# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
