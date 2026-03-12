#!/usr/bin/env python3
"""
build_offline_bible.py

Downloads KJV (with red-letter), WEB, and ASV Bible texts and converts them
into the OfflineBiblePackage format expected by ScriptureScribe. Outputs
gzip-compressed files for Firebase Storage.

KJV source: Bible SuperSearch (has red-letter markup via unicode angle quotes)
WEB/ASV source: wldeh/bible-api GitHub repo (JSON per chapter)

Usage:
    python3 Scripts/build_offline_bible.py          # Build all 3
    python3 Scripts/build_offline_bible.py KJV       # Build one

Output:
    Scripts/output/KJV.json.gz
    Scripts/output/WEB.json.gz
    Scripts/output/ASV.json.gz

Upload to Firebase Storage:
    firebase storage:upload output/KJV.json.gz offline-bibles/KJV.json.gz
    (or use gsutil / Firebase Console)
"""

import gzip
import json
import os
import re
import sys
import time
import urllib.request
import urllib.error

# ─── Configuration ──────────────────────────────────────────────────────────

TRANSLATIONS = {
    "KJV": {
        "source": "biblesupersearch",
        "api_bible_id": "de4e12af7f28f599-02",
        "display_name": "King James Version",
        "abbreviation": "KJV",
        "copyright": "Public Domain",
    },
    "WEB": {
        "source": "wldeh",
        "repo_key": "en-web",
        "api_bible_id": "9879dbb7cfe39e4d-01",
        "display_name": "World English Bible",
        "abbreviation": "WEB",
        "copyright": "Public Domain",
    },
    "ASV": {
        "source": "wldeh",
        "repo_key": "en-asv",
        "api_bible_id": "9879dbb7cfe39e4d-04",
        "display_name": "American Standard Version",
        "abbreviation": "ASV",
        "copyright": "Public Domain",
    },
}

WLDEH_BASE_URL = "https://raw.githubusercontent.com/wldeh/bible-api/main/bibles"

# Bible SuperSearch KJV JSON (contains red-letter markup with ‹› markers)
KJV_SUPERSEARCH_URL = "https://sourceforge.net/projects/biblesuper/files/All%20Bibles%20-%20JSON/EN-English/kjv.json/download"

