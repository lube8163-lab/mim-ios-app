#!/usr/bin/env python3

import difflib
import json
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
APP_DIR = ROOT / "SemanticCompression-v2"
CATALOG_PATH = APP_DIR / "Localizable.xcstrings"
LANGUAGE_DIRS = [
    ("en.lproj", "en"),
    ("ja.lproj", "ja"),
    ("ko.lproj", "ko"),
    ("es.lproj", "es"),
    ("pt-BR.lproj", "pt-BR"),
    ("zh-Hans.lproj", "zh-Hans"),
    ("zh-Hant.lproj", "zh-Hant"),
]


def escape(value: str) -> str:
    return (
        value.replace("\\", "\\\\")
        .replace("\n", "\\n")
        .replace("\"", "\\\"")
    )


def compiled_lines(strings: dict, language: str) -> list[str]:
    lines: list[str] = []
    for key in sorted(strings):
        localization = strings[key].get("localizations", {}).get(language)
        if localization is None:
            continue
        value = localization["stringUnit"]["value"]
        lines.append(f"\"{escape(key)}\" = \"{escape(value)}\";")
    return lines


def main() -> int:
    catalog = json.loads(CATALOG_PATH.read_text(encoding="utf-8"))
    strings = catalog["strings"]
    diffs: list[str] = []

    for folder, language in LANGUAGE_DIRS:
        committed_path = APP_DIR / folder / "Localizable.strings"
        committed = committed_path.read_text(encoding="utf-8").splitlines()
        compiled = compiled_lines(strings, language)

        if committed != compiled:
            diff = "\n".join(
                difflib.unified_diff(
                    committed,
                    compiled,
                    fromfile=str(committed_path),
                    tofile=f"{committed_path} (generated from xcstrings)",
                    lineterm="",
                )
            )
            diffs.append(diff)

    if diffs:
        print("\n\n".join(diffs))
        return 1

    print("Localizable.xcstrings compiles to the committed Localizable.strings files.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
