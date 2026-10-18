# Localization Workflow

`SemanticCompression-v2/Localizable.xcstrings` is the source of truth.

## Update flow

1. Edit `Localizable.xcstrings`.
2. Run:

```bash
python3 scripts/sync_localizations.py
```

3. Commit both the catalog and the generated `*.lproj/Localizable.strings` files.

## Manual commands

If you want to run each step separately:

```bash
python3 scripts/export_strings_from_xcstrings.py
python3 scripts/check_xcstrings_sync.py
```

## Bootstrap or rebuild the catalog

If the catalog needs to be recreated from the existing `Localizable.strings` files, run:

```bash
python3 scripts/generate_xcstrings.py
```

## Notes

- Supported languages currently: `ja`, `en`, `ko`, `es`, `pt-BR`, `zh-Hans`, `zh-Hant`
- `Localizable.strings` files are kept for compatibility and easier diffs, but they should be treated as generated artifacts.

- Run commands from the repository root. `sync_localizations.py` also checks seven-language coverage, translation state, printf arguments, and Japanese app copy before exporting.
- Model names, upstream license texts, user posts, and the English prompts used by image models retain their original language.
- Runtime copy from `mt()` uses a SHA-256-derived key. Add all seven translations whenever that source text changes; never mark an English fallback as translated.