# 66 books: (wldeh folder name, API.Bible ID, display name, long name, chapter count, book number 1-66)
BOOKS = [
    ("genesis",         "GEN", "Genesis",         "The First Book of Moses, called Genesis",            50,  1),
    ("exodus",          "EXO", "Exodus",           "The Second Book of Moses, called Exodus",            40,  2),
    ("leviticus",       "LEV", "Leviticus",        "The Third Book of Moses, called Leviticus",          27,  3),
    ("numbers",         "NUM", "Numbers",           "The Fourth Book of Moses, called Numbers",           36,  4),
    ("deuteronomy",     "DEU", "Deuteronomy",      "The Fifth Book of Moses, called Deuteronomy",        34,  5),
    ("joshua",          "JOS", "Joshua",            "The Book of Joshua",                                 24,  6),
    ("judges",          "JDG", "Judges",            "The Book of Judges",                                 21,  7),
    ("ruth",            "RUT", "Ruth",              "The Book of Ruth",                                    4,  8),
    ("1samuel",         "1SA", "1 Samuel",          "The First Book of Samuel",                           31,  9),
    ("2samuel",         "2SA", "2 Samuel",          "The Second Book of Samuel",                          24, 10),
    ("1kings",          "1KI", "1 Kings",           "The First Book of Kings",                            22, 11),
    ("2kings",          "2KI", "2 Kings",           "The Second Book of Kings",                           25, 12),
    ("1chronicles",     "1CH", "1 Chronicles",      "The First Book of Chronicles",                       29, 13),
    ("2chronicles",     "2CH", "2 Chronicles",      "The Second Book of Chronicles",                      36, 14),
    ("ezra",            "EZR", "Ezra",              "The Book of Ezra",                                   10, 15),
    ("nehemiah",        "NEH", "Nehemiah",          "The Book of Nehemiah",                               13, 16),
    ("esther",          "EST", "Esther",            "The Book of Esther",                                 10, 17),
    ("job",             "JOB", "Job",               "The Book of Job",                                    42, 18),
    ("psalms",          "PSA", "Psalms",            "The Book of Psalms",                                150, 19),
    ("proverbs",        "PRO", "Proverbs",          "The Proverbs",                                       31, 20),
    ("ecclesiastes",    "ECC", "Ecclesiastes",      "Ecclesiastes; or, The Preacher",                     12, 21),
    ("songofsolomon",   "SNG", "Song of Solomon",   "The Song of Solomon",                                 8, 22),
    ("isaiah",          "ISA", "Isaiah",            "The Book of the Prophet Isaiah",                     66, 23),
    ("jeremiah",        "JER", "Jeremiah",          "The Book of the Prophet Jeremiah",                   52, 24),
    ("lamentations",    "LAM", "Lamentations",      "The Lamentations of Jeremiah",                        5, 25),
    ("ezekiel",         "EZK", "Ezekiel",           "The Book of the Prophet Ezekiel",                    48, 26),
    ("daniel",          "DAN", "Daniel",            "The Book of Daniel",                                 12, 27),
    ("hosea",           "HOS", "Hosea",             "Hosea",                                              14, 28),
    ("joel",            "JOL", "Joel",              "Joel",                                                3, 29),
    ("amos",            "AMO", "Amos",              "Amos",                                                9, 30),
    ("obadiah",         "OBA", "Obadiah",           "Obadiah",                                             1, 31),
    ("jonah",           "JON", "Jonah",             "Jonah",                                               4, 32),
    ("micah",           "MIC", "Micah",             "Micah",                                               7, 33),
    ("nahum",           "NAM", "Nahum",             "Nahum",                                               3, 34),
    ("habakkuk",        "HAB", "Habakkuk",          "Habakkuk",                                            3, 35),
    ("zephaniah",       "ZEP", "Zephaniah",         "Zephaniah",                                           3, 36),
    ("haggai",          "HAG", "Haggai",            "Haggai",                                              2, 37),
    ("zechariah",       "ZEC", "Zechariah",         "Zechariah",                                          14, 38),
    ("malachi",         "MAL", "Malachi",           "Malachi",                                             4, 39),
    ("matthew",         "MAT", "Matthew",           "The Gospel According to Matthew",                    28, 40),
    ("mark",            "MRK", "Mark",              "The Gospel According to Mark",                       16, 41),
    ("luke",            "LUK", "Luke",              "The Gospel According to Luke",                       24, 42),
    ("john",            "JHN", "John",              "The Gospel According to John",                       21, 43),
    ("acts",            "ACT", "Acts",              "The Acts of the Apostles",                           28, 44),
    ("romans",          "ROM", "Romans",            "The Epistle of Paul to the Romans",                  16, 45),
    ("1corinthians",    "1CO", "1 Corinthians",     "The First Epistle of Paul to the Corinthians",       16, 46),
    ("2corinthians",    "2CO", "2 Corinthians",     "The Second Epistle of Paul to the Corinthians",      13, 47),
    ("galatians",       "GAL", "Galatians",         "The Epistle of Paul to the Galatians",                6, 48),
    ("ephesians",       "EPH", "Ephesians",         "The Epistle of Paul to the Ephesians",                6, 49),
    ("philippians",     "PHP", "Philippians",       "The Epistle of Paul to the Philippians",              4, 50),
    ("colossians",      "COL", "Colossians",        "The Epistle of Paul to the Colossians",               4, 51),
    ("1thessalonians",  "1TH", "1 Thessalonians",   "The First Epistle of Paul to the Thessalonians",      5, 52),
    ("2thessalonians",  "2TH", "2 Thessalonians",   "The Second Epistle of Paul to the Thessalonians",     3, 53),
    ("1timothy",        "1TI", "1 Timothy",         "The First Epistle of Paul to Timothy",                6, 54),
    ("2timothy",        "2TI", "2 Timothy",         "The Second Epistle of Paul to Timothy",               4, 55),
    ("titus",           "TIT", "Titus",             "The Epistle of Paul to Titus",                        3, 56),
    ("philemon",        "PHM", "Philemon",          "The Epistle of Paul to Philemon",                     1, 57),
    ("hebrews",         "HEB", "Hebrews",           "The Epistle to the Hebrews",                         13, 58),
    ("james",           "JAS", "James",             "The General Epistle of James",                        5, 59),
    ("1peter",          "1PE", "1 Peter",           "The First Epistle General of Peter",                  5, 60),
    ("2peter",          "2PE", "2 Peter",           "The Second Epistle General of Peter",                 3, 61),
    ("1john",           "1JN", "1 John",            "The First Epistle General of John",                   5, 62),
    ("2john",           "2JN", "2 John",            "The Second Epistle General of John",                  1, 63),
    ("3john",           "3JN", "3 John",            "The Third Epistle General of John",                   1, 64),
    ("jude",            "JUD", "Jude",              "The General Epistle of Jude",                         1, 65),
    ("revelation",      "REV", "Revelation",        "The Revelation of John",                             22, 66),
]

# Build lookup: book_number -> (book_id, book_name, book_long, num_chapters)
BOOK_BY_NUMBER = {
    b[5]: (b[1], b[2], b[3], b[4]) for b in BOOKS
}


