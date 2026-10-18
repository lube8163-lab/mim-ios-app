#!/usr/bin/env python3
"""Prepare notices in a marked staging COPY; never export, infer, zip or upload a model."""
import argparse
import hashlib
import json
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
SOURCE_REVISIONS = {'flux': 'a7f65cdd6b2c8e2616dab3887efd0ae6ce983e44', 'lfm': 'f6648f9c65402a4d5c280cae41b672f977e74e3a'}
FILES = {
    'flux': ['FLUX2-LICENSE.txt', 'Qwen3-4B-LICENSE.txt', 'FLUX2-MIM-MODIFICATIONS.txt'],
    'lfm': ['LFM-Open-License-v1.0.txt', 'LFM-upstream-NOTICE.txt', 'LFM-MIM-NOTICE.txt', 'SigLIP2-Apache-LICENSE.txt'],
}

def checked_path(root, relative):
    path = root / relative
    if Path(relative).is_absolute() or '..' in Path(relative).parts or not path.resolve().is_relative_to(root.resolve()):
        raise ValueError('Unsafe package path')
    if any(p.is_symlink() for p in [path, *path.parents] if p == root or root in p.parents):
        raise ValueError('Symlink package paths are not accepted')
    return path

def record(root, relative):
    path = checked_path(root, relative)
    return {'path': relative, 'bytes': path.stat().st_size, 'sha256': hashlib.sha256(path.read_bytes()).hexdigest()}

def prepare(root, kind, revision, source_manifest=None):
    root = Path(root)
    if root.is_symlink() or not (root / '.mim-package-staging').is_file():
        raise ValueError('Only a copy marked .mim-package-staging may be changed')
    if kind not in FILES or not revision or revision in ['coreai-512-4bit-a7f65cd-v1', 'lfm2-vl-450m-f6648f9-v1']:
        raise ValueError('Choose a new immutable package revision')
    manifest = json.loads(Path(source_manifest).read_text()) if source_manifest else None
    if kind == 'flux' and (manifest is None or not isinstance(manifest.get('files'), list)):
        raise ValueError('FLUX requires the validated source manifest')
    if manifest:
        if revision == manifest.get('revision'):
            raise ValueError('Source revision must not be overwritten')
        for entry in manifest['files']:
            path = checked_path(root, entry['path'])
            if not path.is_file() or path.stat().st_size != entry['bytes']:
                raise ValueError('Source asset is missing or has changed size')
    notices = checked_path(root, 'MIM_licenses'); notices.mkdir(exist_ok=True)
    changed = []
    for name in FILES[kind]:
        source = REPO / 'licenses' / name
        target = checked_path(root, 'MIM_licenses/' + name)
        # Do not silently replace an existing third-party notice.
        if target.exists() and target.read_bytes() != source.read_bytes():
            raise ValueError('Existing notice differs: ' + name)
        target.write_bytes(source.read_bytes()); changed.append(str(target.relative_to(root)))
    if kind == 'flux':
        relative = 'Transformer_512.aimodel/metadata.json'
        path = checked_path(root, relative)
        metadata = json.loads(path.read_text())
        notice = '\nMim modification: existing 512px half graph extracted and renamed main; converted 4bit weights retained. See MIM_licenses/FLUX2-MIM-MODIFICATIONS.txt.'
        if notice not in metadata.get('description', ''):
            metadata['description'] = metadata.get('description', '') + notice
            path.write_text(json.dumps(metadata, indent=2) + '\n')
        changed.append(relative)
    records = [record(root, relative) for relative in changed]
    license_manifest = {'schemaVersion': 1, 'kind': kind, 'packageRevision': revision,
        'sourceConversionRevision': SOURCE_REVISIONS[kind], 'files': records}
    (root / 'license-manifest.json').write_text(json.dumps(license_manifest, indent=2) + '\n')
    if kind == 'flux':
        # Model byte hashes are reused from a validated copy, without reading GB-scale
        # weights. Archive/install verification still checks the actual model bytes.
        files = {entry['path']: entry for entry in manifest['files']}
        for entry in records + [record(root, 'license-manifest.json')]: files[entry['path']] = entry
        manifest['revision'] = revision; manifest['files'] = sorted(files.values(), key=lambda x: x['path'])
        (root / 'model-manifest.next.json').write_text(json.dumps(manifest, indent=2) + '\n')
    return license_manifest

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--staging-root', type=Path, required=True)
    parser.add_argument('--kind', choices=FILES, required=True)
    parser.add_argument('--package-revision', required=True)
    parser.add_argument('--source-manifest', type=Path)
    args = parser.parse_args()
    print(json.dumps(prepare(args.staging_root, args.kind, args.package_revision, args.source_manifest), indent=2))

if __name__ == '__main__': main()
