// supabase/functions/revenuecat_webhook/index.ts
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

type RCEvent = {
  api_version?: string;
  event?: {
    type?: string;
    app_user_id?: string;
    product_id?: string;
    entitlement_ids?: string[] | null;
    transaction_id?: string | null;
    original_transaction_id?: string | null;
    store?: string; // APP_STORE / PLAY_STORE / STRIPE / etc (often uppercase)
    environment?: string; // SANDBOX / PRODUCTION
  };
};

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "content-type": "application/json" },
  });
}

function mapPlatform(storeRaw?: string): "ios" | "android" | "web" | "unknown" {
  const store = (storeRaw ?? "").toLowerCase();
  if (store === "app_store") return "ios";
  if (store === "play_store") return "android";
  if (store === "stripe") return "web";
  return "unknown";
}

function isAuthorized(req: Request, secret: string) {
  const header = (req.headers.get("Authorization") ?? "").trim();

  // Accept BOTH:
  // - "Bearer <secret>"
  // - "bearer <secret>"
  // - "<secret>"
  return (
    header === secret ||
    header === `Bearer ${secret}` ||
    header === `bearer ${secret}`
  );
}

serve(async (req) => {
  try {
    if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

    // ✅ Verify webhook secret
    const secret = Deno.env.get("REVENUECAT_WEBHOOK_SECRET") ?? "";
    if (!secret) return json({ error: "Missing REVENUECAT_WEBHOOK_SECRET" }, 500);

    if (!isAuthorized(req, secret)) {
      return json(
        {
          error: "Unauthorized",
          hint:
            "RevenueCat may send Authorization as the raw secret (no 'Bearer') or as 'Bearer <secret>'. " +
            "This function accepts both formats.",
          got: req.headers.get("Authorization") ?? null,
        },
        401,
      );
    }

    const payload = (await req.json()) as RCEvent;
    const e = payload?.event;

    const type = e?.type ?? "";
    const appUserId = e?.app_user_id ?? "";

    // entitlement_ids can be null in test payloads
    const entitlementIds = (e?.entitlement_ids ?? []) as string[];

    // ✅ Only grant when entitlement is present AND event implies ownership
    const hasPro = entitlementIds.includes("aligna_pro");
    const grantTypes = new Set([
      "INITIAL_PURCHASE",
      "NON_RENEWING_PURCHASE",
      "RENEWAL",
      "UNCANCELLATION",
      "PRODUCT_CHANGE",
      "TRANSFER",
      // NOTE: TEST events usually have no entitlements, but we keep this in case
      // you later add entitlement_ids in a custom test.
      "TEST",
    ]);

    const shouldGrant = hasPro && grantTypes.has(type);

    // If event doesn't include entitlements, ignore (don’t fail)
    if (!shouldGrant) {
      return json({
        ok: true,
        ignored: true,
        reason: hasPro ? "event_type_not_granting" : "missing_entitlement",
        type,
        entitlementIds,
        appUserId: appUserId || null,
      });
    }

    if (!appUserId) return json({ error: "Missing app_user_id" }, 400);

    // ✅ Use your existing secrets (you already created them)
    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
    if (!supabaseUrl || !serviceKey) {
      return json(
        { error: "Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY" },
        500,
      );
    }

    const platform = mapPlatform(e?.store);

    // Prefer real tx IDs if present; otherwise stable fallback for retries
    const tx =
      e?.transaction_id ??
      e?.original_transaction_id ??
      `${platform}:${appUserId}:aligna_pro:${type}`;

    // ✅ Upsert-style insert:
    // This relies on you adding a UNIQUE(user_id, type) constraint (next steps below).
    const insertRes = await fetch(
      `${supabaseUrl}/rest/v1/purchases?on_conflict=user_id,type`,
      {
        method: "POST",
        headers: {
          "content-type": "application/json",
          "apikey": serviceKey,
          "authorization": `Bearer ${serviceKey}`,
          "prefer": "resolution=merge-duplicates,return=representation",
        },
        body: JSON.stringify({
          user_id: appUserId,
          type: "lifetime_unlock",
          platform,
          transaction_id: tx,
        }),
      },
    );

    if (!insertRes.ok) {
      const text = await insertRes.text();
      return json({ error: "Insert failed", details: text }, 500);
    }

    return json({ ok: true, granted: true, appUserId, tx, type, platform });
  } catch (err) {
    return json({ error: String(err) }, 500);
  }
});