# ─── Red-Letter Parsing ────────────────────────────────────────────────────

def parse_red_letter_segments(text: str) -> list:
    """Parse text with ‹›  red-letter markers into segments.

    ‹ = \\u2039 (LEFT-POINTING SINGLE ANGLE QUOTATION MARK)  — opens red-letter
    › = \\u203a (RIGHT-POINTING SINGLE ANGLE QUOTATION MARK) — closes red-letter

    Also strips [bracket] italic markers and ¶ paragraph markers.
    """
    # Remove paragraph markers
    text = text.replace("\u00b6", "").strip()

    segments = []
    is_red = False
    buffer = ""

    for char in text:
        if char == "\u2039":  # ‹ opens red-letter
            if buffer.strip():
                segments.append({"text": buffer.strip() + " ", "isRedLetter": is_red})
            buffer = ""
            is_red = True
        elif char == "\u203a":  # › closes red-letter
            if buffer.strip():
                segments.append({"text": buffer.strip() + " ", "isRedLetter": is_red})
            buffer = ""
            is_red = False
        else:
            buffer += char

    if buffer.strip():
        segments.append({"text": buffer.strip(), "isRedLetter": is_red})

    # Clean up trailing spaces on last segment
    if segments and segments[-1]["text"].endswith(" "):
        segments[-1]["text"] = segments[-1]["text"].rstrip()

    return segments if segments else [{"text": text.strip(), "isRedLetter": False}]


# ─── wldeh/bible-api fetcher (WEB, ASV) ────────────────────────────────────

def fetch_chapter_json(repo_key: str, book_folder: str, chapter_num: int) -> list:
    """Fetch a chapter's verse data from wldeh/bible-api on GitHub."""
    encoded_book = urllib.request.pathname2url(book_folder)
    url = f"{WLDEH_BASE_URL}/{repo_key}/books/{encoded_book}/chapters/{chapter_num}.json"
    for attempt in range(3):
        try:
            req = urllib.request.Request(url)
            req.add_header("User-Agent", "ScriptureScribe-BuildScript/1.0")
            with urllib.request.urlopen(req, timeout=15) as resp:
                raw = json.loads(resp.read().decode("utf-8"))
                return raw.get("data", [])
        except urllib.error.HTTPError as e:
            if e.code == 404:
                return []
            print(f"    HTTP {e.code} for {url}, retrying...")
            time.sleep(1)
        except Exception as e:
            print(f"    Error fetching {url}: {e}, retrying...")
            time.sleep(1)
    return []


# ─── Bible SuperSearch KJV fetcher ──────────────────────────────────────────

def fetch_kjv_supersearch() -> dict:
    """Download KJV JSON from Bible SuperSearch (SourceForge).

    Returns a dict keyed by (book_number, chapter, verse) -> text with ‹› markup.
    The ‹› characters mark Jesus' words (red-letter text).
    """
    print("  Downloading KJV with red-letter markup from Bible SuperSearch...")

    req = urllib.request.Request(KJV_SUPERSEARCH_URL)
    req.add_header("User-Agent", "ScriptureScribe-BuildScript/1.0")
    with urllib.request.urlopen(req, timeout=60) as resp:
        raw_data = json.loads(resp.read().decode("utf-8"))

    # Format: {"metadata": {...}, "verses": [{book, chapter, verse, text}, ...]}
    verses = {}
    for v in raw_data["verses"]:
        book_num = int(v["book"])
        chapter = int(v["chapter"])
        verse_num = int(v["verse"])
        verses[(book_num, chapter, verse_num)] = v["text"]

    print(f"  Loaded {len(verses)} verses ({sum(1 for t in verses.values() if chr(0x2039) in t)} with red-letter)")
    return verses


