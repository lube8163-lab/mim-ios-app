#!/usr/bin/env python3
"""Restore the pinned, required safety model and verify every file before install."""
import hashlib
import json
import os
import shutil
import tempfile
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
spec = json.loads((ROOT / "docs/image-safety-assets.json").read_text())
destination = ROOT / "SemanticCompression-v2/Resources/Models/ImageSafetyClassifier.mlpackage"
destination.parent.mkdir(parents=True, exist_ok=True)
with tempfile.TemporaryDirectory(prefix="mim-safety-") as temporary:
    staging = Path(temporary) / "ImageSafetyClassifier.mlpackage"
    for item in spec["files"]:
        path = Path(item["path"])
        if path.is_absolute() or ".." in path.parts:
            raise ValueError("unsafe manifest path")
        output = staging / path
        output.parent.mkdir(parents=True, exist_ok=True)
        # The upstream repository places these files inside the mlpackage directory.
        remote = "ImageSafetyClassifier.mlpackage/" + item["path"]
        url = spec["source"] + "/resolve/" + spec["revision"] + "/" + urllib.parse.quote(remote, safe="/")
        with urllib.request.urlopen(url, timeout=60) as response, output.open("wb") as stream:
            shutil.copyfileobj(response, stream)
        content = output.read_bytes()
        if len(content) != item["bytes"] or hashlib.sha256(content).hexdigest() != item["sha256"]:
            raise ValueError("safety model integrity check failed: " + item["path"])
    # Refuse to overwrite an existing model with different or unverified content.
    if destination.exists():
        for item in spec["files"]:
            current = destination / item["path"]
            if not current.is_file() or hashlib.sha256(current.read_bytes()).hexdigest() != item["sha256"]:
                raise RuntimeError("existing safety model differs; preserve and inspect it before replacement")
    else:
        shutil.copytree(staging, destination)
print("Pinned safety model verified:", destination)
