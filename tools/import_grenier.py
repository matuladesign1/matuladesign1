#!/usr/bin/env python3
"""Construit la bibliothèque embarquée à partir de la compilation « Le Grenier du Message ».

Usage :
    python3 tools/import_grenier.py sermons.pdf assets/sermons [--chunk-mb 16]

Principe :
  * les signets du PDF (« Sermons en ordre chronologique ») donnent pour chaque sermon
    son code officiel, son titre et sa page de début ;
  * le texte est extrait page par page (pdftotext) ;
  * les en-têtes et pieds de page répétés sont retirés ;
  * le texte est découpé en paragraphes numérotés ;
  * la base SQLite produite utilise exactement le schéma de l'application (lib/data/db.dart),
    index plein texte compris, puis elle est découpée en morceaux pour l'APK.
Rien n'est inventé : un sermon dont le texte n'est pas reconnu est signalé dans le rapport.
"""
import argparse
import json
import os
import re
import sqlite3
import subprocess
import sys
import unicodedata
from collections import Counter

HERE = os.path.dirname(os.path.abspath(__file__))
DB_DART = os.path.join(HERE, "..", "lib", "data", "db.dart")
SOURCE = "Le Grenier du Message (version de juin 2019), La Restauration Promise — www.branham.fr ; traductions Voice of God Recordings / Shekinah Publications"

CODE_RE = re.compile(r"^(?P<code>(4[7-9]|5\d|6[0-5])-\d{4}[A-Z]?)[\s_-]+(?P<title>.+?)(\.pdf)?$", re.I)
DATE_LINE = re.compile(r"^\d{1,2}\s+[A-Za-zéûÉÛ]+\s+\d{4}\b")
FOOTER_LOC = re.compile(
    r"^\d{1,2}\s+\S+\s+\d{4}(?:-\d{4}[A-Z]?)?(?:\s+(?:matin|soir|après-midi|apres-midi|midi))?\s+(.+?),?\s+[a-z]?\d{1,4}$",
    re.I)

SERIES = {
    "La Révélation des Sept Sceaux": ["63-0317", "63-0318", "63-0319", "63-0320", "63-0321", "63-0322",
                                       "63-0323", "63-0324"],
    "Les Sept Âges de l'Église": ["60-1204", "60-1205", "60-1206", "60-1207", "60-1208", "60-1209",
                                   "60-1210", "60-1211"],
    "Le Livre des Hébreux": ["57-0821", "57-0825", "57-0828", "57-0901", "57-0908", "57-0915", "57-0922",
                             "57-0925"],
    "L'Adoption": ["60-0515", "60-0518", "60-0522"],
    "Les Soixante-dix semaines de Daniel": ["61-0730", "61-0806"],
}
SERIES_BY_BASE = {code: name for name, codes in SERIES.items() for code in codes}

MONTHS = {"janvier": 1, "fevrier": 2, "mars": 3, "avril": 4, "mai": 5, "juin": 6, "juillet": 7,
          "aout": 8, "septembre": 9, "octobre": 10, "novembre": 11, "decembre": 12}


def fold(s):
    s = unicodedata.normalize("NFKD", s.lower())
    return "".join(c for c in s if not unicodedata.combining(c))


def app_schema():
    src = open(DB_DART, encoding="utf-8").read()
    parts = re.findall(r"const (?:sermonSchema|appSchema) = '''(.*?)''';", src, re.S)
    if len(parts) != 2:
        sys.exit("Schéma introuvable dans lib/data/db.dart")
    return parts


def outline(pdf):
    from pypdf import PdfReader
    r = PdfReader(pdf)
    items = []

    def walk(o, path):
        last = None
        for x in o:
            if isinstance(x, list):
                walk(x, path + [last])
            else:
                try:
                    items.append((path, x.title.strip(), r.get_destination_page_number(x)))
                except Exception:
                    pass
                last = x.title.strip()

    walk(r.outline, [])
    return items, len(r.pages)


def page_texts(pdf):
    out = subprocess.run(["pdftotext", "-enc", "UTF-8", pdf, "-"], capture_output=True, check=True).stdout
    return out.decode("utf-8", "replace").split("\f")


