#!/usr/bin/env python3
"""Import massif des predications (PDF) vers un pack SQLite lisible par l'application.

Usage :
    python3 tools/import_sermons.py SORTIE.smpack ENTREE [ENTREE ...]
        [--source "branham.org (autorisation du ...)"] [--lang auto|fr|ln|en]
        [--series series.csv] [--audio audio.csv]

ENTREE peut etre un PDF, un dossier (parcouru recursivement) ou un .zip de PDF.
Le pack produit s'importe dans l'application : Parametres > Bibliotheque > Importer un pack.

Ce que fait l'outil, pour chaque PDF :
  1. extraction du texte (pdftotext, puis pdfplumber) ; OCR Tesseract si le PDF est scanne ;
  2. reconnaissance du code officiel (ex. 47-0412, 65-1127B), de la date et de l'annee ;
  3. reconnaissance du titre et du lieu (en-tete du document ou nom du fichier) ;
  4. detection de la langue (francais, lingala, anglais) ;
  5. decoupage en paragraphes numerotes ;
  6. detection des doublons (meme code + langue, ou meme texte) ;
  7. signalement des documents incomplets ou douteux (colonne needs_review + rapport CSV).

Rien n'est invente : un champ non reconnu reste vide et le sermon est marque « a verifier ».
Le fichier PDF d'origine et sa source sont conserves dans le pack.

Prerequis : poppler-utils (pdftotext, pdftoppm), tesseract-ocr + tesseract-ocr-fra,
pip install pdfplumber (facultatif).
"""
import argparse
import csv
import hashlib
import os
import re
import shutil
import sqlite3
import subprocess
import sys
import tempfile
import unicodedata
import zipfile

SCHEMA = """
CREATE TABLE IF NOT EXISTS sermons(
  id INTEGER PRIMARY KEY,
  code TEXT NOT NULL,
  language TEXT NOT NULL,
  title TEXT NOT NULL,
  date TEXT,
  year INTEGER,
  location TEXT,
  duration_sec INTEGER,
  series TEXT,
  audio_url TEXT,
  audio_cues INTEGER NOT NULL DEFAULT 0,
  pdf_name TEXT,
  source TEXT,
  sha1 TEXT,
  paragraph_count INTEGER NOT NULL DEFAULT 0,
  translation_status TEXT NOT NULL DEFAULT 'original',
  needs_review INTEGER NOT NULL DEFAULT 0,
  review_notes TEXT,
  added_at TEXT NOT NULL DEFAULT (datetime('now')),
  UNIQUE(code, language));
CREATE TABLE IF NOT EXISTS paragraphs(
  id INTEGER PRIMARY KEY,
  sermon_id INTEGER NOT NULL REFERENCES sermons(id) ON DELETE CASCADE,
  number INTEGER NOT NULL,
  text TEXT NOT NULL,
  start_ms INTEGER);
CREATE INDEX IF NOT EXISTS paragraphs_sermon ON paragraphs(sermon_id, number);
CREATE TABLE IF NOT EXISTS pdf_files(
  sermon_id INTEGER PRIMARY KEY REFERENCES sermons(id) ON DELETE CASCADE,
  name TEXT NOT NULL, data BLOB NOT NULL);
CREATE TABLE IF NOT EXISTS pack_info(key TEXT PRIMARY KEY, value TEXT);
"""

CODE_RE = re.compile(r"(?<!\d)(4[7-9]|5\d|6[0-5])-(\d{2})(\d{2})([MAESBX]?)(?![\d])")

MONTHS_FR = {
    "janvier": 1, "février": 2, "fevrier": 2, "mars": 3, "avril": 4, "mai": 5,
    "juin": 6, "juillet": 7, "août": 8, "aout": 8, "septembre": 9,
    "octobre": 10, "novembre": 11, "décembre": 12, "decembre": 12,
}

