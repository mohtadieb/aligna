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
  if (auth.startsWith("Bearer ")) return auth.slice("Bearer ".length).trim();
  return auth.trim();
}

// ---------------- JSON cleaning / repair helpers ----------------

function stripCodeFences(s: string): string {
  let t = (s ?? "").trim();
  t = t.replace(/^\s*```(?:json)?\s*/i, "");
  t = t.replace(/\s*```\s*$/i, "");
  t = t.replace(/^\s*json\s*/i, "");
  return t.trim();
}

function extractFirstJsonObject(s: string): string | null {
  const t = stripCodeFences(s);
  const start = t.indexOf("{");
  if (start < 0) return null;

  // Prefer balanced extraction; fallback to lastIndexOf if needed
  let depth = 0;
  for (let i = start; i < t.length; i++) {
    const ch = t[i];
    if (ch === "{") depth++;
    if (ch === "}") {
      depth--;
      if (depth === 0) return t.slice(start, i + 1).trim();
    }
  }

  const end = t.lastIndexOf("}");
  if (end <= start) return null;
  return t.slice(start, end + 1).trim();
}

function removeTrailingCommas(s: string): string {
  return s.replace(/,\s*([}\]])/g, "$1");
}

function balanceBrackets(s: string): string {
  let curlyOpen = 0;
  let curlyClose = 0;
  let squareOpen = 0;
  let squareClose = 0;

  for (const ch of s) {
    if (ch === "{") curlyOpen++;
    else if (ch === "}") curlyClose++;
    else if (ch === "[") squareOpen++;
    else if (ch === "]") squareClose++;
  }

  let out = s;
  out += "]".repeat(Math.max(0, squareOpen - squareClose));
  out += "}".repeat(Math.max(0, curlyOpen - curlyClose));
  return out;
}

function tryParseJsonObject(
  raw: string,
): { ok: true; value: Record<string, unknown> } | { ok: false; reason: string } {
  const extracted = extractFirstJsonObject(raw);
  if (!extracted) return { ok: false, reason: "No JSON object found in model output" };

  const repaired = balanceBrackets(removeTrailingCommas(extracted));

  try {
    const parsed = JSON.parse(repaired);
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
      return { ok: false, reason: "Parsed JSON is not an object" };
    }
    return { ok: true, value: parsed as Record<string, unknown> };
  } catch (e) {
    return { ok: false, reason: `JSON.parse failed after repair: ${String(e)}` };
  }
}

function enforceShape(obj: Record<string, unknown>) {
  const ensureArray = (k: string) => (Array.isArray(obj[k]) ? obj[k] : []);
  const ensureString = (k: string) => (typeof obj[k] === "string" ? obj[k] : "");

  return {
    headline: ensureString("headline"),
    strengths: (ensureArray("strengths") as unknown[]).map(String).slice(0, 8),
    risks: (ensureArray("risks") as unknown[]).map(String).slice(0, 8),
    discussion_prompts: (ensureArray("discussion_prompts") as unknown[]).map(String).slice(0, 12),
    next_steps: (ensureArray("next_steps") as unknown[]).map(String).slice(0, 8),
  };
}

function fallbackSummary(reason: string) {
  return {
    headline: "Summary temporarily unavailable",
    strengths: ["Try generating again in a moment."],
    risks: [reason],
    discussion_prompts: [
      "What felt most aligned during this session?",
      "What topic felt most different, and why?",
    ],
    next_steps: ["Retry generating the summary.", "Discuss one key mismatch together."],
  };
}

// ---------------- Gemini calls ----------------

async function callGemini(opts: {
  apiKey: string;
  model: string;
  prompt: string;
  maxOutputTokens?: number;
  temperature?: number;
}) {
  const { apiKey, model, prompt } = opts;

  const url = `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${apiKey}`;

  const res = await fetch(url, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      contents: [{ role: "user", parts: [{ text: prompt }] }],
      generationConfig: {
        temperature: opts.temperature ?? 0.4,
        maxOutputTokens: opts.maxOutputTokens ?? 4096,
        responseMimeType: "application/json",
      },
    }),
  });

  const text = await res.text().catch(() => "");
  if (!res.ok) {
    return { ok: false as const, status: res.status, raw: text };
  }

  let outText = "";
  try {
    const j = JSON.parse(text);
    outText =
      j?.candidates?.[0]?.content?.parts?.[0]?.text ??
      j?.candidates?.[0]?.content?.parts?.map((p: any) => p?.text ?? "").join("") ??
      "";
  } catch (_) {
    outText = text;
  }

  return { ok: true as const, raw: outText };
}

async function sleep(ms: number) {
  return new Promise((r) => setTimeout(r, ms));
}

async function callGeminiWithFallback(opts: {
  apiKey: string;
  models: string[];
  prompt: string;
  maxOutputTokens?: number;
  temperature?: number;
}) {
  const { apiKey, models, prompt } = opts;

  let lastErr: any = null;

  for (const model of models) {
    // First attempt
    const first = await callGemini({
      apiKey,
      model,
      prompt,
      temperature: opts.temperature ?? 0.4,
      maxOutputTokens: opts.maxOutputTokens ?? 4096,
    });

    if (first.ok) return { ok: true as const, modelUsed: model, raw: first.raw };

    // 503: retry once after short delay
    if (first.status === 503) {
      await sleep(650);
      const retry = await callGemini({
        apiKey,
        model,
        prompt,
        temperature: opts.temperature ?? 0.4,
        maxOutputTokens: opts.maxOutputTokens ?? 4096,
      });
      if (retry.ok) return { ok: true as const, modelUsed: model, raw: retry.raw };
      lastErr = retry;
      continue;
    }

    // 404: try next model
    lastErr = first;
    continue;
  }

  return { ok: false as const, lastErr };
}

