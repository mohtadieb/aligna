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
    store?: string;
    environment?: string;
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

  return (
    header === secret ||
    header === `Bearer ${secret}` ||
    header === `bearer ${secret}`
  );
}

serve(async (req) => {
  try {
    if (req.method !== "POST") {
      return json({ error: "Method not allowed" }, 405);
    }

    // ✅ 1. Verify webhook secret
    const secret = Deno.env.get("REVENUECAT_WEBHOOK_SECRET") ?? "";
    if (!secret) {
      return json({ error: "Missing REVENUECAT_WEBHOOK_SECRET" }, 500);
    }

    if (!isAuthorized(req, secret)) {
      return json(
        {
          error: "Unauthorized",
          got: req.headers.get("Authorization") ?? null,
        },
        401,
      );
    }

    const payload = (await req.json()) as RCEvent;
    const e = payload?.event;

    const type = e?.type ?? "";
    const appUserId = e?.app_user_id ?? "";

    if (!appUserId) {
      return json({ error: "Missing app_user_id" }, 400);
    }

    const entitlementIds = (e?.entitlement_ids ?? []) as string[];
    const hasPro = entitlementIds.includes("aligna_pro");

    // ✅ 2. Setup Supabase
    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

    if (!supabaseUrl || !serviceKey) {
      return json(
        { error: "Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY" },
        500,
      );
    }

    const platform = mapPlatform(e?.store);

    const tx =
      e?.transaction_id ??
      e?.original_transaction_id ??
      `${platform}:${appUserId}:aligna_pro:${type}`;

    // =========================
    // ✅ 3. GRANT EVENTS
    // =========================
    const grantTypes = new Set([
      "INITIAL_PURCHASE",
      "NON_RENEWING_PURCHASE",
      "RENEWAL",
      "UNCANCELLATION",
      "PRODUCT_CHANGE",
      "TRANSFER",
      "TEST",
    ]);

    const shouldGrant = hasPro && grantTypes.has(type);

    if (shouldGrant) {
      const insertRes = await fetch(
        `${supabaseUrl}/rest/v1/purchases?on_conflict=user_id,type`,
        {
          method: "POST",
          headers: {
            "content-type": "application/json",
            apikey: serviceKey,
            authorization: `Bearer ${serviceKey}`,
            prefer: "resolution=merge-duplicates,return=representation",
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

      return json({ ok: true, granted: true, appUserId, type });
    }

    // =========================
    // ❌ 4. REVOCATION EVENTS
    // =========================
    const revokeTypes = new Set([
      "CANCELLATION",
      "EXPIRATION",
      "BILLING_ISSUE",
      "REFUND",
    ]);

    const shouldRevoke = revokeTypes.has(type);

    if (shouldRevoke) {
      const deleteRes = await fetch(
        `${supabaseUrl}/rest/v1/purchases?user_id=eq.${appUserId}&type=eq.lifetime_unlock`,
        {
          method: "DELETE",
          headers: {
            apikey: serviceKey,
            authorization: `Bearer ${serviceKey}`,
          },
        },
      );

      if (!deleteRes.ok) {
        const text = await deleteRes.text();
        return json({ error: "Delete failed", details: text }, 500);
      }

      return json({ ok: true, revoked: true, appUserId, type });
    }

    // =========================
    // ℹ️ 5. IGNORE OTHER EVENTS
    // =========================
    return json({
      ok: true,
      ignored: true,
      reason: "event_not_handled",
      type,
      entitlementIds,
      appUserId,
    });

  } catch (err) {
    return json({ error: String(err) }, 500);
  }
});