#!/usr/bin/env python
"""Check whether MinerU output is usable for Chinese document interpretation."""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path


MOJIBAKE_MARKERS = (
    "\ufffd",
    "锟",
    "�",
    "璁烘枃",
    "闃呰",
    "褰掔撼",
    "杈圭紭",
    "绔",
    "鍩轰",
    "缁撴灉",
    "涓枃",
    "鏂囨湰",
    "閫熷櫒",
    "鈥",
    "â",
    "Â",
)
SUSPICIOUS_SYMBOLS = set("\ufffd�������")
MIN_CJK_RATIO = 0.12
MAX_MOJIBAKE_RATIO = 0.025
MAX_REPLACEMENT_RATIO = 0.002
MAX_SUSPICIOUS_RATIO = 0.03


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8", errors="replace")


def cjk_count(text: str) -> int:
    return sum(1 for ch in text if "\u4e00" <= ch <= "\u9fff")


def marker_count(text: str) -> int:
    return sum(text.count(marker) for marker in MOJIBAKE_MARKERS)


def replacement_count(text: str) -> int:
    return text.count("\ufffd")


def suspicious_symbol_count(text: str) -> int:
    return sum(1 for ch in text if ch in SUSPICIOUS_SYMBOLS)


def table_count(text: str) -> int:
    return text.count("<table") + len(re.findall(r"^\|.+\|$", text, re.M))


def image_count(text: str) -> int:
    return len(re.findall(r"!\[[^\]]*\]\(([^)]+)\)", text))


def score_text(text: str) -> dict:
    total = max(len(text), 1)
    cjk = cjk_count(text)
    markers = marker_count(text)
    replacements = replacement_count(text)
    suspicious = suspicious_symbol_count(text)
    return {
        "chars": len(text),
        "cjk_chars": cjk,
        "cjk_ratio": round(cjk / total, 4),
        "mojibake_markers": markers,
        "mojibake_ratio": round(markers / total, 4),
        "replacement_chars": replacements,
        "replacement_ratio": round(replacements / total, 4),
        "suspicious_symbols": suspicious,
        "suspicious_symbol_ratio": round(suspicious / total, 4),
        "image_refs": image_count(text),
        "table_refs": table_count(text),
    }


def find_outputs(path: Path) -> tuple[Path | None, Path | None]:
    if path.is_file() and path.suffix.lower() == ".md":
        stem = path.stem
        auto = path.parent
        json_path = auto / f"{stem}_content_list.json"
        return path, json_path if json_path.exists() else None

    candidates = sorted(path.rglob("*.md"))
    if not candidates:
        return None, None
    md = candidates[0]
    json_path = md.with_name(f"{md.stem}_content_list.json")
    return md, json_path if json_path.exists() else None


def extract_json_text(path: Path) -> str:
    try:
        data = json.loads(read_text(path))
    except Exception:
        return ""
    parts: list[str] = []
    if isinstance(data, list):
        for item in data:
            if isinstance(item, dict):
                txt = item.get("text") or item.get("content") or ""
                if isinstance(txt, str):
                    parts.append(txt)
    return "\n".join(parts)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("path", help="MinerU output folder or markdown file")
    parser.add_argument("--json", action="store_true", help="Emit JSON only")
    args = parser.parse_args()

    root = Path(args.path)
    md_path, json_path = find_outputs(root)
    if not md_path:
        result = {"status": "fail", "reason": "no_markdown_found", "path": str(root)}
        print(json.dumps(result, ensure_ascii=False, indent=None if args.json else 2))
        return 2

    md_text = read_text(md_path)
    md_score = score_text(md_text)
    json_score = None
    if json_path:
        json_text = extract_json_text(json_path)
        json_score = score_text(json_text) if json_text else None

    best = md_score
    preferred_source = "markdown"
    if json_score and (
        json_score["cjk_ratio"] > md_score["cjk_ratio"]
        and json_score["mojibake_ratio"] <= md_score["mojibake_ratio"]
    ):
        best = json_score
        preferred_source = "content_list_json"

    status = "pass"
    reasons = []
    if best["cjk_ratio"] < MIN_CJK_RATIO:
        status = "review"
        reasons.append("low_chinese_ratio")
    if best["mojibake_ratio"] > MAX_MOJIBAKE_RATIO:
        status = "review"
        reasons.append("high_mojibake_ratio")
    if best["replacement_ratio"] > MAX_REPLACEMENT_RATIO:
        status = "review"
        reasons.append("unicode_replacement_chars")
    if best["suspicious_symbol_ratio"] > MAX_SUSPICIOUS_RATIO:
        status = "review"
        reasons.append("high_suspicious_symbol_ratio")
    if best["chars"] < 3000:
        status = "review"
        reasons.append("short_text")

    result = {
        "status": status,
        "reasons": reasons,
        "preferred_source": preferred_source,
        "markdown_path": str(md_path),
        "content_json_path": str(json_path) if json_path else None,
        "markdown": md_score,
        "content_list_json": json_score,
    }
    print(json.dumps(result, ensure_ascii=False, indent=None if args.json else 2))
    return 0 if status == "pass" else 1


if __name__ == "__main__":
    raise SystemExit(main())
