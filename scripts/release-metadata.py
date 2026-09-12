#!/usr/bin/env python3
"""Validate release notes and format explicitly supplied commit coauthors."""
import re
import sys
from pathlib import Path


def read_file(path, label):
    if not path or not Path(path).is_file():
        raise ValueError(f"{label} file is required: {path or '(not set)'}")
    return Path(path).read_text(encoding="utf-8")


def check_notes(notes_path, contributors_path):
    notes = read_file(notes_path, "PTB_NOTES_FILE")
    # Instructions in the template are not release content.
    visible = re.sub(r"<!--.*?-->", "", notes, flags=re.S)
    sections = {}
    for match in re.finditer(r"^## (New|Fixed|Other|Contributors)\s*$\n(.*?)(?=^## |\Z)", visible, re.M | re.S):
        sections[match[1]] = match[2].split("\n---", 1)[0].strip()
    for name in ("New", "Fixed", "Other", "Contributors"):
        if not sections.get(name):
            raise ValueError(f"Release notes need a nonempty '## {name}' section")
    for command in ("brew install --cask chattymin/tap/poke-token-bar", "brew upgrade --cask poke-token-bar"):
        if command not in visible:
            raise ValueError(f"Release notes are missing: {command}")

    roster = read_file(contributors_path, "PTB_CONTRIBUTORS_FILE")
    expected = set()
    for line in roster.splitlines():
        handle = line.strip().removeprefix("@")
        if not handle:
            continue
        if not re.fullmatch(r"[A-Za-z0-9]+(?:-[A-Za-z0-9]+)*", handle):
            raise ValueError(f"Invalid contributor handle: {line}")
        expected.add(handle.lower())
    def mentions(text):
        return {name.lower() for name, bot in re.findall(
            r"@([A-Za-z0-9]+(?:-[A-Za-z0-9]+)*)(\[bot\])?", text, re.I) if not bot}
    # Also catch a credited contributor accidentally omitted from the final roster.
    expected |= mentions("\n".join(sections[name] for name in ("New", "Fixed", "Other"))) - {"chattymin"}
    actual = mentions(sections["Contributors"])
    missing = expected - actual
    if missing:
        raise ValueError("Missing Contributors: " + ", ".join("@" + name for name in sorted(missing)))
    if not actual and sections["Contributors"] != "No external contributors in this release.":
        raise ValueError("List contributor handles, or explicitly state 'No external contributors in this release.'")


def commit_message(version, coauthors_path=""):
    if not re.fullmatch(r"\d+\.\d+\.\d+", version):
        raise ValueError("Version must be X.Y.Z")
    message = f"release: bump version to {version}"
    if coauthors_path:
        authors = []
        for line in read_file(coauthors_path, "PTB_COAUTHORS_FILE").splitlines():
            author = line.strip()
            if not author:
                continue
            if not re.fullmatch(r"[^<>\r\n]+ <[^<>\s]+@[^<>\s]+>", author):
                raise ValueError("Coauthors must be one 'Name <email>' per line")
            if author not in authors:
                authors.append(author)
        if authors:
            message += "\n\n" + "\n".join("Co-Authored-By: " + author for author in authors)
    return message


if __name__ == "__main__":
    try:
        if len(sys.argv) == 4 and sys.argv[1] == "check-notes":
            check_notes(sys.argv[2], sys.argv[3])
        elif len(sys.argv) in (3, 4) and sys.argv[1] == "commit-message":
            print(commit_message(*sys.argv[2:]))
        else:
            raise ValueError("Use check-notes <notes> <contributors> or commit-message <version> [coauthors]")
    except (ValueError, OSError) as error:
        sys.exit(f"Release metadata: {error}")
