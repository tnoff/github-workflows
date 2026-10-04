#!/usr/bin/env bash
# PR check: every reusable workflow has a versions/<name>.version file, and a
# workflow changed against the base branch also has its version raised.
#
# Usage: check-versions.sh <base-ref>     (e.g. origin/main)
set -euo pipefail

BASE="${1:?usage: check-versions.sh <base-ref>}"
status=0

for wf in .github/workflows/*.yml; do
  grep -q '^  workflow_call:' "${wf}" || continue
  name=$(basename "${wf}" .yml)
  vfile="versions/${name}.version"

  if [ ! -f "${vfile}" ]; then
    echo "::error file=${wf}::missing ${vfile} (new reusable workflows start at 1.0.0)"
    status=1
    continue
  fi

  # Unchanged workflow: nothing to bump.
  if git diff --quiet "${BASE}...HEAD" -- "${wf}"; then
    continue
  fi

  new=$(tr -d '[:space:]' < "${vfile}")
  if ! old=$(git show "${BASE}:${vfile}" 2>/dev/null | tr -d '[:space:]'); then
    continue  # version file is new in this PR, so is the workflow
  fi
  if [ "${new}" = "${old}" ] || [ "$(printf '%s\n%s\n' "${old}" "${new}" | sort -V | tail -1)" != "${new}" ]; then
    echo "::error file=${vfile}::${wf} changed but ${vfile} is still ${old}; raise it (patch/minor/major)"
    status=1
  fi
done
exit "${status}"