LOCATION_HINTS = [
    "USA", "U.S.A", "Etats-Unis", "États-Unis", "Canada", "Californie", "Indiana",
    "Arizona", "Illinois", "Ohio", "Texas", "Louisiane", "Kentucky", "Floride",
    "Michigan", "Minnesota", "Oregon", "Washington", "Colorado", "Oklahoma",
    "Arkansas", "Géorgie", "Tennessee", "Caroline", "Pennsylvanie", "New York",
    "Afrique du Sud", "Suisse", "Allemagne", "Norvège", "Finlande", "Inde",
    "Jeffersonville", "Phoenix", "Chicago", "Los Angeles", "Oakland", "Tucson",
    "Shreveport", "Dallas", "Houston", "Denver", "Tabernacle Branham",
]

STOP = {
    "fr": {"le", "la", "les", "et", "de", "des", "que", "qui", "est", "dans", "il",
           "nous", "vous", "pas", "une", "un", "pour", "sur", "dieu"},
    "en": {"the", "and", "of", "that", "is", "in", "he", "we", "you", "not", "a",
           "to", "for", "on", "god", "it"},
    "ln": {"na", "ya", "mpe", "oyo", "te", "kaka", "nzambe", "bato", "ezali",
           "moto", "ete", "bongo", "bino", "biso", "awa"},
}


def norm(s):
    s = unicodedata.normalize("NFKD", s.lower())
    return "".join(c for c in s if not unicodedata.combining(c))


def detect_language(text):
    words = re.findall(r"[a-zà-ÿ]+", text.lower()[:20000])
    scores = {k: sum(1 for w in words if w in v) for k, v in STOP.items()}
    best = max(scores, key=scores.get)
    return best if scores[best] > 20 else "fr"


def run(cmd):
    return subprocess.run(cmd, capture_output=True, text=True, check=False)


def extract_text(path, workdir):
    """Retourne (texte, methode). Bascule sur l'OCR si la couche texte est vide."""
    pages = 1
    info = run(["pdfinfo", path])
    m = re.search(r"Pages:\s+(\d+)", info.stdout)
    if m:
        pages = max(1, int(m.group(1)))
    text = ""
    if shutil.which("pdftotext"):
        text = run(["pdftotext", "-enc", "UTF-8", path, "-"]).stdout
    if len(text.strip()) < 100 * pages:
        try:
            import pdfplumber  # noqa
            with pdfplumber.open(path) as pdf:
                text = "\n".join((p.extract_text() or "") for p in pdf.pages)
        except Exception:
            pass
    if len(text.strip()) >= 100 * pages:
        return text, "texte"
    if not (shutil.which("pdftoppm") and shutil.which("tesseract")):
        return text, "vide"
    prefix = os.path.join(workdir, "ocr")
    run(["pdftoppm", "-r", "300", "-gray", "-png", path, prefix])
    out = []
    for img in sorted(f for f in os.listdir(workdir) if f.startswith("ocr")):
        r = run(["tesseract", os.path.join(workdir, img), "-", "-l", "fra+eng"])
        out.append(r.stdout)
        os.remove(os.path.join(workdir, img))
    return "\n".join(out), "ocr"


def clean_lines(text):
    lines = []
    for raw in text.replace("\f", "\n").splitlines():
        line = raw.strip()
        if not line:
            lines.append("")
            continue
        # numeros de page isoles et en-tetes repetes
        if re.fullmatch(r"\d{1,3}", line) and len(line) <= 3 and (not lines or lines[-1] == ""):
            lines.append("\x00" + line)  # candidat : decide plus tard
            continue
        lines.append(line)
    return lines


PARA_RE = re.compile(r"^(?:E-)?(\d{1,4})[\s.]+(?=\S)(.*)$")


def split_paragraphs(text):
    """Decoupe sur les numeros de paragraphe consecutifs (1, 2, 3 ... ou E-1, E-2 ...)."""
    lines = clean_lines(text)
    paragraphs = []  # (numero, texte)
    expected = 1
    preamble = []
    for line in lines:
        if line.startswith("\x00"):
            continue  # numero de page
        m = PARA_RE.match(line)
        if m:
            n = int(m.group(1))
            if expected <= n <= expected + 2:
                paragraphs.append([n, m.group(2).strip()])
                expected = n + 1
                continue
        if not line:
            continue
        if paragraphs:
            prev = paragraphs[-1][1]
            if prev.endswith("-") and not prev.endswith(" -"):
                paragraphs[-1][1] = prev[:-1] + line
            else:
                paragraphs[-1][1] = (prev + " " + line).strip()
        else:
            preamble.append(line)
    return preamble, [(n, " ".join(t.split())) for n, t in paragraphs if t.strip()]


