// supabase/functions/ai_summary/index.ts
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

function json(
  data: unknown,
  status = 200,
  extraHeaders: Record<string, string> = {},
) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "content-type": "application/json", ...extraHeaders },
  });
}

type ReqBody = { sessionId?: string };

function getBearerToken(req: Request): string | null {
  const auth = req.headers.get("Authorization") ?? "";
  if (!auth) return null;
  if (auth.startsWith("Bearer ")) return auth.slice("Bearer ".length).trim();
  return auth.trim();
}

// ---------------- Generic retrying fetch ----------------

function isRetryableStatus(s: number) {
  return s === 429 || s === 502 || s === 503 || s === 504;
}

function looksLikeConnectionReset(err: unknown) {
  const msg = String(err ?? "");
  return (
    msg.toLowerCase().includes("connection reset") ||
    msg.toLowerCase().includes("connection error") ||
    msg.toLowerCase().includes("sendrequest") ||
    msg.toLowerCase().includes("timed out") ||
    msg.toLowerCase().includes("timeout") ||
    msg.toLowerCase().includes("network")
  );
}

function isAbortError(err: unknown) {
  const msg = String(err ?? "").toLowerCase();
  return (
    msg.includes("aborterror") ||
    msg.includes("aborted") ||
    msg.includes("the signal has been aborted")
  );
}

async function sleep(ms: number) {
  return new Promise((r) => setTimeout(r, ms));
}

async function fetchWithRetry(
  url: string,
  init: RequestInit,
  opts?: {
    retries?: number;
    baseDelayMs?: number;
    timeoutMs?: number;
    retryOnStatuses?: boolean;
  },
): Promise<Response> {
  const retries = opts?.retries ?? 3;
  const baseDelayMs = opts?.baseDelayMs ?? 350;
  const timeoutMs = opts?.timeoutMs ?? 12_000;
  const retryOnStatuses = opts?.retryOnStatuses ?? true;

  let lastErr: unknown = null;

  for (let attempt = 0; attempt <= retries; attempt++) {
    const controller = new AbortController();
    const t = setTimeout(() => controller.abort(), timeoutMs);

    try {
      const res = await fetch(url, { ...init, signal: controller.signal });
      clearTimeout(t);

      if (retryOnStatuses && isRetryableStatus(res.status) && attempt < retries) {
        const delay = baseDelayMs * Math.pow(2, attempt);
        await sleep(delay);
        continue;
      }

      return res;
    } catch (e) {
      clearTimeout(t);
      lastErr = e;

      const retryable = looksLikeConnectionReset(e) || isAbortError(e);
      if (!retryable || attempt >= retries) throw e;

      const delay = baseDelayMs * Math.pow(2, attempt);
      await sleep(delay);
      continue;
    }
  }

  throw lastErr ?? new Error("fetchWithRetry failed");
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

// ---------------- Audit logging ----------------

async function logAiEvent(opts: {
  supabaseUrl: string;
  serviceKey: string;
  sessionId: string;
  userId: string;
  event: string;
  details?: Record<string, unknown> | null;
}) {
  const { supabaseUrl, serviceKey, sessionId, userId, event, details } = opts;

  const url = `${supabaseUrl}/rest/v1/ai_generation_events`;

  try {
    await fetchWithRetry(
      url,
      {
        method: "POST",
        headers: {
          "content-type": "application/json",
          apikey: serviceKey,
          authorization: `Bearer ${serviceKey}`,
          prefer: "return=minimal",
        },
        body: JSON.stringify({
          session_id: sessionId,
          user_id: userId,
          event,
          details: details ?? null,
        }),
      },
      { retries: 2, baseDelayMs: 200, timeoutMs: 8000, retryOnStatuses: true },
    );
  } catch (_) {}
}

// ---------------- Gemini calls ----------------

function extractRetryDelaySecondsFromGeminiError(raw: string): number | null {
  try {
    const j = JSON.parse(raw);
    const details = Array.isArray(j?.error?.details) ? j.error.details : [];
    const retryInfo = details.find((d: any) =>
      String(d?.["@type"] ?? "").includes("google.rpc.RetryInfo")
    );
    const retryDelay = retryInfo?.retryDelay;
    if (typeof retryDelay === "string" && retryDelay.endsWith("s")) {
      const n = Number(retryDelay.slice(0, -1));
      return Number.isFinite(n) ? n : null;
    }
  } catch (_) {}
  return null;
}

async function callGemini(opts: {
  apiKey: string;
  model: string;
  prompt: string;
  maxOutputTokens?: number;
  temperature?: number;
}) {
  const { apiKey, model, prompt } = opts;
  const url =
    `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${apiKey}`;

  let res: Response;
  let text = "";

  try {
    res = await fetchWithRetry(
      url,
      {
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
      },
      // ✅ Longer timeout so high-token generations don't get aborted.
      { retries: 1, baseDelayMs: 650, timeoutMs: 120_000, retryOnStatuses: false },
    );

    text = await res.text().catch(() => "");
  } catch (e) {
    // ✅ Treat aborts like "still generating" so client can poll.
    if (isAbortError(e)) {
      return { ok: false as const, status: 202, raw: "AbortError: request timed out locally" };
    }
    return { ok: false as const, status: 0, raw: String(e) };
  }

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
    const first = await callGemini({
      apiKey,
      model,
      prompt,
      temperature: opts.temperature ?? 0.4,
      maxOutputTokens: opts.maxOutputTokens ?? 4096,
    });

    if (first.ok) return { ok: true as const, modelUsed: model, raw: first.raw };

    // If our local timeout/abort triggered, stop trying other models and let client poll.
    if (first.status === 202) {
      return { ok: false as const, lastErr: first };
    }

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

    lastErr = first;
  }

  return { ok: false as const, lastErr };
}

