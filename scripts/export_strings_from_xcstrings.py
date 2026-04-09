#!/usr/bin/env python3

import json
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


def main() -> None:
    catalog = json.loads(CATALOG_PATH.read_text(encoding="utf-8"))
    strings = catalog["strings"]

    for folder, language in LANGUAGE_DIRS:
        destination = APP_DIR / folder / "Localizable.strings"
        lines: list[str] = []

        for key in sorted(strings):
            localization = strings[key].get("localizations", {}).get(language)
            if localization is None:
                continue
            value = localization["stringUnit"]["value"]
            lines.append(f"\"{escape(key)}\" = \"{escape(value)}\";")

        destination.write_text("\n".join(lines) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
