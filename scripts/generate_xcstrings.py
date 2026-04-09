#!/usr/bin/env python3

import ast
import json
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1] / "SemanticCompression-v2"
SOURCE_LANGUAGE = "en"
LANGUAGE_DIRS = [
    ("en.lproj", "en"),
    ("ja.lproj", "ja"),
    ("ko.lproj", "ko"),
    ("es.lproj", "es"),
    ("pt-BR.lproj", "pt-BR"),
    ("zh-Hans.lproj", "zh-Hans"),
    ("zh-Hant.lproj", "zh-Hant"),
]
ENTRY_RE = re.compile(r'^"((?:\\.|[^"])*)"\s*=\s*"((?:\\.|[^"])*)";\s*$')


def decode_escaped(text: str) -> str:
    escaped = text.replace("\\", "\\\\").replace('"', '\\"')
    escaped = escaped.replace("\\\\\\\\n", "\\n").replace("\\\\\\\\\"", "\\\"")
    return ast.literal_eval(f'"{escaped}"')


def parse_strings(path: Path) -> dict[str, str]:
    entries: dict[str, str] = {}
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("//"):
            continue
        match = ENTRY_RE.match(line)
        if not match:
            raise ValueError(f"Unsupported strings entry in {path}: {raw_line}")
        key = decode_escaped(match.group(1))
        value = decode_escaped(match.group(2))
        entries[key] = value
    return entries


def main() -> None:
    all_entries: dict[str, dict[str, str]] = {}

    for folder, language in LANGUAGE_DIRS:
        strings_path = ROOT / folder / "Localizable.strings"
        entries = parse_strings(strings_path)
        for key, value in entries.items():
            all_entries.setdefault(key, {})[language] = value

    catalog = {
        "sourceLanguage": SOURCE_LANGUAGE,
        "strings": {},
        "version": "1.0",
    }

    for key in sorted(all_entries):
        localizations = {}
        for language, value in sorted(all_entries[key].items()):
            localizations[language] = {
                "stringUnit": {
                    "state": "translated",
                    "value": value,
                }
            }
        catalog["strings"][key] = {
            "extractionState": "manual",
            "localizations": localizations,
        }

    output_path = ROOT / "Localizable.xcstrings"
    output_path.write_text(
        json.dumps(catalog, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )


if __name__ == "__main__":
    main()