def parse_code(s):
    m = CODE_RE.search(s)
    if not m:
        return None, None
    yy, mm, dd, suffix = m.groups()
    code = f"{yy}-{mm}{dd}{suffix}"
    date = None
    if 1 <= int(mm) <= 12 and 1 <= int(dd) <= 31:
        date = f"19{yy}-{mm}-{dd}"
    return code, date


def guess_title(filename, preamble, code):
    stem = os.path.splitext(os.path.basename(filename))[0]
    stem = re.sub(r"^(FRN|FRE|FR|LIN|ENG)[\s_-]*", "", stem, flags=re.I)
    if code:
        stem = stem.replace(code, " ")
    stem = re.sub(r"\b(VGR|VOG|PDF)\b", " ", stem, flags=re.I)
    stem = re.sub(r"[_]+", " ", stem)
    stem = " ".join(stem.replace("-", " - ").split()).strip(" -")
    if len(stem) >= 3 and not re.fullmatch(r"[\d\s-]+", stem):
        return stem, False
    for line in preamble[:8]:
        if 3 <= len(line) <= 90 and not CODE_RE.search(line) and not any(
                h in line for h in LOCATION_HINTS):
            return line, False
    return "", True


def guess_location(preamble, first_text):
    for line in preamble[:20] + first_text.splitlines()[:20]:
        if 4 < len(line) < 90 and "," in line and any(h in line for h in LOCATION_HINTS):
            return " ".join(line.split())
    return ""


def iter_pdfs(inputs, tmp):
    for item in inputs:
        if os.path.isdir(item):
            for root, _, files in os.walk(item):
                for f in sorted(files):
                    if f.lower().endswith(".pdf"):
                        yield os.path.join(root, f)
                    elif f.lower().endswith(".zip"):
                        yield from iter_pdfs([os.path.join(root, f)], tmp)
        elif item.lower().endswith(".zip"):
            dest = tempfile.mkdtemp(dir=tmp)
            with zipfile.ZipFile(item) as z:
                for name in z.namelist():
                    if name.lower().endswith(".pdf") and ".." not in name:
                        z.extract(name, dest)
            yield from iter_pdfs([dest], tmp)
        elif item.lower().endswith(".pdf"):
            yield item
        else:
            print(f"  ignoré (pas un PDF) : {item}", file=sys.stderr)