// ---------------- Metrics fetch + tone selection + prompt ----------------

async function fetchCompatibilityMetrics(opts: {
  supabaseUrl: string;
  serviceKey: string;
  sessionId: string;
}) {
  const { supabaseUrl, serviceKey, sessionId } = opts;

  const res = await fetchWithRetry(
    `${supabaseUrl}/rest/v1/rpc/get_session_compatibility_metrics`,
    {
      method: "POST",
      headers: {
        "content-type": "application/json",
        apikey: serviceKey,
        authorization: `Bearer ${serviceKey}`,
      },
      body: JSON.stringify({ p_session_id: sessionId }),
    },
    { retries: 3, baseDelayMs: 350, timeoutMs: 12_000, retryOnStatuses: true },
  );

  const raw = await res.text().catch(() => "");
  if (!res.ok) {
    console.error("metrics rpc failed:", res.status, raw);
    return null;
  }

  try {
    return JSON.parse(raw);
  } catch (_) {
    console.error("metrics rpc returned non-json:", raw.slice(0, 500));
    return null;
  }
}

type ToneProfile = "CELEBRATORY_GROWTH" | "BALANCED_GROWTH" | "GENTLE_STRUCTURED";

function computeToneProfile(metrics: any | null): {
  tone: ToneProfile;
  rationale: string;
  severity: number | null;
  overall: number | null;
} {
  const overall = typeof metrics?.overall_score === "number" ? metrics.overall_score : null;

  let severity: number | null = null;

  const top = Array.isArray(metrics?.top_mismatched_questions)
    ? metrics.top_mismatched_questions
    : [];

  if (top.length > 0) {
    let maxWeighted = 0;
    for (const q of top) {
      const mismatchPct = typeof q?.mismatch_pct === "number" ? q.mismatch_pct : null; // 0..100
      const weight = typeof q?.weight === "number" ? q.weight : 1; // 1..3
      if (mismatchPct == null) continue;

      const weighted = (mismatchPct / 100) * Math.max(1, Math.min(3, weight));
      if (weighted > maxWeighted) maxWeighted = weighted;
    }
    severity = Math.min(1, maxWeighted / 3);
  }

  const highSeverity = severity != null && severity >= 0.72;
  const midSeverity = severity != null && severity >= 0.45;

  let tone: ToneProfile;
  if (overall == null) {
    tone = "BALANCED_GROWTH";
  } else if (overall >= 80) {
    tone = highSeverity ? "BALANCED_GROWTH" : "CELEBRATORY_GROWTH";
  } else if (overall >= 55) {
    tone = highSeverity ? "GENTLE_STRUCTURED" : "BALANCED_GROWTH";
  } else {
    tone = "GENTLE_STRUCTURED";
  }

  const rationale =
    `overall=${overall ?? "n/a"}, severity=${severity == null ? "n/a" : severity.toFixed(2)}, ` +
    `rule=${tone}${highSeverity ? " (severity override)" : midSeverity ? " (severity noted)" : ""}`;

  return { tone, rationale, severity, overall };
}

