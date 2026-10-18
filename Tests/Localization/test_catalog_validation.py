import importlib.util
from pathlib import Path
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[2] / 'scripts/check_localization_coverage.py'
spec = importlib.util.spec_from_file_location('coverage', SCRIPT)
coverage = importlib.util.module_from_spec(spec)
spec.loader.exec_module(coverage)

class CatalogValidationTests(unittest.TestCase):
    def catalog(self, text='%@ has %ld posts'):
        return {'example': {'localizations': {
            language: {'stringUnit': {'state': 'translated', 'value': text}}
            for language in coverage.LANGUAGES}}}

    def test_missing_supported_language_fails(self):
        catalog = self.catalog()
        del catalog['example']['localizations']['zh-Hant']
        self.assertEqual(len(coverage.catalog_errors(catalog)), 1)

    def test_english_placeholder_marked_for_review_fails(self):
        catalog = self.catalog()
        catalog['example']['localizations']['ko']['stringUnit']['state'] = 'needs_review'
        self.assertEqual(len(coverage.catalog_errors(catalog)), 1)

    def test_positional_arguments_can_reorder(self):
        catalog = self.catalog()
        catalog['example']['localizations']['ja']['stringUnit']['value'] = '%2$ld件: %1$@'
        self.assertEqual(coverage.catalog_errors(catalog), [])

    def test_missing_or_wrong_type_format_argument_fails(self):
        for text in ['%@', '%@ has %@ posts', '%@ has %d posts']:
            catalog = self.catalog()
            catalog['example']['localizations']['es']['stringUnit']['value'] = text
            self.assertEqual(len(coverage.catalog_errors(catalog)), 1)

    def test_literal_percent_uses_no_argument(self):
        self.assertEqual(coverage.format_signature('100%% complete'), {})

    def test_changed_runtime_copy_requires_new_translation(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'View.swift'
            path.write_text('Text(mt("写真を処理中"))')
            self.assertEqual(len(coverage.copy_errors({}, Path(folder))), 1)

if __name__ == '__main__':
    unittest.main()
