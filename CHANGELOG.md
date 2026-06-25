# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.0.49] - 2026-06-25

### Added

- `gitlab/tox-pipeline.yml`: the generated child pipeline now writes `/etc/pip.conf` from `PIP_INDEX_URL` / `PIP_EXTRA_INDEX_URL` / `PIP_TRUSTED_HOST` before running tox, so pip (including inside tox-created venvs, where env passthrough is unreliable) resolves through a configured index — the Nexus pull-through cache. **With automatic fallback:** pip has no native index failover, so the job TCP-probes `PIP_INDEX_URL` at start — if Nexus is reachable it's used (with pypi as extra-index for fresh releases), and if not, pip.conf points at `PIP_EXTRA_INDEX_URL` (pypi.org) instead, so a Nexus outage degrades CI to "no cache", never "no installs". The probe uses only `python3` (no `curl` dependency). **No-op until `PIP_INDEX_URL` is set**, so this is inert for every consumer until the Nexus CI cutover flips that variable. Applies to both the tox matrix job and the diff-cover job, in both the slim-image and `TOX_BASE_IMAGE` paths.

## [0.0.47] - 2026-06-01

### Added

- `gitlab/spellcheck.yml`: new reusable template exposing `.spellcheck` for running pyspelling against a project's spellcheck config. Inputs: `SPELLCHECK_NAME` (default `Markdown`; consumers using HTML sites override to `html`), `SPELLCHECK_CONFIG` (default `.spellcheck/spellcheck.yml`). Consolidates the inline pyspelling jobs across four in-tree consumers (`dappertable`, `enheduanna`, `eastbay`, `personal-website`).

## [0.0.46] - 2026-06-01

### Added

- `gitlab/tox-pipeline.yml`: new reusable templates exposing `.tox-generate` and `.tox-pipeline` for Python tox matrix testing plus a diff-cover coverage gate. GitLab CI doesn't accept YAML lists as job variables, so `.tox-generate` introspects `tox -l` and writes a child pipeline YAML that `.tox-pipeline` then triggers via `include: artifact:`. Inputs on `.tox-generate`: `TOX_EXTRA_APT` (appended after the default `git` so per-repo extras like discord-bot's `sqlite3 ffmpeg` don't lose `git`), `DIFF_COVER_FAIL_UNDER` (default 100), `DIFF_COVER_COMPARE_BRANCH` (default `origin/main`). The generated child pipeline always pins images as `docker.io/library/python:<X.Y>-slim` so the template works on runtimes that enforce CRI-O `short-name-mode = "enforcing"`. Consolidates the ~70-line copy-pasted heredoc generator across seven in-tree Python repos (`dappertable`, `backup-tool`, `enheduanna`, `hathor`, `public-transit`, `vault-app`, `oke-security-scanner`) plus discord-bot's older hand-rolled matrix.

## [0.0.45] - 2026-06-01

### Added

- `gitlab/buildkit-build-check.yml`: new reusable template exposing `.buildkit-build-check` for MR-time "does the Dockerfile compile" validation. Builds a local image with buildkit (out-of-cluster, no dind) and emits a `docker save` tarball as an artifact so downstream MR jobs (e.g. `.trufflehog-image`) can scan without rebuilding. Same buildkit-via-cluster-service transport as `.buildkit-docker-push` (0.0.44). Inputs: `BUILDKIT_IMAGE` (centralizes the `v0.29.0`/`v0.30.0` drift that had crept into individual repos), `CONTEXT_DIR` / `DOCKERFILE_DIR` / `DOCKERFILE_NAME` / `BUILD_ARGS` / `OUTPUT_NAME` / `OUTPUT_TARBALL`. Default `rules:` runs on every MR with fork-MRs requiring a maintainer to manually trigger. Consolidates the `build-check` / `docker-build` / `validate-docker` jobs that were copy-pasted across eight in-tree consumers.

## [0.0.44] - 2026-06-01

### Added