def load_map(path, key_cols):
    out = {}
    if path:
        with open(path, newline="", encoding="utf-8") as f:
            for row in csv.DictReader(f):
                out[row["code"].strip()] = {k: row.get(k, "").strip() for k in key_cols}
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("output")
    ap.add_argument("inputs", nargs="+")
    ap.add_argument("--source", default="", help="provenance et autorisation des fichiers")
    ap.add_argument("--lang", default="auto")
    ap.add_argument("--series", help="CSV code,series")
    ap.add_argument("--audio", help="CSV code,audio_url,duration_sec")
    ap.add_argument("--no-pdf", action="store_true", help="ne pas embarquer les PDF d'origine")
    args = ap.parse_args()

    series = load_map(args.series, ["series"])
    audio = load_map(args.audio, ["audio_url", "duration_sec"])
    db = sqlite3.connect(args.output)
    db.execute("PRAGMA foreign_keys=ON")
    db.executescript(SCHEMA)
    db.execute("INSERT OR REPLACE INTO pack_info VALUES('format','1')")
    db.execute("INSERT OR REPLACE INTO pack_info VALUES('source',?)", (args.source,))

    known_hashes = {r[0] for r in db.execute("SELECT sha1 FROM sermons WHERE sha1 IS NOT NULL")}
    report_rows = []
    stats = {"importés": 0, "doublons": 0, "à vérifier": 0, "échecs": 0, "ocr": 0}
    tmp = tempfile.mkdtemp()
    try:
        for path in iter_pdfs(args.inputs, tmp):
            name = os.path.basename(path)
            work = tempfile.mkdtemp(dir=tmp)
            try:
                text, method = extract_text(path, work)
            except Exception as e:  # noqa
                stats["échecs"] += 1
                report_rows.append([name, "", "échec", f"extraction : {e}"])
                continue
            if method == "ocr":
                stats["ocr"] += 1
            preamble, paras = split_paragraphs(text)
            notes = []
            code, date = parse_code(name)
            if not code:
                code, date = parse_code("\n".join(preamble[:30]) or text[:2000])
            if not code:
                notes.append("code officiel introuvable")
                code = "SANS-CODE-" + hashlib.sha1(name.encode()).hexdigest()[:8]
            title, title_missing = guess_title(name, preamble, code)
            if title_missing:
                notes.append("titre introuvable")
                title = name
            location = guess_location(preamble, text[:3000])
            if not location:
                notes.append("lieu introuvable")
            lang = detect_language(text) if args.lang == "auto" else args.lang
            if not paras:
                notes.append("aucun paragraphe numéroté reconnu (texte conservé en un bloc)")
                body = " ".join(text.split())
                paras = [(1, body)] if body else []
            if not paras:
                stats["échecs"] += 1
                report_rows.append([name, code, "échec", "document vide"])
                continue
            nums = [n for n, _ in paras]
            gaps = [b for a, b in zip(nums, nums[1:]) if b != a + 1]
            if gaps:
                notes.append(f"numérotation discontinue ({len(gaps)} saut(s))")
            if method == "ocr":
                notes.append("texte issu de l'OCR, relecture conseillée")
            digest = hashlib.sha1(norm(" ".join(t for _, t in paras)).encode()).hexdigest()
            dup = db.execute("SELECT id FROM sermons WHERE code=? AND language=?",
                             (code, lang)).fetchone()
            if digest in known_hashes or dup:
                stats["doublons"] += 1
                report_rows.append([name, code, "doublon", "déjà présent dans le pack"])
                continue
            known_hashes.add(digest)
            extra_a = audio.get(code, {})
            cur = db.execute(
                """INSERT INTO sermons(code,language,title,date,year,location,duration_sec,
                   series,audio_url,pdf_name,source,sha1,paragraph_count,needs_review,
                   review_notes) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)""",
                (code, lang, title, date, int("19" + code[:2]) if code[0].isdigit() else None,
                 location or None,
                 int(extra_a["duration_sec"]) if extra_a.get("duration_sec") else None,
                 series.get(code, {}).get("series") or None,
                 extra_a.get("audio_url") or None, name, args.source, digest, len(paras),
                 1 if notes else 0, "; ".join(notes) or None))
            sid = cur.lastrowid
            db.executemany("INSERT INTO paragraphs(sermon_id,number,text) VALUES(?,?,?)",
                           [(sid, n, t) for n, t in paras])
            if not args.no_pdf:
                with open(path, "rb") as f:
                    db.execute("INSERT INTO pdf_files VALUES(?,?,?)", (sid, name, f.read()))
            stats["importés"] += 1
            if notes:
                stats["à vérifier"] += 1
            report_rows.append([name, code, "à vérifier" if notes else "ok", "; ".join(notes)])
            print(f"  {code:12} {lang}  {len(paras):4} §  {title[:60]}")
            db.commit()
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    db.commit()
    db.execute("VACUUM")
    db.close()
    report = os.path.splitext(args.output)[0] + "-rapport.csv"
    with open(report, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["fichier", "code", "statut", "remarques"])
        w.writerows(report_rows)
    print("\nRésumé : " + ", ".join(f"{k} {v}" for k, v in stats.items()))
    print(f"Pack : {args.output}\nRapport : {report}")


if __name__ == "__main__":
    main()