function toneInstruction(tone: ToneProfile) {
  switch (tone) {
    case "CELEBRATORY_GROWTH":
      return `
TONE_PROFILE=CELEBRATORY_GROWTH
- Style: warm, optimistic, celebratory, affectionate but not cheesy.
- Still include 1–2 meaningful growth edges (no perfection language).
- Avoid minimizing mismatches; frame them as "tuning" and "alignment choices".
`.trim();
    case "BALANCED_GROWTH":
      return `
TONE_PROFILE=BALANCED_GROWTH
- Style: practical, calm, constructive, emotionally intelligent.
- Normalize differences; emphasize tradeoffs, negotiation, and curiosity.
- Keep risks gentle and actionable (no alarmist language).
`.trim();
    case "GENTLE_STRUCTURED":
      return `
TONE_PROFILE=GENTLE_STRUCTURED
- Style: gentle, supportive, structured, non-judgmental.
- Avoid doom language. Avoid "red flag" phrasing.
- Focus on clarity, values, boundaries, and step-by-step conversations.
- Make next_steps especially concrete and paced.
`.trim();
  }
}

function buildSummaryPrompt(args: {
  sessionStatus: string;
  compactedAnswers: Array<{ q: string; u: string; a: unknown }>;
  metrics: any | null;
  tone: ToneProfile;
}) {
  const { sessionStatus, compactedAnswers, metrics, tone } = args;

  const metricsBlock = metrics
    ? `
COMPATIBILITY METRICS (primary evidence; use these to prioritize what matters):
- overall_score: ${metrics.overall_score} / 100

- strongest_modules (top 3):
${JSON.stringify(metrics.strongest_modules)}

- highest_mismatch_modules (top 3):
${JSON.stringify(metrics.highest_mismatch_modules)}

- top_mismatched_questions (top 5):
${JSON.stringify(metrics.top_mismatched_questions)}

How to use:
- Use strongest_modules to choose Strengths that feel specific (not generic).
- Use highest_mismatch_modules + top_mismatched_questions to choose Risks + Discussion Prompts.
- Do NOT mention UUIDs or internal IDs in the final output.
- Paraphrase question_text naturally.
- If values are short (e.g., "3", "yes/no"), interpret as preferences/importance without overclaiming.
`
    : `
COMPATIBILITY METRICS:
- Not available. Use answers only; avoid numeric claims about compatibility.
`;

  return `
You generate a relationship compatibility summary for TWO people.

Return ONLY valid JSON (no markdown, no code fences, no commentary).
JSON keys EXACTLY:
headline (string),
strengths (array of 3-6 strings),
risks (array of 3-6 strings),
discussion_prompts (array of 5-10 strings),
next_steps (array of 3-6 strings)

GLOBAL RULES:
- Be culturally sensitive and respectful.
- Avoid moralizing. Avoid diagnosis/therapy language. Do not shame either person.
- Do not mention "AI", "model", "Gemini", "prompt", "tokens", or internal systems.

SESSION CONTEXT:
session_status=${sessionStatus}

${toneInstruction(tone)}

${metricsBlock}

SUPPORTING ANSWERS (compact; may include free-text):
answers=${JSON.stringify(compactedAnswers).slice(0, 90000)}

QUALITY RULES:
- Prioritize top mismatched questions for Risks + Discussion Prompts.
- Use strongest modules for Strengths.
- Do not invent facts not supported by metrics/answers.
`.trim();
}

// ---------------- Save helpers ----------------