- `gitlab/buildkit-docker-push.yml`: new reusable template exposing `.buildkit-docker-push` for building OCI images with buildkit (out-of-cluster via `buildctl --addr`, no dind) and pushing `:SHA` and `:latest` tags to OCIR. Emits `IMAGE=<full ref>` to a dotenv artifact so downstream jobs (e.g. `.trigger-bump`) can pick up the reference without re-decoding the `OCI_*_64` CI variables. Same auth mechanism as the removed `.docker-push` (base64-encoded `OCI_USERNAME_64`/`OCI_TOKEN_64`/`OCI_REGISTRY_64`/`OCI_NAMESPACE_64`/`OCI_REPO_NAME_64`). Supports multi-image consumers by overriding `OCI_REPO_NAME_64` per job, plus `DOCKERFILE_NAME` / `DOCKERFILE_DIR` / `CONTEXT_DIR` / `BUILD_ARGS` / `PLATFORM` for build customization. Consolidates the inline buildkit jobs that were copy-pasted across all six in-tree producer repos.

### Removed

- `gitlab/docker-push.yml` (`.docker-push`): removed. The dind-based template had zero in-tree consumers — every producer was running its own inline buildkit-via-cluster-service job that `.buildkit-docker-push` now consolidates. **Breaking** for any external consumer still extending `.docker-push`; migrate to `.buildkit-docker-push` (which expects an out-of-cluster `buildkitd` Deployment rather than dind).

## [0.0.43] - 2026-05-12

### Added

- `gitlab/trigger-bump.yml`: new reusable template exposing `.trigger-bump` for the *producer* side of the cross-project bump-pin flow. Fires `POST /projects/:id/trigger/pipeline` on a downstream repo (e.g. docker-apps) with `BUMP_SOURCE` / `IMAGE_NAME` / `IMAGE_TAG` as `variables[...]` so the downstream pipeline can rewrite the image pin and open an MR. Defaults `TARGET_PROJECT_ID` / `TARGET_TRIGGER_TOKEN` to `$DOCKER_APPS_PROJECT_ID` / `$DOCKER_APPS_TRIGGER_TOKEN` (the names terraform already provisions), so consumers usually only need to set `BUMP_SOURCE` and wire `needs:` to their `docker-push` job (which must emit `IMAGE` to a dotenv artifact). `allow_failure: true` by default — the image is already pushed by the time the trigger fires, so a downstream automation hiccup shouldn't fail the producer pipeline.

## [0.0.42] - 2026-05-10

### Changed

- `gitlab/release.yml`: dropped the `registry.gitlab.com/gitlab-org/release-cli:v0.24.0` image and now runs on `docker.io/library/alpine:3` with `curl` and `jq` installed in `before_script`. Calls the Releases API directly (`POST /projects/:id/releases`) authenticated with `CI_JOB_TOKEN`. Self-hosted runners that hadn't preheated the release-cli image were hitting `prepare environment: timed out waiting for pod to start` because the registry.gitlab.com pull exceeded the runner's `poll_timeout`; the alpine image is small enough to pull within the default and is already cached on most runners. Behaviour is otherwise unchanged: same CHANGELOG-section extraction, same fallback description, same idempotency on `TAG_CREATED`.

## [0.0.41] - 2026-05-10

### Added

- `gitlab/bump-version.yml`: new optional `BUMP_CHANGELOG` variable. When set to `"true"`, the template also prepends a new `## [X.Y.Z] - YYYY-MM-DD` section to `CHANGELOG_FILE` (default `CHANGELOG.md`) and stages it as part of the bump commit. Entry text is parsed from the MR title when it matches renovate's `<type>(deps): update dependency <name> to <version>` pattern (e.g. `Bumped tox to v4.53.1`); otherwise the MR title is used verbatim. Idempotent — if a section for the new version already exists, the changelog is left untouched.

## [0.0.40] - 2026-05-10

### Added

- `gitlab/release.yml`: new reusable template that creates a GitLab Release matching the tag pushed by `gitlab/tag.yml`. Reads `VERSION` and `TAG_CREATED` from `.tag`'s dotenv artifact via `needs: artifacts: true`, so it no-ops when the tag already existed instead of creating a duplicate release. Pulls the `## [X.Y.Z]` section out of `CHANGELOG.md` (Keep-a-Changelog format) for the release description; falls back to `"Release <version>"` when no matching section is found. `CHANGELOG_FILE` is configurable. Image pinned to `registry.gitlab.com/gitlab-org/release-cli:v0.24.0`.

## [0.0.39] - 2026-05-09

### Changed