def clean_pages(pages, title):
    """Retire les en-têtes / pieds de page répétés d'un sermon."""
    def key(line):
        return re.sub(r"[a-z]?\d+", "#", fold(line.strip()))

    edge = Counter()
    for pg in pages:
        lines = [l for l in pg.split("\n") if l.strip()]
        for l in lines[:2] + lines[-2:]:
            edge[key(l)] += 1
    threshold = max(3, int(len(pages) * 0.2))
    repeated = {k for k, n in edge.items() if n >= threshold and k not in ("#",)}
    ftitle = fold(title)
    out = []
    location = None
    for pg in pages:
        lines = pg.split("\n")
        non_empty = [i for i, l in enumerate(lines) if l.strip()]
        edges = set(non_empty[:2] + non_empty[-2:])
        for i, l in enumerate(lines):
            s = l.strip()
            if i in edges and s:
                k = key(s)
                m = FOOTER_LOC.match(s)
                if m and not location:
                    location = m.group(1).strip(" ,")
                if k in repeated or m:
                    continue
                # en-tête « 12 TITRE » ou « TITRE 12 »
                bare = re.sub(r"^[a-z]?\d+\s+|\s+[a-z]?\d+$", "", fold(s)).strip()
                if bare and (bare == ftitle or (len(bare) > 6 and bare in ftitle)) and re.search(r"\d", s):
                    continue
            out.append(l)
    return "\n".join(out), location


PARA_INLINE = re.compile(r"^(?:E-)?(\d{1,4})[\s.]+(?=\S)(.*)$")


def split_paragraphs(text):
    pre, paras, expected = [], [], 1
    for raw in text.split("\n"):
        s = raw.strip()
        if not s:
            continue
        if re.fullmatch(r"(?:E-)?\d{1,4}", s):
            n = int(s.replace("E-", ""))
            if expected <= n <= expected + 2:
                paras.append([n, ""])
                expected = n + 1
                continue
        m = PARA_INLINE.match(s)
        if m and paras:
            n = int(m.group(1))
            if expected <= n <= expected + 1 and len(m.group(2)) > 20:
                paras.append([n, m.group(2)])
                expected = n + 1
                continue
        if paras:
            prev = paras[-1][1]
            if prev.endswith("-") and not prev.endswith(" -") and s[:1].islower():
                paras[-1][1] = prev + s  # « devez-/vous » -> « devez-vous »
            else:
                paras[-1][1] = (prev + " " + s).strip()
        else:
            pre.append(s)
    return pre, [(n, " ".join(t.split())) for n, t in paras if t.strip()]


COLOPHON = ["Veuillez trouver les autres", "www.shekinahgospelmissions", "Shekinah Gospel", "SHEKINAH",
            "Shekinah Publications", "B.P. 10", "Publié par", "Publiée par", "Imprimé par", "Ce Message a été",
            "Ce message a été", "Voice Of God Recordings", "VOICE OF GOD RECORDINGS", "Copyright", "©"]


def strip_colophon(paras):
    """Retire la notice de l'éditeur collée à la fin du dernier paragraphe."""
    if not paras:
        return paras
    n, t = paras[-1]
    window = max(0, len(t) - 2500)
    cut = min((i for i in (t.find(m, window) for m in COLOPHON) if i >= 0), default=-1)
    if cut >= 0:
        t = t[:cut].rstrip(" -–—,;:")
        # remonte jusqu'à la dernière phrase complète
        t = t.rstrip()
        paras = paras[:-1] + ([(n, t)] if len(t) > 3 else [])
    return paras


def clean_location(loc):
    if not loc:
        return None
    loc = loc.strip(" ,.")
    loc = re.sub(r"^(?:[a-zàâäéèêëîïôöûüç'’\-]+\s+)+(?=[A-ZÀ-Ý])", "", loc)
    if loc.isupper():
        loc = loc.title().replace("Usa", "USA")
    return loc or None


def fallback_paragraphs(text):
    blocks = [" ".join(b.split()) for b in re.split(r"\n\s*\n", text) if len(b.strip()) > 40]
    return [(i + 1, b) for i, b in enumerate(blocks)]


