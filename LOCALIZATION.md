# Localization Workflow

`/Users/tasuku/Desktop/SemanticCompression-v2/SemanticCompression-v2/Localizable.xcstrings` is the source of truth.

## Update flow

1. Edit `Localizable.xcstrings`.
2. Run:

```bash
python3 /Users/tasuku/Desktop/SemanticCompression-v2/scripts/sync_localizations.py
```

3. Commit both the catalog and the generated `*.lproj/Localizable.strings` files.

## Manual commands

If you want to run each step separately:

```bash
python3 /Users/tasuku/Desktop/SemanticCompression-v2/scripts/export_strings_from_xcstrings.py
python3 /Users/tasuku/Desktop/SemanticCompression-v2/scripts/check_xcstrings_sync.py
```

## Bootstrap or rebuild the catalog

If the catalog needs to be recreated from the existing `Localizable.strings` files, run:

```bash
python3 /Users/tasuku/Desktop/SemanticCompression-v2/scripts/generate_xcstrings.py
```

## Notes

- Supported languages currently: `ja`, `en`, `ko`, `es`, `pt-BR`, `zh-Hans`, `zh-Hant`
- `Localizable.strings` files are kept for compatibility and easier diffs, but they should be treated as generated artifacts.
