-- CycleSync: one-shot catch-up.
-- Brings a database that has the initial schema up to date with the app.
-- Safe to run more than once, and whichever earlier updates were or weren't run.
-- Run in Supabase SQL Editor: + New query -> paste all -> Run.

create extension if not exists pgcrypto;

-- =====================================================================
-- Update 2: settings, overlap guard, account deletion
-- =====================================================================
alter table public.profiles
  add column if not exists onboarding_completed boolean not null default false,
  add column if not exists show_fertile_window boolean not null default false;

alter table public.reminder_preferences
  add column if not exists fertile_reminder_enabled boolean not null default false;

create or replace function public.prevent_period_overlap()
returns trigger language plpgsql set search_path = '' as $$
begin
  if exists (
    select 1 from public.periods p
    where p.user_id = new.user_id
      and p.id <> new.id
      and daterange(p.start_date, coalesce(p.end_date, least(greatest(p.start_date, current_date), p.start_date + 13)), '[]')
          && daterange(new.start_date, coalesce(new.end_date, least(greatest(new.start_date, current_date), new.start_date + 13)), '[]')
  ) then
    raise exception 'period_overlap' using errcode = 'P0001',
      hint = 'This period overlaps another recorded period.';
  end if;
  return new;
end;
$$;

drop trigger if exists periods_no_overlap on public.periods;
create trigger periods_no_overlap before insert or update on public.periods
  for each row execute function public.prevent_period_overlap();

create or replace function public.delete_my_account()
returns void language plpgsql security definer set search_path = '' as $$
declare
  uid uuid := auth.uid();
begin
  if uid is null then
    raise exception 'not_signed_in' using errcode = '42501';
  end if;
  delete from auth.users where id = uid;
end;
$$;
revoke execute on function public.delete_my_account() from public, anon;
grant execute on function public.delete_my_account() to authenticated;

-- =====================================================================
-- Update 3 (tables only): web push. The 5-minute scheduler is set up
-- separately because it needs your project address.
-- =====================================================================
create table if not exists public.push_subscriptions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  endpoint text not null,
  p256dh text not null,
  auth text not null,
  created_at timestamptz not null default now(),
  unique (user_id, endpoint)
);

create table if not exists public.scheduled_pushes (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  kind text not null default 'reminder',
  send_at timestamptz not null,
  title text not null default 'CycleSync',
  body text not null default 'You have a CycleSync reminder',
  repeats_daily boolean not null default false,
  created_at timestamptz not null default now()
);
create index if not exists scheduled_pushes_due_idx
  on public.scheduled_pushes(send_at);

create table if not exists public.push_config (
  id smallint primary key default 1 check (id = 1),
  public_key text not null,
  private_key text not null,
  created_at timestamptz not null default now()
);

alter table public.push_subscriptions enable row level security;
alter table public.scheduled_pushes enable row level security;
alter table public.push_config enable row level security;

drop policy if exists "push_subs_select_own" on public.push_subscriptions;
drop policy if exists "push_subs_insert_own" on public.push_subscriptions;
drop policy if exists "push_subs_update_own" on public.push_subscriptions;
drop policy if exists "push_subs_delete_own" on public.push_subscriptions;
create policy "push_subs_select_own" on public.push_subscriptions for select to authenticated
  using (user_id = (select auth.uid()));
create policy "push_subs_insert_own" on public.push_subscriptions for insert to authenticated
  with check (user_id = (select auth.uid()));
create policy "push_subs_update_own" on public.push_subscriptions for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy "push_subs_delete_own" on public.push_subscriptions for delete to authenticated
  using (user_id = (select auth.uid()));

drop policy if exists "scheduled_select_own" on public.scheduled_pushes;
drop policy if exists "scheduled_insert_own" on public.scheduled_pushes;
drop policy if exists "scheduled_delete_own" on public.scheduled_pushes;
create policy "scheduled_select_own" on public.scheduled_pushes for select to authenticated
  using (user_id = (select auth.uid()));
