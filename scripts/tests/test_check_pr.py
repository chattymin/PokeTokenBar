#!/usr/bin/env python3
"""Behavioral tests for the repository's local PR checker (isolated fixtures)."""
import importlib.util
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[2]
SCRIPT = REPO / 'scripts/check-pr.py'
spec = importlib.util.spec_from_file_location('check_pr', SCRIPT)
check_pr = importlib.util.module_from_spec(spec)
spec.loader.exec_module(check_pr)
TEMPLATE = (REPO / '.github/PULL_REQUEST_TEMPLATE.md').read_text()


def body(ui=None):
    text = '''## Summary

Require UI image evidence when preparing repository PRs.

## Type of change

- [x] Documentation
'''
    if ui is not None:
        text += '\n## UI changes\n\n' + ui + '\n'
    text += '\n## Checklist\n\n' + '\n'.join(
        '- [ ] ' + label for _, label in check_pr.checkboxes(
            check_pr.sections(check_pr.prose(TEMPLATE))['Checklist'])) + '\n'
    return text


class ContentTests(unittest.TestCase):
    def errors(self, content, ui=False, title='docs: require UI images in PRs'):
        return check_pr.validate(title, content, TEMPLATE, ui)

    def test_non_ui_filled_template(self):
        self.assertEqual([], self.errors(body()))

    def test_existing_ui_two_images(self):
        ui = '| Before | After |\n| -- | -- |\n| ![Before - App screenshot](https://github.com/user-attachments/assets/before) | ![After - Sample-data render](https://raw.githubusercontent.com/chattymin/PokeTokenBar/abc123/after.png) |'
        self.assertEqual([], self.errors(body(ui), ui=True))

    def test_new_screen_one_image(self):
        ui = 'No previous screen exists. Illustration / mockup.\n\n![New screen](https://github.com/user-attachments/assets/new)'
        self.assertEqual([], self.errors(body(ui), ui=True))

    def test_no_image_fails(self):
        self.assertTrue(self.errors(body('Attachment unavailable; text describes the screen.'), ui=True))

    def test_missing_ui_section_fails(self):
        errors = self.errors(body(), ui=True)
        self.assertTrue(any("'UI changes'" in e for e in errors))
        self.assertTrue(any('must embed images' in e for e in errors))

    def test_image_in_summary_does_not_count(self):
        content = body('The existing screen has changed.').replace('Require UI image evidence', '![Overview](https://example.com/overview.png)\n\nRequire UI image evidence')
        self.assertTrue(self.errors(content, ui=True))

    def test_local_paths_and_blob_links_fail(self):
        for path in ('/tmp/after.png', 'file:///tmp/after.png', 'assets/after.png', 'http://example.com/after.png', 'https://github.com/chattymin/PokeTokenBar/blob/main/assets/after.png'):
            with self.subTest(path=path):
                self.assertTrue(self.errors(body(f'![After]({path})'), ui=True))

    def test_raw_blob_link_passes(self):
        self.assertEqual([], self.errors(body('![After](https://github.com/chattymin/PokeTokenBar/blob/main/assets/after.png?raw=true)'), ui=True))

    def test_comments_and_fenced_code_do_not_count(self):
        for ui in ('<!-- ![After](https://example.com/after.png) -->', '```markdown\n![After](https://example.com/after.png)\n```', '~~~markdown\n![After](https://example.com/after.png)\n~~~'):
            with self.subTest(ui=ui):
                self.assertTrue(self.errors(body(ui), ui=True))

    def test_inline_code_does_not_count(self):
        self.assertTrue(self.errors(body('Use `![After](https://example.com/after.png)` to embed an image.'), ui=True))

    def test_multiple_backtick_inline_code_does_not_count(self):
        self.assertTrue(self.errors(body('Use ``![After](https://example.com/after.png)`` as an example.'), ui=True))

    def test_indented_code_does_not_count(self):
        self.assertTrue(self.errors(body('    ![After](https://example.com/after.png)'), ui=True))

    def test_escaped_markdown_image_does_not_count(self):
        self.assertTrue(self.errors(body(r'\![After](https://example.com/after.png)'), ui=True))

    def test_longer_fence_close_does_not_count(self):
        self.assertTrue(self.errors(body('```markdown\n![After](https://example.com/after.png)\n````'), ui=True))

    def test_unclosed_fence_does_not_count(self):
        self.assertTrue(self.errors(body('```markdown\n![After](https://example.com/after.png)'), ui=True))

    def test_reference_image_definition_outside_ui(self):
        content = body('![After][after]') + '\n[after]: https://example.com/after.png\n'
        self.assertEqual([], self.errors(content, ui=True))

    def test_reference_definition_alone_not_image(self):
        self.assertTrue(self.errors(body('[after]: https://example.com/after.png'), ui=True))

    def test_template_comment_and_table_do_not_satisfy_ui(self):
        filled = TEMPLATE.replace('<!-- What does this PR do, and why? Keep it focused. -->', 'Update the UI.').replace('- [ ] Documentation', '- [x] Documentation')
        self.assertTrue(any('must embed images' in e for e in self.errors(filled, ui=True)))

    def test_template_checklist_preserved(self):
        content = body()
        item = check_pr.checkboxes(check_pr.sections(check_pr.prose(TEMPLATE))['Checklist'])[0][1]
        self.assertTrue(any('Keep the template checklist item' in e for e in self.errors(content.replace('- [ ] ' + item, ''))))

    def test_type_of_change_must_be_selected(self):
        self.assertTrue(any('Select the actual Type of change' in e for e in self.errors(body().replace('[x] Documentation', '[ ] Documentation'))))

    def test_title_format(self):
        for title in ('fix: repair usage display', 'feat(home)!: add a new dashboard', 'chore(deps): update the toolchain'):
            with self.subTest(title=title):
                self.assertEqual([], self.errors(body(), title=title))
        for title in ('SUP-1234 Fix usage', 'fix:', 'Fix: usage', 'fix: first line\nsecond line'):
            with self.subTest(title=title):
                self.assertTrue(self.errors(body(), title=title))


class CliTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix='ptb-check-pr-')
        self.root = Path(self.directory.name)
        (self.root / 'scripts').mkdir()
        shutil.copyfile(SCRIPT, self.root / 'scripts/check-pr.py')
        (self.root / '.github').mkdir()
        (self.root / '.github/PULL_REQUEST_TEMPLATE.md').write_text(TEMPLATE)
        self.env = dict(os.environ, GIT_AUTHOR_NAME='PR checker fixture', GIT_AUTHOR_EMAIL='fixture@example.com', GIT_COMMITTER_NAME='PR checker fixture', GIT_COMMITTER_EMAIL='fixture@example.com')
        self.run_git('init', '-b', 'main')
        (self.root / 'README.md').write_text('Fixture\n')
        self.run_git('add', 'README.md', '.github', 'scripts')
        self.run_git('commit', '-m', 'docs: create fixture')
        self.run_git('branch', 'base')
        self.body_path = self.root / 'body.md'
        self.body_path.write_text(body())

    def tearDown(self):
        self.directory.cleanup()

    def run_git(self, *args):
        result = subprocess.run(['git', *args], cwd=self.root, env=self.env, text=True, capture_output=True)
        self.assertEqual(0, result.returncode, result.stderr)
        return result

    def change(self, filename, content='fixture\n'):
        path = self.root / filename
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)
        self.run_git('add', filename)
        self.run_git('commit', '-m', 'docs: update fixture')

    def cli(self, *args, body_path=None):
        return subprocess.run([sys.executable, str(self.root / 'scripts/check-pr.py'), '--base', 'base', '--title', 'docs: update fixture', '--body-file', str(body_path or self.body_path), *args], cwd=self.root, env=self.env, text=True, capture_output=True)

    def test_non_ui_diff_passes(self):
        self.change('README.md')
        self.assertEqual(0, self.cli().returncode)

    def test_ui_path_diff_requires_images(self):
        self.change('Sources/PokeTokenBar/UI/HomeView.swift')
        result = self.cli()
        self.assertEqual(1, result.returncode)
        self.assertIn('must embed images', result.stderr)

    def test_ui_path_diff_with_images_passes(self):
        self.change('Sources/PokeTokenBar/UI/HomeView.swift')
        self.body_path.write_text(body('No previous screen exists.\n\n![New - Illustration / mockup](https://example.com/new.png)'))
        self.assertEqual(0, self.cli().returncode)

    def test_visible_change_outside_ui_requires_override(self):
        self.change('Sources/PokeTokenBar/Resources/Localizable.strings')
        self.assertEqual(0, self.cli().returncode)
        self.assertEqual(1, self.cli('--ui-changes').returncode)

    def test_ui_directory_nonvisible_change_accepts_reviewed_reason(self):
        self.change('Sources/PokeTokenBar/UI/HomeView.swift', '// Clarify a comment; runtime UI is unchanged.\n')
        reason = 'Only a source comment changes; rendered screens and states are unchanged.'
        result = self.cli('--no-ui-changes', reason)
        self.assertEqual(0, result.returncode, result.stderr)
        self.assertIn(reason, result.stdout)

    def test_no_ui_changes_reason_must_not_be_empty(self):
        self.change('Sources/PokeTokenBar/UI/HomeView.swift')
        result = self.cli('--no-ui-changes', '   ')
        self.assertNotEqual(0, result.returncode)

    def test_ui_flags_are_mutually_exclusive(self):
        result = self.cli('--ui-changes', '--no-ui-changes', 'Source comments only.')
        self.assertNotEqual(0, result.returncode)
        self.assertIn('not allowed', result.stderr)

    def test_no_ui_changes_reason_still_inspects_git_diff(self):
        result = self.cli('--base', 'nonexistent-ref', '--no-ui-changes', 'Source comments only.')
        self.assertEqual(1, result.returncode)
        self.assertIn('PR check failed:', result.stderr)

    def test_invalid_base_failure(self):
        result = self.cli('--base', 'nonexistent-ref')
        self.assertEqual(1, result.returncode)
        self.assertIn('PR check failed:', result.stderr)

    def test_invalid_head_failure_even_with_ui_override(self):
        result = self.cli('--head', 'nonexistent-ref', '--ui-changes')
        self.assertEqual(1, result.returncode)
        self.assertIn('PR check failed:', result.stderr)

    def test_missing_body_failure(self):
        result = self.cli(body_path=self.root / 'missing-body.md')
        self.assertEqual(1, result.returncode)
        self.assertIn('PR check failed:', result.stderr)


if __name__ == '__main__':
    unittest.main(verbosity=2)