async function upsertAiSummary(opts: {
  supabaseUrl: string;
  serviceKey: string;
  sessionId: string;
  userId: string;
  summaryString: string;
  metrics: any | null;
}) {
  const { supabaseUrl, serviceKey, sessionId, userId, summaryString, metrics } = opts;

  const baseUrl = `${supabaseUrl}/rest/v1/ai_summaries?on_conflict=session_id,user_id`;

  const bodyWithMetrics = JSON.stringify({
    session_id: sessionId,
    user_id: userId,
    summary: summaryString,
    metrics: metrics ?? null,
  });

  const bodyWithoutMetrics = JSON.stringify({
    session_id: sessionId,
    user_id: userId,
    summary: summaryString,
  });

  const headers = {
    "content-type": "application/json",
    apikey: serviceKey,
    authorization: `Bearer ${serviceKey}`,
    prefer: "resolution=merge-duplicates,return=representation",
  };

  const first = await fetchWithRetry(
    baseUrl,
    { method: "POST", headers, body: bodyWithMetrics },
    { retries: 3, baseDelayMs: 350, timeoutMs: 12_000, retryOnStatuses: true },
  );

  if (first.ok) return { ok: true as const };

  const t1 = await first.text().catch(() => "");

  const missingMetricsCol =
    t1.includes('column "metrics" of relation "ai_summaries" does not exist') ||
    t1.includes("Could not find the 'metrics' column") ||
    (t1.toLowerCase().includes("metrics") && t1.toLowerCase().includes("does not exist"));

  if (missingMetricsCol) {
    const second = await fetchWithRetry(
      baseUrl,
      { method: "POST", headers, body: bodyWithoutMetrics },
      { retries: 3, baseDelayMs: 350, timeoutMs: 12_000, retryOnStatuses: true },
    );

    if (second.ok) return { ok: true as const };

    const t2 = await second.text().catch(() => "");
    return { ok: false as const, details: t2 || null };
  }

  return { ok: false as const, details: t1 || null };
}

async function upsertCoupleSummary(opts: {
  supabaseUrl: string;
  serviceKey: string;
  sessionId: string;
  summaryString: string;
  metrics: any | null;
  generatedBy: string;
}) {
  const { supabaseUrl, serviceKey, sessionId, summaryString, metrics, generatedBy } = opts;

  const url = `${supabaseUrl}/rest/v1/ai_couple_summaries?on_conflict=session_id`;

  const headers = {
    "content-type": "application/json",
    apikey: serviceKey,
    authorization: `Bearer ${serviceKey}`,
    prefer: "resolution=merge-duplicates,return=representation",
  };

  // Keep minimal here for schema compatibility; status/error handled by patch with fallback.
  const body = JSON.stringify({
    session_id: sessionId,
    summary: summaryString,
    metrics: metrics ?? null,
    generated_by: generatedBy,
  });

  const res = await fetchWithRetry(
    url,
    { method: "POST", headers, body },
    { retries: 3, baseDelayMs: 350, timeoutMs: 12_000, retryOnStatuses: true },
  );

  if (res.ok) return { ok: true as const };

  const t = await res.text().catch(() => "");
  return { ok: false as const, details: t || null };
}

// ---------------- Race-safe claim + status updates ----------------

type ClaimResult = { claimed: boolean; current_status: string; existing_summary: string | null };

async function claimCoupleSummaryGeneration(opts: {
  supabaseUrl: string;
  serviceKey: string;
  sessionId: string;
  userId: string;
}) {
  const { supabaseUrl, serviceKey, sessionId, userId } = opts;

  const url = `${supabaseUrl}/rest/v1/rpc/claim_couple_summary_generation`;

  const res = await fetchWithRetry(
    url,
    {
      method: "POST",
      headers: {
        "content-type": "application/json",
        apikey: serviceKey,
        authorization: `Bearer ${serviceKey}`,
      },
      body: JSON.stringify({
        p_session_id: sessionId,
        p_user_id: userId,
        p_lock_seconds: 180,
      }),
    },
    { retries: 3, baseDelayMs: 350, timeoutMs: 12_000, retryOnStatuses: true },
  );

  const raw = await res.text().catch(() => "");
  if (!res.ok) {
    console.error("claim rpc failed:", res.status, raw);
    throw new Error(`claim rpc failed: status=${res.status} body=${raw}`);
  }

  try {
    const parsed = JSON.parse(raw);
    if (Array.isArray(parsed) && parsed.length > 0) return parsed[0] as ClaimResult;
    if (parsed && typeof parsed === "object") return parsed as ClaimResult;
  } catch (_) {
    console.error("claim rpc returned non-json:", raw.slice(0, 500));
  }
  return null;
}

