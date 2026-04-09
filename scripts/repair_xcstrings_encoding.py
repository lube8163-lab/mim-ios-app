#!/usr/bin/env python3

import json
from pathlib import Path


CATALOG_PATH = Path(__file__).resolve().parents[1] / "SemanticCompression-v2" / "Localizable.xcstrings"


def repair_text(value: str) -> str:
    try:
        repaired = value.encode("latin1").decode("utf-8")
    except (UnicodeEncodeError, UnicodeDecodeError):
        return value
    return repaired


def repair_node(node):
    if isinstance(node, dict):
        return {key: repair_node(value) for key, value in node.items()}
    if isinstance(node, list):
        return [repair_node(item) for item in node]
    if isinstance(node, str):
        return repair_text(node)
    return node


def main() -> None:
    catalog = json.loads(CATALOG_PATH.read_text(encoding="utf-8"))
    repaired = repair_node(catalog)
    CATALOG_PATH.write_text(
        json.dumps(repaired, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )


if __name__ == "__main__":
    main()
