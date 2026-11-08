// CycleSync: send-reminders Edge Function.
//
// GET  -> returns the public web-push key the app needs to subscribe.
// POST -> sends every reminder that is due. Called every 5 minutes by pg_cron
//         with the x-cron-secret header (see migration 4).
//
// Deploy with "Verify JWT" OFF. GET only returns a public key; POST requires
// the scheduler's secret. Reminder text stored on the server is always neutral.

import { createClient } from "npm:@supabase/supabase-js@2";
import webpush from "npm:web-push@3.6.7";

const CONTACT = "mailto:cyclesync-push@users.noreply.github.com";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "GET, OPTIONS",
};

const db = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  { auth: { persistSession: false } },
);

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
}

/** Constant-time string comparison. */
function safeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

async function cronSecretOk(req: Request): Promise<boolean> {
  const given = req.headers.get("x-cron-secret") ?? "";
  if (!given) return false;
  const { data } = await db
    .from("server_secrets")
    .select("value")
    .eq("name", "cron")
    .maybeSingle();
  return !!data?.value && safeEqual(given, data.value);
}

/** Loads the web-push keys, creating them the first time. */
async function vapidKeys(): Promise<{ publicKey: string; privateKey: string }> {
  const { data } = await db
    .from("push_config")
    .select("public_key, private_key")
    .eq("id", 1)
    .maybeSingle();
  if (data) return { publicKey: data.public_key, privateKey: data.private_key };

  const keys = webpush.generateVAPIDKeys();
  await db.from("push_config").upsert(
    { id: 1, public_key: keys.publicKey, private_key: keys.privateKey },
    { onConflict: "id", ignoreDuplicates: true },
  );
  const { data: again } = await db
    .from("push_config")
    .select("public_key, private_key")
    .eq("id", 1)
    .single();
  return { publicKey: again!.public_key, privateKey: again!.private_key };
}

async function sendDue(): Promise<{ sent: number; skipped: number }> {
  const keys = await vapidKeys();
  webpush.setVapidDetails(CONTACT, keys.publicKey, keys.privateKey);

  // Claims due reminders atomically (moves repeating ones to their next time,
  // deletes one-off ones), so overlapping runs never double-send.
  const { data: due, error } = await db.rpc("claim_due_pushes");
  if (error) throw error;

  let sent = 0;
  let skipped = 0;
  for (const r of due ?? []) {
    if (r.late) {
      skipped++;
      continue;
    }
    const { data: subs } = await db
      .from("push_subscriptions")
      .select("id, endpoint, p256dh, auth")
      .eq("user_id", r.user_id);
    for (const s of subs ?? []) {
      try {
        await webpush.sendNotification(
          { endpoint: s.endpoint, keys: { p256dh: s.p256dh, auth: s.auth } },
          JSON.stringify({ title: r.title, body: r.body, tag: "cyclesync" }),
          { TTL: 6 * 60 * 60 },
        );
        sent++;
      } catch (e) {
        const code = (e as { statusCode?: number }).statusCode;
        if (code === 404 || code === 410) {
          await db.from("push_subscriptions").delete().eq("id", s.id);
        }
      }
    }
  }
  return { sent, skipped };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    if (req.method === "GET") {
      const { publicKey } = await vapidKeys();
      return json({ publicKey });
    }
    if (req.method === "POST") {
      if (!(await cronSecretOk(req))) return json({ error: "forbidden" }, 403);
      return json(await sendDue());
    }
    return json({ error: "method_not_allowed" }, 405);
  } catch (_e) {
    // No details: errors could include personal data.
    return json({ error: "server_error" }, 500);
  }
});
