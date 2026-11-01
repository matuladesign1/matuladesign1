// Fonction serveur « assistant » — Sermons de Branham Matomate.
// Déploiement : supabase functions deploy assistant
// Secrets      : supabase secrets set OPENAI_API_KEY=sk-...  (jamais dans l'application)
//
// Actions :
//   ask       { question, passages:[{n,kind,title,reference,text}] } -> { answer }
//   translate { target:'ln', paragraphs:[{n,text}] }                  -> { paragraphs:[{n,text}] }
//   semantic  { query, limit }                                        -> { matches:[{code,language,number,score}] }

const OPENAI = "https://api.openai.com/v1";
const KEY = Deno.env.get("OPENAI_API_KEY") ?? "";
const MODEL = Deno.env.get("OPENAI_MODEL") ?? "gpt-4o-mini";
const EMBED_MODEL = "text-embedding-3-small";
const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json; charset=utf-8" },
  });
}

async function chat(system: string, user: string, jsonMode = false): Promise<string> {
  const r = await fetch(`${OPENAI}/chat/completions`, {
    method: "POST",
    headers: { Authorization: `Bearer ${KEY}`, "Content-Type": "application/json" },
    body: JSON.stringify({
      model: MODEL,
      temperature: 0.1,
      ...(jsonMode ? { response_format: { type: "json_object" } } : {}),
      messages: [
        { role: "system", content: system },
        { role: "user", content: user },
      ],
    }),
  });
  if (!r.ok) throw new Error(`OpenAI ${r.status}: ${await r.text()}`);
  const data = await r.json();
  return data.choices[0].message.content as string;
}

export async function embed(input: string[]): Promise<number[][]> {
  const r = await fetch(`${OPENAI}/embeddings`, {
    method: "POST",
    headers: { Authorization: `Bearer ${KEY}`, "Content-Type": "application/json" },
    body: JSON.stringify({ model: EMBED_MODEL, input }),
  });
  if (!r.ok) throw new Error(`OpenAI embeddings ${r.status}: ${await r.text()}`);
  const data = await r.json();
  return data.data.map((d: { embedding: number[] }) => d.embedding);
}

const ASK_RULES = `Tu es l'assistant de l'application « Sermons de Branham Matomate ».
Règles absolues :
1. Réponds UNIQUEMENT à partir des passages numérotés fournis. N'utilise aucune autre connaissance.
2. Chaque affirmation doit être suivie du numéro du passage entre crochets, ex. [2].
3. Ne fabrique jamais une citation et n'attribue jamais à William Branham une phrase absente des passages.
   Les citations entre guillemets doivent être recopiées mot pour mot.
4. Si les passages ne permettent pas de répondre, dis-le clairement : « Je ne trouve pas de passage fiable sur ce point dans la bibliothèque. »
5. Distingue ce que dit la Bible (passages de type bible) et ce que dit la prédication (passages de type sermon).
6. Réponds en français (ou en lingala si la question est en lingala), de façon sobre, en quelques paragraphes courts.
7. N'ajoute aucune doctrine ni interprétation personnelle.`;

const TRANSLATE_RULES = `Tu es un traducteur expert français → lingala (Kinshasa), spécialisé dans les textes chrétiens.
Traduis fidèlement chaque paragraphe :
- ne supprime aucune phrase, n'ajoute rien, n'ajoute aucune doctrine ;
- conserve les références bibliques (ex. Jean 3.16) et les noms propres tels quels ;
- respecte les expressions religieuses consacrées en lingala (Nzambe, Yesu Klisto, Molimo Mosantu…) ;
- conserve exactement les numéros de paragraphe.
Réponds en JSON : {"paragraphs":[{"n":<numéro>,"text":"<traduction>"}]}`;

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (!KEY) return json({ error: "OPENAI_API_KEY manquant sur le serveur" }, 500);
  try {
    const body = await req.json();
    switch (body.action) {
      case "ask": {
        const passages = (body.passages ?? []).slice(0, 16);
        if (!passages.length) return json({ answer: "" });
        const ctx = passages
          .map((p: Record<string, unknown>) => `[${p.n}] (${p.kind}) ${p.title} — ${p.reference}\n${p.text}`)
          .join("\n\n");
        const answer = await chat(ASK_RULES, `Question : ${body.question}\n\nPassages :\n${ctx}`);
        return json({ answer });
      }
      case "translate": {
        const paras = body.paragraphs ?? [];
        const out = await chat(TRANSLATE_RULES, JSON.stringify({ paragraphs: paras }), true);
        const parsed = JSON.parse(out);
        // Contrôle : mêmes numéros, aucun paragraphe perdu.
        const want = new Set(paras.map((p: { n: number }) => p.n));
        const got = (parsed.paragraphs ?? []).filter((p: { n: number; text: string }) => want.has(p.n) && p.text);
        if (got.length !== want.size) return json({ error: "traduction incomplète" }, 502);
        return json({ paragraphs: got });
      }
      case "semantic": {
        const [vector] = await embed([String(body.query ?? "")]);
        const r = await fetch(`${SUPABASE_URL}/rest/v1/rpc/match_paragraphs`, {
          method: "POST",
          headers: {
            apikey: SERVICE_KEY,
            Authorization: `Bearer ${SERVICE_KEY}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({ query_embedding: vector, match_count: Math.min(Number(body.limit ?? 20), 50) }),
        });
        if (!r.ok) throw new Error(`match_paragraphs ${r.status}: ${await r.text()}`);
        return json({ matches: await r.json() });
      }
      default:
        return json({ error: "action inconnue" }, 400);
    }
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});
