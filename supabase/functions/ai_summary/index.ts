// supabase/functions/ai_summary/index.ts
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "content-type": "application/json" },
  });
}

type ReqBody = { sessionId?: string };

function getBearerToken(req: Request): string | null {
  const auth = req.headers.get("Authorization") ?? "";
  if (!auth) return null;

  // Accept:
  // - "Bearer <jwt>"
  // - "<jwt>"
  if (auth.startsWith("Bearer ")) return auth.slice("Bearer ".length).trim();
  return auth.trim();
}

serve(async (req) => {
  try {
    if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
    const openaiKey = Deno.env.get("OPENAI_API_KEY") ?? "";

    if (!supabaseUrl || !serviceKey) {
      return json({ error: "Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY" }, 500);
    }
    if (!openaiKey) return json({ error: "Missing OPENAI_API_KEY" }, 500);

    // 1) Verify user via JWT (we verify ourselves)
    const token = getBearerToken(req);
    if (!token) {
      return json({ error: "Missing Authorization token" }, 401);
    }

    const userRes = await fetch(`${supabaseUrl}/auth/v1/user`, {
      headers: {
        // ✅ Use service key as apikey so you don't need SUPABASE_ANON_KEY at all
        apikey: serviceKey,
        authorization: `Bearer ${token}`,
      },
    });

    if (!userRes.ok) {
      const t = await userRes.text().catch(() => "");
      return json({ error: "Invalid user token", details: t || null }, 401);
    }

    const userJson = await userRes.json();
    const userId = userJson?.id as string | undefined;
    if (!userId) return json({ error: "User not found" }, 401);

    const { sessionId } = (await req.json()) as ReqBody;
    if (!sessionId) return json({ error: "Missing sessionId" }, 400);

    // 2) Check Pro (purchases table)
    const proRes = await fetch(
      `${supabaseUrl}/rest/v1/purchases?select=id&user_id=eq.${userId}&type=eq.lifetime_unlock&limit=1`,
      {
        headers: {
          apikey: serviceKey,
          authorization: `Bearer ${serviceKey}`,
        },
      },
    );

    if (!proRes.ok) {
      const t = await proRes.text().catch(() => "");
      return json({ error: "Failed to check Pro", details: t || null }, 500);
    }

    const proRows = await proRes.json();
    const isPro = Array.isArray(proRows) && proRows.length > 0;
    if (!isPro) return json({ error: "Pro required" }, 403);

    // 3) Load session + responses (server-side)
    const sessionRes = await fetch(
      // ✅ fixed: removed accidental space before id filter
      `${supabaseUrl}/rest/v1/pair_sessions?select=id,created_by,partner_id,status&id=eq.${sessionId}&limit=1`,
      {
        headers: {
          apikey: serviceKey,
          authorization: `Bearer ${serviceKey}`,
        },
      },
    );

    if (!sessionRes.ok) {
      const t = await sessionRes.text().catch(() => "");
      return json({ error: "Failed to load session", details: t || null }, 500);
    }

    const sessionRows = await sessionRes.json();
    const session = sessionRows?.[0];
    if (!session) return json({ error: "Session not found" }, 404);

    // ✅ Your responses columns: id,session_id,user_id,question_id,value,created_at,updated_at
    const responsesRes = await fetch(
      `${supabaseUrl}/rest/v1/responses?select=question_id,user_id,value&session_id=eq.${sessionId}`,
      {
        headers: {
          apikey: serviceKey,
          authorization: `Bearer ${serviceKey}`,
        },
      },
    );

    if (!responsesRes.ok) {
      const t = await responsesRes.text().catch(() => "");
      return json({ error: "Failed to load responses", details: t || null }, 500);
    }

    const responses = await responsesRes.json();

    // 4) Build compact input for LLM
    const compact = (Array.isArray(responses) ? responses : []).map((r) => ({
      q: r.question_id,
      u: r.user_id,
      a: r.value, // ✅ use value
    }));

    const prompt = `
You are an assistant generating a relationship compatibility summary.
Use a warm, neutral tone. Be actionable and respectful.

Return JSON with keys:
- headline (string)
- strengths (array of 3-6 strings)
- risks (array of 3-6 strings)
- discussion_prompts (array of 5-10 strings)
- next_steps (array of 3-6 strings)

Input:
session_status=${session.status}
answers=${JSON.stringify(compact).slice(0, 120000)}
`.trim();

    // 5) Call OpenAI
    const aiRes = await fetch("https://api.openai.com/v1/responses", {
      method: "POST",
      headers: {
        "content-type": "application/json",
        authorization: `Bearer ${openaiKey}`,
      },
      body: JSON.stringify({
        model: "gpt-4.1-mini",
        input: prompt,
        text: { format: { type: "json_object" } },
      }),
    });

    if (!aiRes.ok) {
      const t = await aiRes.text().catch(() => "");
      return json({ error: "OpenAI failed", details: t || null }, 500);
    }

    const aiJson = await aiRes.json();
    const summaryText =
      aiJson?.output_text ??
      aiJson?.output?.[0]?.content?.[0]?.text ??
      null;

    if (!summaryText) return json({ error: "No summary returned" }, 500);

    // 6) Upsert into ai_summaries
    const upsertRes = await fetch(
      `${supabaseUrl}/rest/v1/ai_summaries?on_conflict=session_id,user_id`,
      {
        method: "POST",
        headers: {
          "content-type": "application/json",
          apikey: serviceKey,
          authorization: `Bearer ${serviceKey}`,
          prefer: "resolution=merge-duplicates,return=representation",
        },
        body: JSON.stringify({
          session_id: sessionId,
          user_id: userId,
          summary: summaryText,
        }),
      },
    );

    if (!upsertRes.ok) {
      const t = await upsertRes.text().catch(() => "");
      return json({ error: "Failed to save summary", details: t || null }, 500);
    }

    return json({ ok: true, saved: true });
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});