def build_kjv_translation(config: dict) -> dict:
    """Build KJV with red-letter markup from Bible SuperSearch data."""
    print(f"\nProcessing KJV (with red-letter)...")

    kjv_verses = fetch_kjv_supersearch()

    books_out = []
    chapters_out = []
    total_verses = 0
    red_letter_count = 0

    for _, book_id, book_name, book_long, num_chapters, book_num in BOOKS:
        chapter_ids = []
        book_verse_count = 0

        for chap_num in range(1, num_chapters + 1):
            chapter_id = f"{book_id}.{chap_num}"
            chapter_ids.append(chapter_id)

            verses = []
            v_num = 1
            while True:
                text = kjv_verses.get((book_num, chap_num, v_num))
                if text is None:
                    break

                # Parse red-letter markers
                has_red = "\u2039" in text or "\u203a" in text
                if has_red:
                    red_letter_count += 1
                    segments = parse_red_letter_segments(text)
                else:
                    # Strip paragraph markers, clean up
                    clean = text.replace("\u00b6", "").strip()
                    segments = [{"text": clean, "isRedLetter": False}]

                verses.append({
                    "number": str(v_num),
                    "segments": segments,
                })
                v_num += 1

            book_verse_count += len(verses)

            chapters_out.append({
                "id": chapter_id,
                "bookId": book_id,
                "number": str(chap_num),
                "reference": f"{book_name} {chap_num}",
                "copyright": config["copyright"],
                "verses": verses,
            })

        total_verses += book_verse_count
        print(f"  {book_name}: {num_chapters} chapters, {book_verse_count} verses")

        books_out.append({
            "id": book_id,
            "name": book_name,
            "nameLong": book_long,
            "abbreviation": book_id,
            "chapterIds": chapter_ids,
        })

    print(f"  Total: {len(books_out)} books, {len(chapters_out)} chapters, {total_verses} verses")
    print(f"  Red-letter verses: {red_letter_count}")

    return {
        "metadata": {
            "translationKey": "KJV",
            "apiBibleId": config["api_bible_id"],
            "name": config["display_name"],
            "abbreviation": config["abbreviation"],
            "copyright": config["copyright"],
            "books": books_out,
        },
        "chapters": chapters_out,
    }


# ─── wldeh builder (WEB, ASV) ──────────────────────────────────────────────

def build_wldeh_translation(key: str, config: dict) -> dict:
    """Build a translation from wldeh/bible-api (no red-letter)."""
    print(f"\nProcessing {key} ({config['repo_key']})...")

    books_out = []
    chapters_out = []
    total_verses = 0

    for book_folder, book_id, book_name, book_long, num_chapters, _ in BOOKS:
        chapter_ids = []
        book_verse_count = 0

        for chap_num in range(1, num_chapters + 1):
            chapter_id = f"{book_id}.{chap_num}"
            chapter_ids.append(chapter_id)

            verse_data = fetch_chapter_json(config["repo_key"], book_folder, chap_num)

            # Deduplicate verses
            seen_verses = set()
            verses = []
            for v in verse_data:
                v_num = str(v.get("verse", ""))
                if v_num in seen_verses:
                    continue
                seen_verses.add(v_num)
                text = v.get("text", "").strip()
                if text:
                    verses.append({
                        "number": v_num,
                        "segments": [{"text": text, "isRedLetter": False}],
                    })

            book_verse_count += len(verses)

            chapters_out.append({
                "id": chapter_id,
                "bookId": book_id,
                "number": str(chap_num),
                "reference": f"{book_name} {chap_num}",
                "copyright": config["copyright"],
                "verses": verses,
            })

        total_verses += book_verse_count
        print(f"  {book_name}: {num_chapters} chapters, {book_verse_count} verses")

        books_out.append({
            "id": book_id,
            "name": book_name,
            "nameLong": book_long,
            "abbreviation": book_id,
            "chapterIds": chapter_ids,
        })

    print(f"  Total: {len(books_out)} books, {len(chapters_out)} chapters, {total_verses} verses")

    return {
        "metadata": {
            "translationKey": key,
            "apiBibleId": config["api_bible_id"],
            "name": config["display_name"],
            "abbreviation": config["abbreviation"],
            "copyright": config["copyright"],
            "books": books_out,
        },
        "chapters": chapters_out,
    }


# ─── Main ──────────────────────────────────────────────────────────────────

def main():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    output_dir = os.path.join(script_dir, "output")
    os.makedirs(output_dir, exist_ok=True)

    # Allow building a single translation: python3 build_offline_bible.py KJV
    only = sys.argv[1].upper() if len(sys.argv) > 1 else None

    for key, config in TRANSLATIONS.items():
        if only and key != only:
            continue

        if config["source"] == "biblesupersearch":
            package = build_kjv_translation(config)
        else:
            package = build_wldeh_translation(key, config)

        # Write compressed JSON
        json_bytes = json.dumps(package, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
        gz_path = os.path.join(output_dir, f"{key}.json.gz")
        with gzip.open(gz_path, "wb") as f:
            f.write(json_bytes)

        # Also write uncompressed for inspection
        json_path = os.path.join(output_dir, f"{key}.json")
        with open(json_path, "w", encoding="utf-8") as f:
            json.dump(package, f, ensure_ascii=False, indent=2)

        uncompressed_mb = len(json_bytes) / (1024 * 1024)
        compressed_mb = os.path.getsize(gz_path) / (1024 * 1024)
        print(f"  Output: {gz_path}")
        print(f"    {compressed_mb:.1f} MB compressed, {uncompressed_mb:.1f} MB uncompressed")

    print("\nDone! Upload the .json.gz files to Firebase Storage under offline-bibles/")


if __name__ == "__main__":
    main()
