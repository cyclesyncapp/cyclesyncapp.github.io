-- CycleSync migration 4: review fixes (health profile, pain, contraception
-- reminders, long cycles, consent, safer web reminders).
-- Run once in the Supabase SQL Editor after migration 3. No edits needed.

-- ---------- Health profile & consent ----------
alter table public.profiles
  add column if not exists contraception text
    check (contraception is null or contraception in
      ('none','pill','injection','implant','hormonal_iud','copper_iud','other')),
  add column if not exists life_stage text not null default 'cycling'
    check (life_stage in ('cycling','pregnant','postpartum','breastfeeding','perimenopause')),
  add column if not exists health_consent_at timestamptz;

-- Stop storing the unused time-zone abbreviation.
update public.profiles set timezone = null where timezone is not null;

-- ---------- Long gaps: was the gap before this period a real cycle? ----------
-- null = not answered, true = real (long) cycle, false = missed logging.
alter table public.periods
  add column if not exists gap_is_cycle boolean;

-- ---------- Pain and heavy-bleeding detail; new symptoms ----------
alter table public.daily_logs
  add column if not exists pain smallint check (pain is null or pain between 0 and 3),
  add column if not exists pain_disrupted boolean not null default false,
  add column if not exists heavy_soaked boolean not null default false;

alter table public.daily_logs drop constraint if exists daily_logs_symptoms_check;
alter table public.daily_logs add constraint daily_logs_symptoms_check
  check (symptoms <@ array['cramps','headache','bloating','acne','breast_tenderness',
    'fatigue','nausea','back_pain','pelvic_pain','hot_flushes','night_sweats',
    'sleep_problems','other']::text[]);

-- ---------- Contraception reminders ----------
alter table public.reminder_preferences
  add column if not exists pill_reminder_enabled boolean not null default false,
  add column if not exists pill_reminder_time time,
  add column if not exists injection_reminder_enabled boolean not null default false,
  add column if not exists injection_last_date date,
  add column if not exists injection_interval_weeks smallint
    check (injection_interval_weeks is null or injection_interval_weeks between 4 and 16);

-- ---------- Safer web reminders ----------
-- The server only ever stores a generic kind and neutral text.
alter table public.scheduled_pushes drop constraint if exists scheduled_pushes_kind_check;
update public.scheduled_pushes
  set kind = 'reminder', title = 'CycleSync', body = 'You have a CycleSync reminder';
alter table public.scheduled_pushes add constraint scheduled_pushes_kind_check
  check (kind = 'reminder');
alter table public.scheduled_pushes add constraint scheduled_pushes_neutral_check
  check (title = 'CycleSync' and body = 'You have a CycleSync reminder');

-- Replace the signed-in user's reminders in one transaction.
create or replace function public.replace_my_scheduled_pushes(items jsonb)
returns void language plpgsql security invoker set search_path = '' as $$
declare
  uid uuid := auth.uid();
begin
  if uid is null then
    raise exception 'not_signed_in' using errcode = '42501';
  end if;
  delete from public.scheduled_pushes where user_id = uid;
  insert into public.scheduled_pushes (user_id, kind, send_at, title, body, repeats_daily)
  select uid, 'reminder', (i->>'send_at')::timestamptz,
         'CycleSync', 'You have a CycleSync reminder',
         coalesce((i->>'repeats_daily')::boolean, false)
  from jsonb_array_elements(coalesce(items, '[]'::jsonb)) as i
  limit 20;
end;
$$;
revoke execute on function public.replace_my_scheduled_pushes(jsonb) from public, anon;
grant execute on function public.replace_my_scheduled_pushes(jsonb) to authenticated;

-- Atomically claim due reminders so two runs never send the same one.
create or replace function public.claim_due_pushes()
returns table (user_id uuid, title text, body text, late boolean)
language plpgsql security definer set search_path = '' as $$
#variable_conflict use_column
begin
  return query
  with due as (
    select s.id, s.user_id, s.title, s.body, s.send_at, s.repeats_daily
    from public.scheduled_pushes s
    where s.send_at <= now()
    order by s.send_at
    limit 500
    for update skip locked
  ),
  moved as (
    update public.scheduled_pushes s
      set send_at = d.send_at + ceil(extract(epoch from (now() - d.send_at)) / 86400.0 + 0.000001)
                    * interval '1 day'
    from due d
    where s.id = d.id and d.repeats_daily
    returning s.id
  ),
  removed as (
    delete from public.scheduled_pushes s
    using due d
    where s.id = d.id and not d.repeats_daily
    returning s.id
  )
  select d.user_id, d.title, d.body, (now() - d.send_at) > interval '12 hours'
  from due d;
end;
$$;
revoke execute on function public.claim_due_pushes() from public, anon, authenticated;

-- ---------- Secret for the scheduler ----------
create table if not exists public.server_secrets (
  name text primary key,
  value text not null
);
alter table public.server_secrets enable row level security;
insert into public.server_secrets (name, value)
  values ('cron', encode(extensions.gen_random_bytes(24), 'hex'))
  on conflict (name) do nothing;

-- Re-create the 5-minute job so it sends the secret. Reuses the URL from the
-- job created in migration 3, so nothing needs editing here.
do $do$
declare
  fn_url text;
begin
  select substring(command from 'https://[^'']+/functions/v1/send-reminders')
    into fn_url
    from cron.job where jobname = 'cyclesync-send-reminders';
  if fn_url is null then
    raise notice 'Scheduler job not found. Run migration 3 first.';
    return;
  end if;
  perform cron.unschedule('cyclesync-send-reminders');
  perform cron.schedule(
    'cyclesync-send-reminders',
    '*/5 * * * *',
    format(
      $job$select net.http_post(
        url := %L,
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'x-cron-secret', (select value from public.server_secrets where name = 'cron')),
        body := '{}'::jsonb);$job$,
      fn_url)
  );
end;
$do$;