async function patchCoupleSummaryWithFallback(opts: {
  supabaseUrl: string;
  serviceKey: string;
  sessionId: string;
  patch: Record<string, unknown>;
}) {
  const { supabaseUrl, serviceKey, sessionId, patch } = opts;

  const url = `${supabaseUrl}/rest/v1/ai_couple_summaries?session_id=eq.${sessionId}`;

  const headers = {
    "content-type": "application/json",
    apikey: serviceKey,
    authorization: `Bearer ${serviceKey}`,
    prefer: "return=minimal",
  };

  const res1 = await fetchWithRetry(
    url,
    { method: "PATCH", headers, body: JSON.stringify(patch) },
    { retries: 2, baseDelayMs: 250, timeoutMs: 12_000, retryOnStatuses: true },
  );

  if (res1.ok) return true;

  const t1 = await res1.text().catch(() => "");

  const looksLikeMissingCol =
    t1.toLowerCase().includes("does not exist") ||
    t1.toLowerCase().includes("could not find");

  if (!looksLikeMissingCol) {
    console.error("update couple summary failed:", res1.status, t1);
    return false;
  }

  const minimal: Record<string, unknown> = {};
  for (const k of ["summary", "metrics", "generated_by", "updated_at"]) {
    if (k in patch) minimal[k] = patch[k];
  }

  const res2 = await fetchWithRetry(
    url,
    { method: "PATCH", headers, body: JSON.stringify(minimal) },
    { retries: 2, baseDelayMs: 250, timeoutMs: 12_000, retryOnStatuses: true },
  );

  if (res2.ok) return true;

  const t2 = await res2.text().catch(() => "");
  console.error("update couple summary (fallback) failed:", res2.status, t2);
  return false;
}

async function fetchCoupleSummaryRow(opts: {
  supabaseUrl: string;
  serviceKey: string;
  sessionId: string;
}) {
  const { supabaseUrl, serviceKey, sessionId } = opts;

  const urlFull =
    `${supabaseUrl}/rest/v1/ai_couple_summaries?select=session_id,summary,status,generated_by,updated_at,error_message&session_id=eq.${sessionId}&limit=1`;
  const urlMinimal =
    `${supabaseUrl}/rest/v1/ai_couple_summaries?select=session_id,summary,generated_by,updated_at&session_id=eq.${sessionId}&limit=1`;

  const headers = {
    apikey: serviceKey,
    authorization: `Bearer ${serviceKey}`,
  };

  const tryFetch = async (url: string) => {
    const res = await fetchWithRetry(
      url,
      { headers },
      { retries: 2, baseDelayMs: 250, timeoutMs: 12_000, retryOnStatuses: true },
    );
    const raw = await res.text().catch(() => "");
    if (!res.ok) return { ok: false as const, raw };
    try {
      const arr = JSON.parse(raw);
      return { ok: true as const, row: Array.isArray(arr) && arr.length > 0 ? arr[0] : null };
    } catch (_) {
      return { ok: false as const, raw };
    }
  };

  const a = await tryFetch(urlFull);
  if (a.ok) return a.row;

  const b = await tryFetch(urlMinimal);
  if (b.ok) return b.row;

  return null;
}

