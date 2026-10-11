#!/usr/bin/env bash
# Renovate postUpgradeTasks command: raise versions/<name>.version (patch) for
# every reusable workflow the update has just edited in the working tree.
#
# Why: a Renovate pin bump (e.g. actions/upload-artifact) edits
# .github/workflows/<name>.yml, and check-versions.sh then fails the PR because
# the workflow's version file did not move. This does the bump Renovate cannot.
#
# Runs against an uncommitted tree on top of the base branch, so HEAD holds the
# base version. Idempotent: a version file already modified in the tree is left
# alone, so a re-run never double-bumps.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

git diff --name-only HEAD -- '.github/workflows/*.yml' | while read -r wf; do
  [ -f "${wf}" ] || continue  # deleted workflow
  grep -q '^  workflow_call:' "${wf}" || continue
  name=$(basename "${wf}" .yml)
  vfile="versions/${name}.version"

  if [ ! -f "${vfile}" ]; then
    echo "skip ${wf}: no ${vfile}" >&2
    continue
  fi
  if ! git diff --quiet HEAD -- "${vfile}"; then
    echo "skip ${vfile}: already modified"
    continue
  fi

  old=$(tr -d '[:space:]' < "${vfile}")
  new=$(printf '%s\n' "${old}" | awk -F. 'NF==3 {print $1"."$2"."$3+1; next} {exit 1}') || {
    echo "::error file=${vfile}::cannot parse '${old}' as MAJOR.MINOR.PATCH" >&2
    exit 1
  }
  printf '%s\n' "${new}" > "${vfile}"
  echo "bumped ${vfile}: ${old} -> ${new}"
done
