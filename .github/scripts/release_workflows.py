#!/usr/bin/env python3
"""Cut an independent release for each reusable workflow that changed.

Every reusable workflow (a .github/workflows/<name>.yml with an `on.workflow_call`
trigger) is versioned on its own and tagged `<name>-vMAJOR.MINOR.PATCH`. A
workflow is released when at least one commit since its latest tag touched its
file. The bump level comes from those commits:

  * `type!:` in the subject, or a `BREAKING CHANGE:` footer -> major
  * `feat` / `feat(scope)`                                  -> minor
  * anything else (fix, chore(deps), non-conventional)      -> patch

Anything that touches the file at least patch-bumps it, on purpose: a pin
update inside a workflow changes what consumers run.

Workflows with no tag yet are skipped unless --bootstrap is given, which tags
them all at HEAD as <name>-v1.0.0. That is the one-time migration from the old
repo-wide v0.0.N tags.

Needs git (full history + tags) and, unless --dry-run, an authenticated `gh`.
"""

import argparse
import re
import subprocess
import sys
from pathlib import Path

WORKFLOW_DIR = Path('.github/workflows')
BOOTSTRAP_VERSION = (1, 0, 0)
BREAKING_SUBJECT = re.compile(r'^\w+(\([^)]*\))?!:')
BREAKING_FOOTER = re.compile(r'^BREAKING[ -]CHANGE:', re.MULTILINE)
FEAT_SUBJECT = re.compile(r'^feat(\([^)]*\))?:')


def git(*args):
    return subprocess.run(['git', *args], check=True, capture_output=True, text=True).stdout


def library_workflows():
    """Names of workflows that expose workflow_call; `self-*` callers never do."""
    names = []
    for path in sorted(WORKFLOW_DIR.glob('*.yml')):
        if re.search(r'^  workflow_call:', path.read_text(), re.MULTILINE):
            names.append(path.stem)
    return names


def latest_version(name):
    pattern = re.compile(rf'^{re.escape(name)}-v(\d+)\.(\d+)\.(\d+)$')
    versions = []
    for tag in git('tag', '--list', f'{name}-v*').split():
        match = pattern.match(tag)
        if match:
            versions.append(tuple(int(part) for part in match.groups()))
    return max(versions) if versions else None


def commits_since(name, version):
    """(sha, subject, body) for commits touching the workflow since its tag."""
    tag = f'{name}-v{".".join(map(str, version))}'
    out = git('log', '--format=%H%x1f%s%x1f%b%x1e', f'{tag}..HEAD', '--',
              str(WORKFLOW_DIR / f'{name}.yml'))
    commits = []
    for record in out.split('\x1e'):
        record = record.lstrip('\n')
        if record:
            sha, subject, body = record.split('\x1f', 2)
            commits.append((sha, subject, body))
    return commits


def bump(version, commits):
    major, minor, patch = version
    if any(BREAKING_SUBJECT.match(s) or BREAKING_FOOTER.search(b) for _, s, b in commits):
        return (major + 1, 0, 0)
    if any(FEAT_SUBJECT.match(s) for _, s, _ in commits):
        return (major, minor + 1, 0)
    return (major, minor, patch + 1)


def fmt(version):
    return '.'.join(map(str, version))


def publish(tag, notes, dry_run):
    if dry_run:
        print(f'  [dry-run] would tag and release {tag}')
        return
    git('tag', tag)
    git('push', 'origin', tag)
    subprocess.run(['gh', 'release', 'create', tag, '--verify-tag', '--title', tag,
                    '--notes', notes], check=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    parser.add_argument('--dry-run', action='store_true', help='print what would be released')
    parser.add_argument('--bootstrap', action='store_true',
                        help='tag every workflow that has no tag yet as <name>-v1.0.0 at HEAD')
    args = parser.parse_args()

    released = 0
    for name in library_workflows():
        version = latest_version(name)
        if version is None:
            if not args.bootstrap:
                print(f'{name}: no tag yet, skipping (run with --bootstrap once)')
                continue
            tag = f'{name}-v{fmt(BOOTSTRAP_VERSION)}'
            print(f'{name}: bootstrapping {tag}')
            publish(tag, f'Initial per-workflow release of `{name}.yml`.', args.dry_run)
            released += 1
            continue

        commits = commits_since(name, version)
        if not commits:
            print(f'{name}: unchanged since {name}-v{fmt(version)}')
            continue
        new_version = bump(version, commits)
        tag = f'{name}-v{fmt(new_version)}'
        print(f'{name}: {fmt(version)} -> {fmt(new_version)} ({len(commits)} commit(s))')
        notes = '\n'.join(f'- {subject} ({sha[:7]})' for sha, subject, _ in commits)
        publish(tag, notes, args.dry_run)
        released += 1

    print(f'{released} release(s){" (dry run)" if args.dry_run else ""}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