serve(async (req) => {
  try {
    if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

    const geminiKey = Deno.env.get("GEMINI_API_KEY") ?? "";
    const primaryModel = Deno.env.get("GEMINI_MODEL") ?? "gemini-3-flash-preview";

    // ✅ FIX: remove gemini-3-pro-preview fallback (your quota is 0 for gemini-3-pro)
    const modelFallbacks = [
      primaryModel,
      "gemini-3-flash-preview",
    ];

    if (!supabaseUrl || !serviceKey) {
      return json({ error: "Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY" }, 500);
    }
    if (!geminiKey) return json({ error: "Missing GEMINI_API_KEY" }, 500);

    // 1) Verify user via JWT
    const token = getBearerToken(req);
    if (!token) return json({ error: "Missing Authorization token" }, 401);

    const userRes = await fetchWithRetry(
      `${supabaseUrl}/auth/v1/user`,
      { headers: { apikey: serviceKey, authorization: `Bearer ${token}` } },
      { retries: 2, baseDelayMs: 300, timeoutMs: 10_000, retryOnStatuses: true },
    );

    if (!userRes.ok) {
      const t = await userRes.text().catch(() => "");
      return json({ error: "Invalid user token", details: t || null }, 401);
    }

    const userJson = await userRes.json();
    const userId = userJson?.id as string | undefined;
    if (!userId) return json({ error: "User not found" }, 401);

    const { sessionId } = (await req.json()) as ReqBody;
    if (!sessionId) return json({ error: "Missing sessionId" }, 400);

    // 2) If shared summary already exists -> return immediately
    const existingCouple = await fetchCoupleSummaryRow({ supabaseUrl, serviceKey, sessionId });
    if (existingCouple?.summary && String(existingCouple.summary).trim().length > 0) {
      await logAiEvent({
        supabaseUrl,
        serviceKey,
        sessionId,
        userId,
        event: "already_ready",
        details: { source: "shared_cache" },
      });
      return json(
        { ok: true, summary: existingCouple.summary, source: "shared_cache" },
        200,
      );
    }

    // 3) Check Pro — generation only
    const proRes = await fetchWithRetry(
      `${supabaseUrl}/rest/v1/purchases?select=id&user_id=eq.${userId}&type=eq.lifetime_unlock&limit=1`,
      { headers: { apikey: serviceKey, authorization: `Bearer ${serviceKey}` } },
      { retries: 3, baseDelayMs: 350, timeoutMs: 12_000, retryOnStatuses: true },
    );

    if (!proRes.ok) {
      const t = await proRes.text().catch(() => "");
      return json({ error: "Failed to check Pro", details: t || null }, 500);
    }

    const proRows = await proRes.json();
    const isPro = Array.isArray(proRows) && proRows.length > 0;
    if (!isPro) return json({ error: "Pro required" }, 403);

    // 4) Load session
    const sessionRes = await fetchWithRetry(
      `${supabaseUrl}/rest/v1/pair_sessions?select=id,created_by,partner_id,status&id=eq.${sessionId}&limit=1`,
      { headers: { apikey: serviceKey, authorization: `Bearer ${serviceKey}` } },
      { retries: 3, baseDelayMs: 350, timeoutMs: 12_000, retryOnStatuses: true },
    );

    if (!sessionRes.ok) {
      const t = await sessionRes.text().catch(() => "");
      return json({ error: "Failed to load session", details: t || null }, 500);
    }

    const sessionRows = await sessionRes.json();
    const session = sessionRows?.[0];
    if (!session) return json({ error: "Session not found" }, 404);

    if (session.status !== "completed") {
      return json(
        { error: "Session not completed", details: "AI summary is only available after completion." },
        409,
      );
    }

    // 5) CLAIM lock
    const claim = await claimCoupleSummaryGeneration({
      supabaseUrl,
      serviceKey,
      sessionId,
      userId,
    });

    if (!claim) {
      await logAiEvent({ supabaseUrl, serviceKey, sessionId, userId, event: "claim_failed" });
      return json({ error: "Failed to claim generation lock" }, 500);
    }

    if (!claim.claimed) {
      await logAiEvent({
        supabaseUrl,
        serviceKey,
        sessionId,
        userId,
        event: "already_generating",
        details: { current_status: claim.current_status },
      });

      if (claim.current_status === "ready" && claim.existing_summary) {
        return json({ ok: true, summary: claim.existing_summary, source: "shared_cache" }, 200);
      }

      return json(
        { ok: false, status: "generating", note: "Summary is being generated by another request." },
        202,
      );
    }

    await logAiEvent({ supabaseUrl, serviceKey, sessionId, userId, event: "claimed" });

    // ✅ IMPORTANT: force "generating" state + ensure summary is NULL (not empty string)
    await patchCoupleSummaryWithFallback({
      supabaseUrl,
      serviceKey,
      sessionId,
      patch: {
        status: "generating",
        summary: null, // ✅ prevents partner from seeing empty string content
        error_message: null,
        generated_by: userId,
        updated_at: new Date().toISOString(),
      },
    }).catch(() => {});

    // 6) Load responses
    const responsesRes = await fetchWithRetry(
      `${supabaseUrl}/rest/v1/responses?select=question_id,user_id,value&session_id=eq.${sessionId}`,
      { headers: { apikey: serviceKey, authorization: `Bearer ${serviceKey}` } },
      { retries: 3, baseDelayMs: 350, timeoutMs: 12_000, retryOnStatuses: true },
    );

    if (!responsesRes.ok) {
      const t = await responsesRes.text().catch(() => "");
      await logAiEvent({
        supabaseUrl,
        serviceKey,
        sessionId,
        userId,
        event: "responses_failed",
        details: { status: responsesRes.status, body: t?.slice?.(0, 500) ?? t },
      });
      await patchCoupleSummaryWithFallback({
        supabaseUrl,
        serviceKey,
        sessionId,
        patch: {
          status: "error",
          error_message: `Failed to load responses: ${t || responsesRes.status}`.slice(0, 2000),
          updated_at: new Date().toISOString(),
        },
      }).catch(() => {});
      return json({ error: "Failed to load responses", details: t || null }, 500);
    }

    const responses = await responsesRes.json();
    const compact = (Array.isArray(responses) ? responses : []).map((r) => ({
      q: r.question_id,
      u: r.user_id,
      a: r.value,
    }));

    // 7) Metrics + tone
    const metrics = await fetchCompatibilityMetrics({ supabaseUrl, serviceKey, sessionId });
    const { tone, rationale } = computeToneProfile(metrics);
    console.log("tone_profile:", tone, rationale);

    const prompt = buildSummaryPrompt({
      sessionStatus: session.status,
      compactedAnswers: compact,
      metrics,
      tone,
    });

    // 8) Gemini
    const first = await callGeminiWithFallback({
      apiKey: geminiKey,
      models: modelFallbacks,
      prompt,
      temperature: 0.4,
      maxOutputTokens: 4096,
    });

    if (!first.ok) {
      const status = first.lastErr?.status ?? 0;
      const raw = first.lastErr?.raw ?? null;

      // ✅ If our request locally aborted (timeout/network), keep status generating + return 202
      if (status === 202) {
        await logAiEvent({
          supabaseUrl,
          serviceKey,
          sessionId,
          userId,
          event: "gemini_aborted_return_202",
          details: { note: String(raw ?? "").slice(0, 200) },
        });

        await patchCoupleSummaryWithFallback({
          supabaseUrl,
          serviceKey,
          sessionId,
          patch: {
            status: "generating",
            summary: null, // ✅ keep it null while generating
            error_message: null,
            updated_at: new Date().toISOString(),
          },
        }).catch(() => {});

        return json(
          { ok: false, status: "generating", note: "Generation is taking longer; please poll." },
          202,
        );
      }

      // ✅ Gemini rate limit -> return 429 with retry info
      if (status === 429 && typeof raw === "string") {
        const retryAfterSeconds = extractRetryDelaySecondsFromGeminiError(raw) ?? 20;

        await logAiEvent({
          supabaseUrl,
          serviceKey,
          sessionId,
          userId,
          event: "gemini_rate_limited",
          details: { retryAfterSeconds },
        });

        await patchCoupleSummaryWithFallback({
          supabaseUrl,
          serviceKey,
          sessionId,
          patch: {
            status: "error",
            error_message: `Rate limit exceeded. Retry in ~${retryAfterSeconds}s.`,
            updated_at: new Date().toISOString(),
          },
        }).catch(() => {});

        let parsedDetails: any = null;
        try {
          parsedDetails = JSON.parse(raw);
        } catch (_) {
          parsedDetails = raw;
        }

        return json(
          { error: "Gemini rate limited", retryAfterSeconds, details: parsedDetails },
          429,
          { "retry-after": String(retryAfterSeconds) },
        );
      }

      await logAiEvent({
        supabaseUrl,
        serviceKey,
        sessionId,
        userId,
        event: "gemini_failed",
        details: { status, raw: String(raw ?? "unknown").slice(0, 500) },
      });

      await patchCoupleSummaryWithFallback({
        supabaseUrl,
        serviceKey,
        sessionId,
        patch: {
          status: "error",
          error_message: `Gemini failed: ${String(raw ?? "unknown")}`.slice(0, 2000),
          updated_at: new Date().toISOString(),
        },
      }).catch(() => {});

      return json({ error: "Gemini failed", details: raw }, 500);
    }

    // 9) Parse / repair JSON, retry once if needed
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
        const shapedFallback = fallbackSummary("AI output could not be repaired into JSON.");
        const summaryString = JSON.stringify(shapedFallback);

        await logAiEvent({ supabaseUrl, serviceKey, sessionId, userId, event: "json_repair_failed" });

        await upsertAiSummary({ supabaseUrl, serviceKey, sessionId, userId, summaryString, metrics }).catch(() => {});
        await upsertCoupleSummary({ supabaseUrl, serviceKey, sessionId, summaryString, metrics, generatedBy: userId }).catch(() => {});
        await patchCoupleSummaryWithFallback({
          supabaseUrl,
          serviceKey,
          sessionId,
          patch: {
            summary: summaryString,
            metrics: metrics ?? null,
            generated_by: userId,
            status: "ready",
            error_message: null,
            updated_at: new Date().toISOString(),
          },
        }).catch(() => {});

        return json({ ok: true, summary: shapedFallback, note: "Fallback summary returned" }, 200);
      }

      parsed = tryParseJsonObject(second.raw);
      if (!parsed.ok) {
        const shapedFallback = fallbackSummary("AI output was invalid JSON.");
        const summaryString = JSON.stringify(shapedFallback);

        await logAiEvent({ supabaseUrl, serviceKey, sessionId, userId, event: "json_invalid_after_repair" });

        await upsertAiSummary({ supabaseUrl, serviceKey, sessionId, userId, summaryString, metrics }).catch(() => {});
        await upsertCoupleSummary({ supabaseUrl, serviceKey, sessionId, summaryString, metrics, generatedBy: userId }).catch(() => {});
        await patchCoupleSummaryWithFallback({
          supabaseUrl,
          serviceKey,
          sessionId,
          patch: {
            summary: summaryString,
            metrics: metrics ?? null,
            generated_by: userId,
            status: "ready",
            error_message: null,
            updated_at: new Date().toISOString(),
          },
        }).catch(() => {});

        return json({ ok: true, summary: shapedFallback, note: "Fallback summary returned" }, 200);
      }
    }

    const shaped = enforceShape(parsed.value);
    const summaryString = JSON.stringify(shaped);

    // 10) Save per-user
    const save = await upsertAiSummary({
      supabaseUrl,
      serviceKey,
      sessionId,
      userId,
      summaryString,
      metrics,
    });

    if (!save.ok) {
      await logAiEvent({
        supabaseUrl,
        serviceKey,
        sessionId,
        userId,
        event: "save_failed",
        details: { details: (save as any).details ?? null },
      });

      await patchCoupleSummaryWithFallback({
        supabaseUrl,
        serviceKey,
        sessionId,
        patch: {
          status: "error",
          error_message: `Failed to save per-user summary: ${(save as any).details ?? "unknown"}`.slice(0, 2000),
          updated_at: new Date().toISOString(),
        },
      }).catch(() => {});
      return json({ error: "Failed to save summary", details: (save as any).details ?? null }, 500);
    }

    // 11) Save shared couple summary + mark ready
    await upsertCoupleSummary({
      supabaseUrl,
      serviceKey,
      sessionId,
      summaryString,
      metrics,
      generatedBy: userId,
    }).catch(() => {});

    await patchCoupleSummaryWithFallback({
      supabaseUrl,
      serviceKey,
      sessionId,
      patch: {
        summary: summaryString,
        metrics: metrics ?? null,
        generated_by: userId,
        status: "ready",
        error_message: null,
        updated_at: new Date().toISOString(),
      },
    }).catch(() => {});

    await logAiEvent({
      supabaseUrl,
      serviceKey,
      sessionId,
      userId,
      event: "saved",
      details: { kind: "final" },
    });

    return json({ ok: true, summary: shaped }, 200);
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});