- `gitlab/bump-version.yml`: template now sets `stage: .pre` so the bump runs before any consumer-defined stages (validate, test, build, ...). Previously the job inherited GitLab's default `test` stage and consumers' `validate` jobs ran first, burning CI time on a SHA that was about to be superseded by the bump push. Consumers that previously set an explicit `stage:` override on their `bump-version` job can now drop it.
- `gitlab/discord-notify.yml`: webhook failures are now non-fatal — the script logs the error to stderr and exits 0 instead of failing the job. Adds a 10s `urlopen` timeout and catches `URLError` (DNS/network) and unexpected exceptions in addition to `HTTPError`. Notifications are advisory; a Discord outage or webhook misconfiguration should not break the pipeline.

## [0.0.38] - 2026-05-06

### Changed

- `gitlab/bump-version.yml`: when `GITLAB_PUSH_TOKEN` is set, the auth URL now uses `oauth2:<token>` as the basic-auth pair instead of the literal `deploy-token:<token>`. `oauth2:` is the canonical username for personal access tokens, project access tokens, and deploy tokens — the previous form only authenticated correctly for deploy tokens whose username happened to be literally `deploy-token`. The fallback to `gitlab-ci-token:$CI_JOB_TOKEN` is unchanged, but now emits a stderr warning since `CI_JOB_TOKEN`-authored pushes don't trigger a follow-up pipeline (GitLab's infinite-loop guard) and leave the MR widget reporting `ci_must_pass` on the bump commit, while a PAT-authored push triggers a fresh pipeline and keeps the widget green. Doc header and README rewritten to call out the trade-off and recommend `GITLAB_PUSH_TOKEN`.

### Added

