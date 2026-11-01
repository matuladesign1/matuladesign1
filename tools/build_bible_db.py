#!/usr/bin/env python3
"""Construit assets/db/bible.db a partir d'un fichier XML (format Beblia).

Usage :
    python3 tools/build_bible_db.py lsg1910.xml assets/db/bible.db LSG "Louis Segond 1910" fr

La Louis Segond 1910 est dans le domaine public. N'utilisez cet outil qu'avec
une version dont la licence autorise la redistribution.
Plusieurs versions peuvent cohabiter dans la meme base (relancer avec un autre code).
"""
import sqlite3
import sys
import xml.etree.ElementTree as ET

BOOKS = [
    ("Genèse", "Gn"), ("Exode", "Ex"), ("Lévitique", "Lv"), ("Nombres", "Nb"),
    ("Deutéronome", "Dt"), ("Josué", "Jos"), ("Juges", "Jg"), ("Ruth", "Rt"),
    ("1 Samuel", "1S"), ("2 Samuel", "2S"), ("1 Rois", "1R"), ("2 Rois", "2R"),
    ("1 Chroniques", "1Ch"), ("2 Chroniques", "2Ch"), ("Esdras", "Esd"),
    ("Néhémie", "Né"), ("Esther", "Est"), ("Job", "Jb"), ("Psaumes", "Ps"),
    ("Proverbes", "Pr"), ("Ecclésiaste", "Ec"), ("Cantique des cantiques", "Ct"),
    ("Ésaïe", "Es"), ("Jérémie", "Jr"), ("Lamentations", "Lm"), ("Ézéchiel", "Ez"),
    ("Daniel", "Dn"), ("Osée", "Os"), ("Joël", "Jl"), ("Amos", "Am"),
    ("Abdias", "Ab"), ("Jonas", "Jon"), ("Michée", "Mi"), ("Nahum", "Na"),
    ("Habacuc", "Ha"), ("Sophonie", "So"), ("Aggée", "Ag"), ("Zacharie", "Za"),
    ("Malachie", "Ml"), ("Matthieu", "Mt"), ("Marc", "Mc"), ("Luc", "Lc"),
    ("Jean", "Jn"), ("Actes", "Ac"), ("Romains", "Rm"), ("1 Corinthiens", "1Co"),
    ("2 Corinthiens", "2Co"), ("Galates", "Ga"), ("Éphésiens", "Ep"),
    ("Philippiens", "Ph"), ("Colossiens", "Col"), ("1 Thessaloniciens", "1Th"),
    ("2 Thessaloniciens", "2Th"), ("1 Timothée", "1Tm"), ("2 Timothée", "2Tm"),
    ("Tite", "Tt"), ("Philémon", "Phm"), ("Hébreux", "He"), ("Jacques", "Jc"),
    ("1 Pierre", "1P"), ("2 Pierre", "2P"), ("1 Jean", "1Jn"), ("2 Jean", "2Jn"),
    ("3 Jean", "3Jn"), ("Jude", "Jude"), ("Apocalypse", "Ap"),
]

SCHEMA = """
CREATE TABLE IF NOT EXISTS versions(
  code TEXT PRIMARY KEY, name TEXT NOT NULL, language TEXT NOT NULL,
  license TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS books(
  id INTEGER PRIMARY KEY, name TEXT NOT NULL, abbr TEXT NOT NULL,
  testament TEXT NOT NULL, chapters INTEGER NOT NULL);
CREATE TABLE IF NOT EXISTS verses(
  id INTEGER PRIMARY KEY, version TEXT NOT NULL, book INTEGER NOT NULL,
  chapter INTEGER NOT NULL, verse INTEGER NOT NULL, text TEXT NOT NULL,
  UNIQUE(version, book, chapter, verse));
CREATE INDEX IF NOT EXISTS verses_ref ON verses(version, book, chapter, verse);
CREATE VIRTUAL TABLE IF NOT EXISTS verses_fts USING fts5(
  text, content='verses', content_rowid='id',
  tokenize='unicode61 remove_diacritics 2');
"""


def main():
    if len(sys.argv) != 6:
        print(__doc__)
        sys.exit(1)
    src, dst, code, name, lang = sys.argv[1:]
    root = ET.parse(src).getroot()
    license_ = root.get("status", "")
    db = sqlite3.connect(dst)
    db.executescript(SCHEMA)
    db.execute("INSERT OR REPLACE INTO versions VALUES(?,?,?,?)",
               (code, name, lang, license_))
    db.execute("DELETE FROM verses WHERE version=?", (code,))
    count = 0
    for testament in root.findall("testament"):
        for book in testament.findall("book"):
            num = int(book.get("number"))
            chapters = book.findall("chapter")
            bname, abbr = BOOKS[num - 1]
            db.execute("INSERT OR IGNORE INTO books VALUES(?,?,?,?,?)",
                       (num, bname, abbr, "AT" if num <= 39 else "NT", len(chapters)))
            for ch in chapters:
                c = int(ch.get("number"))
                for v in ch.findall("verse"):
                    text = " ".join((v.text or "").split())
                    if not text:
                        continue
                    db.execute(
                        "INSERT INTO verses(version,book,chapter,verse,text) VALUES(?,?,?,?,?)",
                        (code, num, c, int(v.get("number")), text))
                    count += 1
    db.execute("INSERT INTO verses_fts(verses_fts) VALUES('rebuild')")
    db.execute("INSERT INTO verses_fts(verses_fts) VALUES('optimize')")
    db.commit()
    db.execute("VACUUM")
    db.close()
    print(f"{code}: {count} versets importés dans {dst}")


if __name__ == "__main__":
    main()