COLLECTION_NAMES = {
    "frere branham": "Frère Branham : sa vie et son ministère",
    "la revelation de sept sceaux": "La Révélation des Sept Sceaux",
    "le livre des hebreux": "Le Livre des Hébreux",
    "le saint esprit": "Le Saint-Esprit",
    "adoption": "L'Adoption",
    "les soixante-dix semaines de daniel": "Les Soixante-dix Semaines de Daniel",
    "l'eglise": "L'Église",
    "demonologie": "La Démonologie",
    "conduite, ordre et doctrine de l’eglise": "Conduite, Ordre et Doctrine de l'Église",
    "conduite, ordre et doctrine de l'eglise": "Conduite, Ordre et Doctrine de l'Église",
}
EXPOSE = "Exposé des Sept Âges de l'Église"
TRAILING_CODE = re.compile(r"((?:4[7-9]|5\d|6[0-5])-\d{4}[A-Z]?)\s*$")


def nice_collection(name):
    return COLLECTION_NAMES.get(fold(name).replace("’", "'"), COLLECTION_NAMES.get(fold(name), name))


def date_from_code(code):
    yy, mm, dd = code[:2], code[3:5], code[5:7]
    if 1 <= int(mm) <= 12 and 1 <= int(dd) <= 31:
        return f"19{yy}-{mm}-{dd}"
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("pdf")
    ap.add_argument("outdir")
    ap.add_argument("--chunk-mb", type=int, default=16)
    ap.add_argument("--keep-db", help="garder aussi la base complète à cet emplacement")
    a = ap.parse_args()

    items, npages = outline(a.pdf)
    groups = Counter(p[0] if p else "(racine)" for p, _, _ in items)
    print("Groupes de signets :", dict(groups))
    starts = sorted({pg for _, _, pg in items})
    chrono = []
    seen = set()
    for path, title, pg in items:
        if not path or "chronolog" not in fold(path[0]):
            continue
        m = CODE_RE.match(title)
        if not m:
            continue
        code = m.group("code").upper()
        if code in seen:
            continue
        seen.add(code)
        chrono.append((pg, code, m.group("title").replace("_", " ").strip()))
    chrono.sort()
    print(f"Sermons dans les signets chronologiques : {len(chrono)}")

    # Brochures : recueils de la section « Livres » + chapitres de l'Exposé des Sept Âges.
    collections, brochures = [], []
    for path, title, pg in items:
        if not path:
            continue
        top = fold(path[0])
        if top.startswith("livres") and len(path) >= 2:
            m = TRAILING_CODE.search(title)
            if m:
                collections.append((nice_collection(path[1]), m.group(1).upper()))
        elif top.startswith("expos"):
            code = f"EXP-{len(brochures) + 1:02d}"
            brochures.append((pg, code, title))
            collections.append((EXPOSE, code))
    print(f"Brochures : {len(set(c for c, _ in collections))} recueils, {len(brochures)} chapitres d'exposé")
    first_collection = {}
    for name, code in collections:
        if not name.startswith("Conduite") and not name.startswith("Frère"):
            first_collection.setdefault(code, name)

    print("Extraction du texte…", flush=True)
    pages = page_texts(a.pdf)
    print(f"{len(pages)} pages extraites")

    os.makedirs(a.outdir, exist_ok=True)
    dbpath = os.path.join(a.outdir, "_build.db")
    if os.path.exists(dbpath):
        os.remove(dbpath)
    db = sqlite3.connect(dbpath)
    db.execute("PRAGMA journal_mode=OFF")
    db.execute("PRAGMA synchronous=OFF")
    for s in app_schema():
        db.executescript(s)

    report, total_paras, review = [], 0, 0
    docs = [(pg, code, title, "sermon") for pg, code, title in chrono] + \
           [(pg, code, title, "brochure") for pg, code, title in brochures]
    for i, (start, code, title, kind) in enumerate(docs):
        end = next((p for p in starts if p > start), npages)
        raw_pages = pages[start:end]
        text, footer_loc = clean_pages(raw_pages, title)
        pre, paras = split_paragraphs(text)
        paras = strip_colophon(paras)
        notes = []
        location = footer_loc
        if not location:
            for j, l in enumerate(pre):
                if DATE_LINE.match(l) and j + 1 < len(pre):
                    location = pre[j + 1].title()
                    break
        location = clean_location(location) if kind == "sermon" else None
        if not location and kind == "sermon":
            notes.append("lieu introuvable")
        if len(paras) <= 2:
            fb = strip_colophon(fallback_paragraphs(text))
            if len(fb) > len(paras):
                paras = fb
                if kind == "sermon":
                    notes.append("paragraphes non numérotés dans l'original (renumérotés)")
        if not paras:
            notes.append("paragraphes non reconnus (texte conservé en un bloc)")
            body = " ".join(text.split())
            paras = [(1, body)] if body else []
        else:
            gaps = sum(1 for x, y in zip(paras, paras[1:]) if y[0] != x[0] + 1)
            if gaps:
                notes.append(f"numérotation discontinue ({gaps} saut(s))")
        if not paras:
            report.append((code, title, "vide"))
            continue
        if kind == "sermon":
            date, year = date_from_code(code), int("19" + code[:2])
            series = SERIES_BY_BASE.get(code[:7]) or first_collection.get(code)
        else:
            date, year, series = None, None, EXPOSE
            notes = [n for n in notes if not n.startswith("numérotation")]
        cur = db.execute(
            "INSERT OR IGNORE INTO sermons(code,language,title,date,year,location,series,source,"
            "paragraph_count,needs_review,review_notes,kind) VALUES(?,?,?,?,?,?,?,?,?,?,?,?)",
            (code, "fr", title, date, year, location, series,
             SOURCE, len(paras), 1 if notes else 0, "; ".join(notes) or None, kind))
        if cur.rowcount == 0:
            continue
        sid = cur.lastrowid
        db.executemany("INSERT INTO paragraphs(sermon_id, number, text) VALUES(?,?,?)",
                       [(sid, n, t) for n, t in paras])
        total_paras += len(paras)
        if notes:
            review += 1
            report.append((code, title, "; ".join(notes)))
        if i % 100 == 0:
            print(f"  {i}/{len(docs)}  {code}  {title[:50]}  {len(paras)} §  {location}", flush=True)
            db.commit()
    db.commit()
    known = {r[0] for r in db.execute("SELECT code FROM sermons")}
    pos = Counter()
    for name, code in collections:
        if code in known:
            pos[name] += 1
            db.execute("INSERT OR IGNORE INTO collections(name, code, position) VALUES(?,?,?)", (name, code, pos[name]))
    db.commit()
    print("Recueils :", dict(pos))
    db.execute("INSERT INTO paragraphs_fts(paragraphs_fts) VALUES('optimize')")
    db.commit()
    db.execute("VACUUM")
    n = db.execute("SELECT count(*) FROM sermons WHERE kind='sermon'").fetchone()[0]
    db.close()

    if a.keep_db:
        import shutil
        shutil.copy(dbpath, a.keep_db)
    size = os.path.getsize(dbpath)
    chunk = a.chunk_mb * 1024 * 1024
    parts = []
    with open(dbpath, "rb") as f:
        k = 0
        while True:
            data = f.read(chunk)
            if not data:
                break
            name = f"part{k:03d}.bin"
            with open(os.path.join(a.outdir, name), "wb") as out:
                out.write(data)
            parts.append(name)
            k += 1
    os.remove(dbpath)
    manifest = {"version": 1, "sermons": n, "paragraphs": total_paras, "bytes": size, "parts": parts,
                "source": SOURCE}
    with open(os.path.join(a.outdir, "manifest.json"), "w", encoding="utf-8") as f:
        json.dump(manifest, f, ensure_ascii=False, indent=1)
    print(f"\nRésultat : {n} sermons, {total_paras} paragraphes, {review} à vérifier, base {size/1e6:.0f} Mo "
          f"en {len(parts)} morceaux")
    print("Sermons à vérifier (extrait) :")
    for r in report[:40]:
        print("  ", *r)


if __name__ == "__main__":
    main()
