#!/usr/bin/env python3

import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parent


def run(script_name: str) -> None:
    subprocess.run(
        ["python3", str(ROOT / script_name)],
        check=True,
    )


def main() -> None:
    run("export_strings_from_xcstrings.py")
    run("check_xcstrings_sync.py")


if __name__ == "__main__":
    main()