serve(async (req) => {
  try {
    if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

    const geminiKey = Deno.env.get("GEMINI_API_KEY") ?? "";
    const primaryModel = Deno.env.get("GEMINI_MODEL") ?? "gemini-3-flash-preview";

    // Fallbacks if primary 404s (you can adjust anytime)
    const modelFallbacks = [
      primaryModel,
      "gemini-3-flash-preview",
      "gemini-3-pro-preview",
    ];

    if (!supabaseUrl || !serviceKey) {
      return json({ error: "Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY" }, 500);
    }
    if (!geminiKey) return json({ error: "Missing GEMINI_API_KEY" }, 500);

    // 1) Verify user via JWT (we verify ourselves)
    const token = getBearerToken(req);
    if (!token) return json({ error: "Missing Authorization token" }, 401);

    const userRes = await fetch(`${supabaseUrl}/auth/v1/user`, {
      headers: { apikey: serviceKey, authorization: `Bearer ${token}` },
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
      { headers: { apikey: serviceKey, authorization: `Bearer ${serviceKey}` } },
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
      `${supabaseUrl}/rest/v1/pair_sessions?select=id,created_by,partner_id,status&id=eq.${sessionId}&limit=1`,
      { headers: { apikey: serviceKey, authorization: `Bearer ${serviceKey}` } },
    );

    if (!sessionRes.ok) {
      const t = await sessionRes.text().catch(() => "");
      return json({ error: "Failed to load session", details: t || null }, 500);
    }

    const sessionRows = await sessionRes.json();
    const session = sessionRows?.[0];
    if (!session) return json({ error: "Session not found" }, 404);

    const responsesRes = await fetch(
      `${supabaseUrl}/rest/v1/responses?select=question_id,user_id,value&session_id=eq.${sessionId}`,
      { headers: { apikey: serviceKey, authorization: `Bearer ${serviceKey}` } },
    );

    if (!responsesRes.ok) {
      const t = await responsesRes.text().catch(() => "");
      return json({ error: "Failed to load responses", details: t || null }, 500);
    }

    const responses = await responsesRes.json();
    const compact = (Array.isArray(responses) ? responses : []).map((r) => ({
      q: r.question_id,
      u: r.user_id,
      a: r.value,
    }));

    const prompt = `
You generate a relationship compatibility summary.

Return ONLY valid JSON (no markdown, no code fences, no commentary).
JSON keys EXACTLY:
headline (string),
strengths (array of 3-6 strings),
risks (array of 3-6 strings),
discussion_prompts (array of 5-10 strings),
next_steps (array of 3-6 strings)

Tone: warm, neutral, actionable, respectful.

session_status=${session.status}
answers=${JSON.stringify(compact).slice(0, 90000)}
`.trim();

    // 4) Call Gemini with fallback + retry
    const first = await callGeminiWithFallback({
      apiKey: geminiKey,
      models: modelFallbacks,
      prompt,
      temperature: 0.4,
      maxOutputTokens: 4096,
    });

    if (!first.ok) {
      const errText = first.lastErr?.raw ?? null;
      return json({ error: "Gemini failed", details: errText }, 500);
    }

    // 5) Parse / repair JSON, retry once if needed
    let parsed = tryParseJsonObject(first.raw);

    if (!parsed.ok) {
      const fixPrompt = `
Fix the following to be STRICTLY valid JSON.
Return ONLY the corrected JSON object (no markdown).

BROKEN_JSON:
${first.raw}
`.trim();

      const second = await callGeminiWithFallback({
        apiKey: geminiKey,
        models: modelFallbacks,
        prompt: fixPrompt,
        temperature: 0.0,
        maxOutputTokens: 3072,
      });

      if (!second.ok) {
        // Best-effort fallback instead of hard failing the whole request:
        const shapedFallback = fallbackSummary("AI output could not be repaired into JSON.");
        const summaryString = JSON.stringify(shapedFallback);

        await fetch(`${supabaseUrl}/rest/v1/ai_summaries?on_conflict=session_id,user_id`, {
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
            summary: summaryString,
          }),
        }).catch(() => {});

        return json({ ok: true, summary: shapedFallback, note: "Fallback summary returned" }, 200);
      }

      parsed = tryParseJsonObject(second.raw);
      if (!parsed.ok) {
        const shapedFallback = fallbackSummary("AI output was invalid JSON.");
        const summaryString = JSON.stringify(shapedFallback);

        await fetch(`${supabaseUrl}/rest/v1/ai_summaries?on_conflict=session_id,user_id`, {
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
            summary: summaryString,
          }),
        }).catch(() => {});

        return json({ ok: true, summary: shapedFallback, note: "Fallback summary returned" }, 200);
      }
    }

    const shaped = enforceShape(parsed.value);
    const summaryString = JSON.stringify(shaped);

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
        body: JSON.stringify({ session_id: sessionId, user_id: userId, summary: summaryString }),
      },
    );

    if (!upsertRes.ok) {
      const t = await upsertRes.text().catch(() => "");
      return json({ error: "Failed to save summary", details: t || null }, 500);
    }

    return json({ ok: true, summary: shaped }, 200);
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});