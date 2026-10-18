#!/usr/bin/env python3
"""Reject missing translations, mismatched printf arguments, and uncatalogued app copy."""
import hashlib
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
APP_DIR = ROOT / 'SemanticCompression-v2'
LANGUAGES = ('en', 'ja', 'ko', 'es', 'pt-BR', 'zh-Hans', 'zh-Hant')
FORMAT = re.compile(r'%(?:(\d+)\$)?[-+ #0]*(?:\d+|\*)?(?:\.(?:\d+|\*))?(hh|ll|[hlqztj])?([@diuoxXfFeEgGaAcCsSp])')
SWIFT_STRING = re.compile(r'"((?:[^"\\]|\\.)*)"')
JAPANESE = re.compile(r'[\u3040-\u30ff\u3400-\u9fff]')
NATIVE_LANGUAGE_NAMES = {'日本語', '简体中文', '繁體中文'}


def format_signature(text):
    # A literal %% consumes no argument. Positional formats may reorder arguments.
    text = text.replace('%%', '')
    arguments = {}
    next_position = 1
    for match in FORMAT.finditer(text):
        position = int(match[1]) if match[1] else next_position
        arguments[position] = (match[2] or '') + match[3]
        next_position += 1
    return arguments


def catalog_errors(strings):
    errors = []
    for key, entry in strings.items():
        localizations = entry.get('localizations', {})
        source = localizations.get('en', {}).get('stringUnit', {}).get('value', '')
        signature = format_signature(source)
        for language in LANGUAGES:
            unit = localizations.get(language, {}).get('stringUnit', {})
            if not unit.get('value') or unit.get('state') != 'translated':
                errors.append(f'{key}: {language} is missing or untranslated')
            elif format_signature(unit['value']) != signature:
                errors.append(f'{key}: {language} has mismatched format arguments')
    return errors


def swift_literals(source):
    for raw in SWIFT_STRING.findall(source):
        if '\\(' in raw:
            continue
        yield raw.replace('\\n', '\n').replace('\\"', '"').replace('\\\\', '\\')


def copy_errors(strings, app_dir=APP_DIR):
    errors = []
    for path in app_dir.rglob('*.swift'):
        if 'Diagnostics' in path.parts or path.name.endswith(' 2.swift'):
            continue
        for source in swift_literals(path.read_text(encoding='utf-8')):
            if not JAPANESE.search(source) or source in NATIVE_LANGUAGE_NAMES:
                continue
            key = 'mim.refresh.' + hashlib.sha256(source.encode()).hexdigest()[:16]
            if key not in strings:
                errors.append(f'{path.relative_to(app_dir)}: uncatalogued copy {source!r}')
    return sorted(set(errors))


def main():
    strings = json.loads((APP_DIR / 'Localizable.xcstrings').read_text())['strings']
    errors = catalog_errors(strings) + copy_errors(strings)
    if errors:
        print('\n'.join(errors))
        return 1
    print(f'{len(strings)} strings translated in all {len(LANGUAGES)} languages; format arguments and app copy verified.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
