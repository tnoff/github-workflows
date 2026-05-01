# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.0.31] - 2026-05-01

### Added

- `gitlab/trufflehog.yml`: new reusable GitLab CI template for scanning the repo with [TruffleHog](https://github.com/trufflesecurity/trufflehog). On MR pipelines, scans only commits added in the MR via `--since-commit $CI_MERGE_REQUEST_DIFF_BASE_SHA`; on default-branch / scheduled / manual pipelines, scans the full git history. Defaults to `--only-verified --fail` so the job fails only on credentials TruffleHog validates against the issuing API. Configurable via `TRUFFLEHOG_EXTRA_ARGS`, `TRUFFLEHOG_EXCLUDE_PATHS` (regex file), and `TRUFFLEHOG_FULL_HISTORY`.
- `gitlab/trufflehog-image.yml`: companion template that builds the repo's Dockerfile inside Docker-in-Docker and scans the resulting image with TruffleHog's `docker` mode. Catches secrets baked into image layers (e.g. via a leaky `RUN` command or copied-then-deleted file) that source-level scanning misses. Self-contained — no registry pull or chaining with `gitlab/docker-push.yml` required. Configurable via `DOCKERFILE_PATH`, `DOCKER_CONTEXT`, `DOCKER_BUILD_ARGS`, `TRUFFLEHOG_VERSION`, and `TRUFFLEHOG_EXTRA_ARGS`.

## [0.0.30] - 2026-04-30

### Added

- `gitlab/docker-push.yml`: new reusable GitLab CI template for building and pushing a multi-arch Docker image. Logs in to an OCI registry, installs QEMU binfmt handlers via `tonistiigi/binfmt`, builds with `--platform` (default `linux/arm64`), and pushes two tags: the short commit SHA and `latest`. Registry credentials and image coordinates are passed via `OCI_REGISTRY`, `OCI_NAMESPACE`, `OCI_REPO_NAME`, `OCI_USERNAME`, and `OCI_TOKEN` CI variables. Platform is overridable via the `DOCKER_PLATFORM` variable.

### Changed

- `.gitlab-ci.yml`: `pre-commit` no longer runs on push to the default branch (merge). Validation only runs on MR pipelines; tag and notify jobs remain on merge.

## [0.0.29] - 2026-04-29

### Added

- `gitlab/bump-version.yml`: new reusable GitLab CI template for auto-bumping the patch version on a branch. Compares the `VERSION` file against the default branch and increments the patch version if it hasn't been bumped yet. Idempotent — exits cleanly if already bumped, preventing push loops. Uses `alpine:3` with `apk add git`. Supports `GITLAB_PUSH_TOKEN` with fallback to `CI_JOB_TOKEN`.

## [0.0.28] - 2026-04-29

### Added

- `gitlab/renovate.yml`: new reusable GitLab CI template for running Renovate. Runs against the current project using `RENOVATE_TOKEN` (GitLab PAT with `api` scope). Intended for scheduled pipelines — wire up via `Settings → CI/CD → Schedules` in GitLab.
- `renovate.json`: Renovate config for this repo. Enables `pre-commit` and `docker` managers to keep pre-commit hook revs and Docker image tags up to date. GitHub Actions manager intentionally excluded pending GitLab migration.

### Fixed

- `gitlab/discord-notify.yml`: requests were blocked by Cloudflare on GitLab shared runners (error code 1010) due to Python's default `Python-urllib` User-Agent. Fixed by sending `DiscordBot (github-workflows, 1.0)` as the User-Agent, which Cloudflare whitelists.
- `gitlab/discord-notify.yml`: webhook URL is now stripped of whitespace before use, preventing 403s caused by trailing newlines in GitLab CI variable values.
- `gitlab/discord-notify.yml`: Discord API response body is now printed on error, making failures easier to diagnose.
- `.gitlab-ci.yml`: notify jobs now use `needs: []` and `when: always` so they run immediately and independently of the validate/tag stages.

## [0.0.27] - 2026-04-29

### Added

- `gitlab/discord-notify.yml`: new GitLab CI template for Discord notifications. Supports four notification types (`failure`, `success`, `mr_opened`, `mr_merged`) with auto-detected MR context (title, branch arrow, MR URL). The target channel is controlled via `DISCORD_WEBHOOK_URL`, overridable per job to route different event types to different channels.
- `.gitlab-ci.yml`: this repo now has its own GitLab CI pipeline. Runs `pre-commit` on MRs and the default branch, creates a git tag on push to main via `gitlab/tag.yml`, and sends Discord notifications to `$DISCORD_MR_WEBHOOK` on MR pipelines and pushes to main.
- `.pre-commit-config.yaml`: added `check-jsonschema` hook (`check-gitlab-ci`) to validate `.gitlab-ci.yml` against the official GitLab CI JSON schema on every commit.

### Fixed

- `gitlab/tag.yml`: git push would fail silently without credentials configured. The script now sets the remote URL to authenticate via `CI_JOB_TOKEN` by default, or `GITLAB_PUSH_TOKEN` if set, before pushing the tag. Also adds `git config user.email/name` required by some runners.

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
