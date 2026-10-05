#!/usr/bin/env python3
"""Check a PR locally against this repository's title, template, and image rules."""

import argparse
from pathlib import Path
import re
import subprocess
import sys
from urllib.parse import parse_qs, urlparse


ROOT = Path(__file__).resolve().parents[1]
TITLE = re.compile(
    r"(?:feat|fix|docs|chore|refactor|test|perf|style|build|ci|revert|release)"
    r"(?:\([^()\r\n]+\))?!?: \S[^\r\n]*"
)


def prose(markdown):
    """Exclude comments and code blocks from the content being checked."""
    markdown = re.sub(r"<!--[\s\S]*?-->", "", markdown)
    lines = []
    fence = None
    for line in markdown.splitlines(keepends=True):
        if fence:
            if re.fullmatch(r" {0,3}" + re.escape(fence[0]) + "{" + str(len(fence)) + r",}[ \t]*", line.rstrip("\r\n")):
                fence = None
            continue
        opening = re.match(r"^ {0,3}(`{3,}|~{3,})(.*)$", line.rstrip("\r\n"))
        if opening and not (opening[1][0] == "`" and "`" in opening[2]):
            fence = opening[1]
        elif not re.match(r"^(?: {4}|\t)", line):
            lines.append(line)
    return "".join(lines)


def sections(markdown):
    matches = list(re.finditer(r"^## ([^\n]+)\s*$", markdown, re.MULTILINE))
    return {
        match.group(1).strip(): markdown[match.end():matches[i + 1].start()
                                      if i + 1 < len(matches) else len(markdown)].strip()
        for i, match in enumerate(matches)
    }


def checkboxes(markdown):
    return re.findall(r"^\s*- \[([ xX])\] (.+)$", markdown, re.MULTILINE)


def image_urls(markdown):
    # Inline images and reference images are both common in GitHub PR bodies.
    markdown = re.sub(r"(?<!`)(`+)(?!`)[\s\S]*?(?<!`)\1(?!`)", "", markdown)

    def unescaped(match):
        prefix = markdown[:match.start()]
        return (len(prefix) - len(prefix.rstrip("\\"))) % 2 == 0

    urls = re.finditer(r'!\[[^\]]*\]\(\s*(?:<([^>]+)>|([^\s)]+))(?:\s+"[^"]*")?\s*\)', markdown)
    result = [match[1] or match[2] for match in urls if unescaped(match)]
    refs = {name.strip().lower(): url.strip("<>") for name, url in
            re.findall(r"^\s*\[([^\]]+)\]:\s*(\S+)", markdown, re.MULTILINE)}
    for match in re.finditer(r"!\[([^\]]*)\]\[([^\]]*)\]", markdown):
        if unescaped(match):
            result.append(refs.get((match[2] or match[1]).strip().lower(), ""))
    return result


def github_image_url(url):
    parsed = urlparse(url)
    if parsed.scheme != "https" or not parsed.netloc:
        return False
    if parsed.hostname == "github.com" and "/blob/" in parsed.path:
        return parse_qs(parsed.query).get("raw") == ["true"]
    return True


def validate(title, body, template, ui_changes):
    errors = []
    if not TITLE.fullmatch(title):
        errors.append("Use a Conventional Commits title, e.g. fix(home): retain idle usage history.")
    content = sections(prose(body))
    expected = sections(prose(template))
    for name in expected:
        if name != "UI changes" or ui_changes:
            if not content.get(name):
                errors.append(f"Fill the template's '{name}' section.")
    types = {label for _, label in checkboxes(expected.get("Type of change", ""))}
    if not any(mark.lower() == "x" and any(label.startswith(t) for t in types)
               for mark, label in checkboxes(content.get("Type of change", ""))):
        errors.append("Select the actual Type of change from the template.")
    checklist = [label for _, label in checkboxes(content.get("Checklist", ""))]
    for _, label in checkboxes(expected.get("Checklist", "")):
        if not any(item.startswith(label) for item in checklist):
            errors.append(f"Keep the template checklist item: {label}")
    if ui_changes:
        ui = content.get("UI changes", "")
        # Definitions may be outside UI changes; the image use must be inside it.
        definitions = "\n".join(re.findall(r"^\s*\[[^\]]+\]:.*$", prose(body), re.MULTILINE))
        urls = image_urls(ui + "\n" + definitions)
        if not urls:
            errors.append("UI changes must embed images; text or an attachment excuse is insufficient.")
        elif any(not github_image_url(url) for url in urls):
            errors.append("UI images need HTTPS image URLs that render on GitHub, not local paths or blob pages.")
    return errors


def ui_files_changed(base, head):
    result = subprocess.run(
        ["git", "diff", "--name-only", f"{base}...{head}", "--", "Sources/PokeTokenBar/UI/"],
        cwd=ROOT, capture_output=True, text=True,
    )
    if result.returncode:
        raise ValueError(result.stderr.strip() or "Could not inspect the PR diff.")
    return bool(result.stdout.strip())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--title", required=True)
    parser.add_argument("--body-file", required=True, type=Path)
    parser.add_argument("--base", required=True, help="Chosen PR base ref, e.g. origin/main")
    parser.add_argument("--head", default="HEAD")
    ui_flags = parser.add_mutually_exclusive_group()
    ui_flags.add_argument("--ui-changes", action="store_true", help="Visible changes outside the UI directory")
    ui_flags.add_argument("--no-ui-changes", metavar="REASON", help="Explain reviewed UI-directory edits with no visible effect")
    args = parser.parse_args()
    try:
        changed_ui_files = ui_files_changed(args.base, args.head)
        if args.no_ui_changes is not None and not args.no_ui_changes.strip():
            raise ValueError("--no-ui-changes requires a reason based on the reviewed diff.")
        ui_changes = (changed_ui_files or args.ui_changes) and args.no_ui_changes is None
        errors = validate(args.title, args.body_file.read_text(encoding="utf-8"),
                          (ROOT / ".github/PULL_REQUEST_TEMPLATE.md").read_text(encoding="utf-8"),
                          ui_changes)
    except (OSError, ValueError) as error:
        print(f"PR check failed: {error}", file=sys.stderr)
        return 1
    if errors:
        for error in errors:
            print(f"PR check failed: {error}", file=sys.stderr)
        return 1
    if args.no_ui_changes:
        print(f"Reviewed as no visible UI change: {args.no_ui_changes}")
    print("PR structure check passed. Verify English wording, checked claims, and remote image rendering before publishing.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
