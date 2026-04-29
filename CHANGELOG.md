# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.0.26] - 2026-04-29

### Added

- `gitlab/tag.yml`: new GitLab CI template equivalent of `tag.yml`. Reads a version file (plain text or JSON), checks if the tag already exists, and pushes it if not. Configuration is passed via CI variables (`VERSION_FILE`, `VERSION_FILE_TYPE`, `VERSION_JSON_KEY`). Outputs (`VERSION`, `TAG_CREATED`, `TAG_EXISTS`) are exposed via a `dotenv` artifact for downstream jobs.

## [0.0.25] - 2026-04-24

### Changed

- `coverage-check.yml`: overall coverage drop no longer fails the job — it now posts a warning comment on the PR instead, so teams that delete code aren't blocked by a coverage regression that diff-cover shows is 100% on changed lines.
- `coverage-check.yml`: `fail_on_diff_cover` default changed from `false` to `true` — diff-cover (new/changed line coverage) is now the primary hard gate.
- `coverage-check.yml`: added `pull-requests: write` permission so the warning comment can be posted.
- `coverage-check.yml`: step summary coverage drop status updated from ❌ Failed to ⚠️ Warning to reflect the non-blocking behaviour.

## [0.0.24] - 2026-04-23

### Added

- `dependabot-auto-approve.yml`: new `dependency_groups` input — a comma-separated list of dependabot group names that must match the `dependency-group` reported by `dependabot/fetch-metadata` for the PR to be eligible. Useful for filtering updates by section in files like `pyproject.toml` (e.g. `prod-deps` vs `dev-deps`) without having to enumerate every package in `accept_packages`. If empty, no group filter is applied.

## [0.0.23] - 2026-04-23

### Added

- `bump-version.yml`: new `paths` input — a JSON array of glob patterns that gates the version bump on whether any changed files match. Empty array (default) preserves the existing always-run behaviour. Implemented as a lightweight `check` job that runs `git diff --name-only` against the base branch and matches files using bash `case` glob syntax.

## [0.0.22] - 2026-04-23

### Added

- `bump-version.yml`: new reusable workflow that bumps the version file on a PR branch (major/minor/patch, default patch) and commits the result back onto the PR. Idempotent — skips if the version file was already changed relative to the base branch, preventing re-trigger loops.

## [0.0.21] - 2026-04-22

### Added

- `ocir-push.yml`: new optional `build_args` input (newline-separated `KEY=VALUE` pairs) passed through to `docker/build-push-action`'s `build-args` parameter.

## [0.0.20] - prior

### Fixed

- Address git hash bug (#24)

### Added

- Add flag to fail on diff cover (#23)

### Changed

- Bump `docker/build-push-action` from 7.0.0 to 7.1.0 (#26)
- Bump `actions/upload-artifact` from 7.0.0 to 7.0.1 (#27)
- Bump `docker/login-action` from 4.0.0 to 4.1.0 (#25)