- `gitlab/renovate.yml`: new optional `GITHUB_COM_TOKEN` pass-through. When set as a CI variable (any GitHub PAT — no scopes needed beyond public-repo reads), Renovate uses it to fetch release notes from github.com for dependencies whose source/changelog lives there. Without it, MR bodies show "Release Notes retrieval for this MR were skipped because no github.com credentials were available." See [renovate self-hosting docs](https://github.com/renovatebot/renovate/blob/main/docs/usage/examples/self-hosting.md#githubcom-token-for-release-notes).

## [0.0.37] - 2026-05-05

### Changed

- `gitlab/docker-push.yml`: now reads OCI registry credentials from base64-encoded variables (`OCI_USERNAME_64`, `OCI_TOKEN_64`, `OCI_REGISTRY_64`, `OCI_NAMESPACE_64`, `OCI_REPO_NAME_64`) and decodes them in `before_script`. GitLab's masking length requirement rejects short values (e.g. namespace, repo name) when stored as plaintext; base64-encoding lets all of them be stored as masked CI variables. **Breaking** for consumers — rename the CI variables in **Settings → CI/CD → Variables** and store the base64-encoded values (e.g. `printf '%s' "$value" | base64`).

## [0.0.36] - 2026-05-04

### Changed

- `gitlab/trufflehog-image.yml`: dropped the in-job `docker build` / `docker save` flow and the `docker:27-dind` service. The template now requires `TRUFFLEHOG_IMAGE_TARBALL` to point at a `docker save` tarball produced by an upstream build job (wired up via `needs:`), and runs on `docker.io/library/alpine:3` with no Docker daemon. TruffleHog reads the OCI tarball directly via `file://`. Removes the dind memory baseline and ~10s daemon startup from the scan job. **Breaking** for consumers that relied on the self-contained build-and-scan behaviour — they now need an upstream job that publishes the tarball as an artifact. Removed variables: `DOCKERFILE_PATH`, `DOCKER_CONTEXT`, `DOCKER_BUILD_ARGS`.
- `gitlab/trufflehog-image.yml`: default `TRUFFLEHOG_EXTRA_ARGS` now includes `--concurrency=2`. TruffleHog otherwise spawns one scan worker per `runtime.NumCPU()`, which on unbounded CI pods drives memory peaks of 1–2 GiB on larger images. Capping at 2 keeps memory predictable at the cost of ~20–30% scan time; raise it via override when you have headroom.

## [0.0.35] - 2026-05-03

### Added

- `gitlab/bump-version.yml`: now supports JSON version files (e.g. `package.json`) via `VERSION_FILE_TYPE: 'json'` and `VERSION_JSON_KEY` (default `version`), matching the surface area `gitlab/tag.yml` already exposed. JSON files are rewritten with `jq --indent 2`, preserving key order. The default behaviour is unchanged: `VERSION_FILE_TYPE` defaults to `plain` and consumers using a plain-text `VERSION` file need no changes. Adds `jq` to the alpine `apk add` line.

## [0.0.34] - 2026-05-03

### Added

- `gitlab/trufflehog-image.yml`: new optional `TRUFFLEHOG_IMAGE_TARBALL` variable. When set, the template skips the local `docker build` / `docker save` step and scans the supplied tarball directly. Lets a consumer chain off an upstream build job (e.g. `gitlab/docker-push.yml`) via `needs: [<build-job>]` and an artifact, instead of rebuilding the image just to scan it.

## [0.0.33] - 2026-05-03

### Changed

- All template image references are now fully qualified with `docker.io/...` so they work on runtimes that enforce CRI-O's `short-name-mode = "enforcing"` (e.g. Oracle Linux nodes on OKE). Containerd and Docker auto-resolve short names so this is invisible there. Affects:
  - `gitlab/trufflehog.yml`: `trufflesecurity/trufflehog:latest` → `docker.io/trufflesecurity/trufflehog:latest`
  - `gitlab/renovate.yml`: `renovate/renovate:43` → `docker.io/renovate/renovate:43`
  - `gitlab/bump-version.yml`: `alpine:3` → `docker.io/library/alpine:3`
  - `gitlab/discord-notify.yml`: `python:3.14-slim` → `docker.io/library/python:3.14-slim`
  - `gitlab/docker-push.yml`: `docker:27` (image) and `docker:27-dind` (service) → `docker.io/library/docker:27` and `docker.io/library/docker:27-dind`
  - `gitlab/trufflehog-image.yml`: same as docker-push.yml

### Fixed

- `gitlab/tag.yml`: explicitly declares `image: docker.io/library/alpine:3` and a `before_script` that installs `git` and `jq`. Previously the template inherited whatever image the consumer or runner default supplied — fine on shared runners with a fat default that includes `git`, but the script's `git` and `jq` (used on the `VERSION_FILE_TYPE=json` branch) would fail with `command not found` on a minimal alpine runner default.

## [0.0.32] - 2026-05-01

### Fixed

- `gitlab/trufflehog-image.yml`: scanning failed with `UNAUTHORIZED: authentication required` against `index.docker.io` because `trufflehog docker --image <tag>` resolves references through a registry rather than the local Docker daemon, so a bare local tag got normalized to `docker.io/library/<tag>` and pulled. The template now `docker save`s the built image to a tarball and passes `--image "file://$SCAN_TARBALL"`, scanning the local image without any registry round-trip.

## [0.0.31] - 2026-05-01

### Added

- `gitlab/trufflehog.yml`: new reusable GitLab CI template for scanning the repo with [TruffleHog](https://github.com/trufflesecurity/trufflehog). On MR pipelines, scans only commits added in the MR via `--since-commit $CI_MERGE_REQUEST_DIFF_BASE_SHA`; on default-branch / scheduled / manual pipelines, scans the full git history. Defaults to `--only-verified --fail` so the job fails only on credentials TruffleHog validates against the issuing API. Configurable via `TRUFFLEHOG_EXTRA_ARGS`, `TRUFFLEHOG_EXCLUDE_PATHS` (regex file), and `TRUFFLEHOG_FULL_HISTORY`.
- `gitlab/trufflehog-image.yml`: companion template that builds the repo's Dockerfile inside Docker-in-Docker and scans the resulting image with TruffleHog's `docker` mode. Catches secrets baked into image layers (e.g. via a leaky `RUN` command or copied-then-deleted file) that source-level scanning misses. Self-contained — no registry pull or chaining with `gitlab/docker-push.yml` required. Configurable via `DOCKERFILE_PATH`, `DOCKER_CONTEXT`, `DOCKER_BUILD_ARGS`, `TRUFFLEHOG_VERSION`, and `TRUFFLEHOG_EXTRA_ARGS`.

### Changed

- `.gitlab-ci.yml`: this repo now runs `gitlab/trufflehog.yml` on MR pipelines as a `validate`-stage job, dogfooding the new template. Fork MRs require manual trigger, matching the existing `pre-commit` and `notify-mr` jobs.

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
