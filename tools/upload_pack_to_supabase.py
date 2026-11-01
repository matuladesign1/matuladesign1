#!/usr/bin/env python3
"""Publie un pack .smpack sur le serveur Supabase et calcule les vecteurs (recherche « Sens »).

Usage (sur l'ordinateur de l'administrateur, jamais dans l'application) :
    export SUPABASE_URL=https://xxxx.supabase.co
    export SUPABASE_SERVICE_ROLE_KEY=...      # clé de service (secrète)
    export OPENAI_API_KEY=sk-...              # clé OpenAI (secrète)
    python3 tools/upload_pack_to_supabase.py pack.smpack [--publish]

Sans --publish, les sermons sont envoyés non publiés (validation dans le tableau de bord).
"""
import json
import os
import sqlite3
import sys
import urllib.request

URL = os.environ.get("SUPABASE_URL", "").rstrip("/")
SKEY = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "")
OKEY = os.environ.get("OPENAI_API_KEY", "")


def call(url, payload, headers, method="POST"):
    req = urllib.request.Request(url, data=json.dumps(payload).encode(), method=method,
                                 headers={"Content-Type": "application/json", **headers})
    with urllib.request.urlopen(req, timeout=120) as r:
        body = r.read().decode()
        return json.loads(body) if body else None


def rest(path, payload, prefer="return=representation"):
    return call(f"{URL}/rest/v1/{path}", payload,
                {"apikey": SKEY, "Authorization": f"Bearer {SKEY}", "Prefer": prefer})


def embed(texts):
    r = call("https://api.openai.com/v1/embeddings",
             {"model": "text-embedding-3-small", "input": texts},
             {"Authorization": f"Bearer {OKEY}"})
    return [d["embedding"] for d in r["data"]]


def main():
    if len(sys.argv) < 2 or not (URL and SKEY and OKEY):
        print(__doc__)
        sys.exit(1)
    publish = "--publish" in sys.argv
    db = sqlite3.connect(sys.argv[1])
    db.row_factory = sqlite3.Row
    for s in db.execute("SELECT * FROM sermons ORDER BY code"):
        row = rest("sermons?on_conflict=code,language", [{
            "code": s["code"], "language": s["language"], "title": s["title"], "date": s["date"],
            "year": s["year"], "location": s["location"], "duration_sec": s["duration_sec"],
            "series": s["series"], "audio_url": s["audio_url"], "source": s["source"] or "",
            "sha1": s["sha1"], "translation_status": s["translation_status"], "published": publish,
        }], prefer="return=representation,resolution=merge-duplicates")[0]
        paras = db.execute("SELECT number, text, start_ms FROM paragraphs WHERE sermon_id=? ORDER BY number",
                           (s["id"],)).fetchall()
        for i in range(0, len(paras), 64):
            chunk = paras[i:i + 64]
            vectors = embed([p["text"][:8000] for p in chunk])
            rest("paragraphs?on_conflict=sermon_id,number", [
                {"sermon_id": row["id"], "number": p["number"], "text": p["text"],
                 "start_ms": p["start_ms"], "embedding": v} for p, v in zip(chunk, vectors)
            ], prefer="resolution=merge-duplicates")
        print(f"  {s['code']} {s['language']} : {len(paras)} paragraphes")
    print("Terminé.")


if __name__ == "__main__":
    main()