create policy "scheduled_insert_own" on public.scheduled_pushes for insert to authenticated
  with check (user_id = (select auth.uid()));
create policy "scheduled_delete_own" on public.scheduled_pushes for delete to authenticated
  using (user_id = (select auth.uid()));

-- =====================================================================
-- Update 4: health profile, pain, contraception reminders, long gaps,
-- consent, safer web reminders
-- =====================================================================
alter table public.profiles
  add column if not exists contraception text,
  add column if not exists life_stage text not null default 'cycling',
  add column if not exists health_consent_at timestamptz;

alter table public.profiles drop constraint if exists profiles_contraception_check;
alter table public.profiles add constraint profiles_contraception_check
  check (contraception is null or contraception in
    ('none','pill','injection','implant','hormonal_iud','copper_iud','other'));
alter table public.profiles drop constraint if exists profiles_life_stage_check;
alter table public.profiles add constraint profiles_life_stage_check
  check (life_stage in ('cycling','pregnant','postpartum','breastfeeding','perimenopause'));

update public.profiles set timezone = null where timezone is not null;

alter table public.periods add column if not exists gap_is_cycle boolean;

alter table public.daily_logs
  add column if not exists pain smallint,
  add column if not exists pain_disrupted boolean not null default false,
  add column if not exists heavy_soaked boolean not null default false;
alter table public.daily_logs drop constraint if exists daily_logs_pain_check;
alter table public.daily_logs add constraint daily_logs_pain_check
  check (pain is null or pain between 0 and 3);
alter table public.daily_logs drop constraint if exists daily_logs_symptoms_check;
alter table public.daily_logs add constraint daily_logs_symptoms_check
  check (symptoms <@ array['cramps','headache','bloating','acne','breast_tenderness',
    'fatigue','nausea','back_pain','pelvic_pain','hot_flushes','night_sweats',
    'sleep_problems','other']::text[]);

alter table public.reminder_preferences
  add column if not exists pill_reminder_enabled boolean not null default false,
  add column if not exists pill_reminder_time time,
  add column if not exists injection_reminder_enabled boolean not null default false,
  add column if not exists injection_last_date date,
  add column if not exists injection_interval_weeks smallint;
alter table public.reminder_preferences
  drop constraint if exists reminder_preferences_injection_interval_weeks_check;
alter table public.reminder_preferences
  add constraint reminder_preferences_injection_interval_weeks_check
  check (injection_interval_weeks is null or injection_interval_weeks between 4 and 16);

-- Server only ever stores a generic kind and neutral text.
alter table public.scheduled_pushes drop constraint if exists scheduled_pushes_kind_check;
alter table public.scheduled_pushes drop constraint if exists scheduled_pushes_neutral_check;
update public.scheduled_pushes
  set kind = 'reminder', title = 'CycleSync', body = 'You have a CycleSync reminder';
alter table public.scheduled_pushes add constraint scheduled_pushes_kind_check
  check (kind = 'reminder');
alter table public.scheduled_pushes add constraint scheduled_pushes_neutral_check
  check (title = 'CycleSync' and body = 'You have a CycleSync reminder');

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

create table if not exists public.server_secrets (
  name text primary key,
  value text not null
);
alter table public.server_secrets enable row level security;
insert into public.server_secrets (name, value)
  values ('cron', encode(extensions.gen_random_bytes(24), 'hex'))
  on conflict (name) do nothing;

-- If the web-push scheduler already exists, make it send the secret.
do $do$
declare
  fn_url text;
begin
  if to_regclass('cron.job') is null then
    raise notice 'Scheduler not set up yet (optional, for web notifications).';
    return;
  end if;
  execute $q$select substring(command from 'https://[^'']+/functions/v1/send-reminders')
            from cron.job where jobname = 'cyclesync-send-reminders'$q$
    into fn_url;
  if fn_url is null then
    raise notice 'Scheduler not set up yet (optional, for web notifications).';
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

-- Done. You should see "Success" (possibly with a notice about the scheduler).
