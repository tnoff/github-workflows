# GitHub Workflows

Reusable GitHub Actions workflows for standardizing CI/CD across all application repositories. GitLab CI equivalents are available under [`gitlab/`](./gitlab/) as part of an ongoing migration path.

> **For Contributors:** See [DEVELOPMENT.md](./DEVELOPMENT.md) for local workflow validation and development setup.

## Table of Contents

**GitHub Actions (`/.github/workflows/`)**

- [ocir-push.yml](#ocir-pushyml) — Build and push Docker images to OCIR
- [tag.yml](#tagyml) — Auto-create Git tags from a version file
- [bump-version.yml](#bump-versionyml) — Bump the version file on a PR branch
- [check-pr-labels.yml](#check-pr-labelsyml) — Validate PR labels and merge conditions
- [dependabot-auto-approve.yml](#dependabot-auto-approveyml) — Auto-approve Dependabot PRs
- [discord-notify.yml](#discord-notifyyml) — Send failure notifications to Discord
- [coverage-store.yml](#coverage-storeyml) — Store pytest coverage baseline artifact
- [coverage-check.yml](#coverage-checkyml) — Compare PR coverage against baseline
- [check-action-pins.yml](#check-action-pinsyml) — Enforce SHA-pinned action refs
- [Self-Hosted Runners](#self-hosted-runners)

**GitLab CI (`/gitlab/`)**

- [gitlab/tag.yml](#gitlabtagyml) — Auto-create Git tags from a version file
- [gitlab/release.yml](#gitlabreleaseyml) — Create a GitLab Release for a tag with notes pulled from `CHANGELOG.md`
- [gitlab/discord-notify.yml](#gitlabdiscord-notifyyml) — Send Discord notifications for MR and pipeline events
- [gitlab/renovate.yml](#gitlabrenovateyml) — Run Renovate dependency updates on a schedule
- [gitlab/bump-version.yml](#gitlabbump-versionyml) — Auto-bump patch version on a branch
- [gitlab/docker-push.yml](#gitlabdocker-pushyml) — Build and push a multi-arch Docker image
- [gitlab/trufflehog.yml](#gitlabtrufflehogyml) — Scan the repo for leaked secrets with TruffleHog
- [gitlab/trufflehog-image.yml](#gitlabtrufflehog-imageyml) — Scan a built Docker image for leaked secrets with TruffleHog

## Available Workflows

### `ocir-push.yml`

Builds and pushes Docker images to OCI Container Registry (OCIR) with version tagging from a VERSION file and the git hash.

```yaml
# In your app repository: .github/workflows/ci.yml
name: CI/CD

on:
  push:
    branches: [main]

jobs:
  build-and-push:
    uses: tnoff/github-workflows/.github/workflows/ocir-push.yml@v1
    with:
      image_name: my-app
      platforms: linux/amd64,linux/arm64
    secrets:
      oci_registry: ${{ secrets.OCI_REGISTRY }}
      oci_username: ${{ secrets.OCI_USERNAME }}
      oci_token: ${{ secrets.OCI_TOKEN }}
      oci_namespace: ${{ secrets.OCI_NAMESPACE }}
```

**Inputs:**

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `image_name` | ✅ | - | Name of the Docker image |
| `dockerfile_path` | ❌ | `./Dockerfile` | Path to Dockerfile |
| `docker_context` | ❌ | `.` | Docker build context |
| `platforms` | ❌ | `linux/amd64,linux/arm64` | Platforms to build |
| `version_file` | ❌ | `./VERSION` | Path to VERSION file |
| `tag_version` | ❌ | `false` | Tag image with version from VERSION file and `latest` (default: only commit SHA) |
| `runner_labels` | ❌ | `["ubuntu-24.04"]` | Runner labels as JSON array |
| `allow_fork_prs` | ❌ | `true` | Allow fork PRs to run (set `false` for self-hosted runners) |
| `build_args` | ❌ | `''` | Docker build arguments (newline-separated `KEY=VALUE` pairs) |

**Secrets:**

| Secret | Required | Description |
|--------|----------|-------------|
| `oci_registry` | ✅ | OCI Registry URL (e.g., `iad.ocir.io`) |
| `oci_username` | ✅ | OCI Username |
| `oci_token` | ✅ | OCI Auth Token |
| `oci_namespace` | ✅ | OCIR Namespace |

**Outputs:**

| Output | Description |
|--------|-------------|
| `version` | Version read from VERSION file |
| `image_tags` | Comma-separated list of tag names (e.g., `0.0.4,abc1234,latest`) |

**Permissions:**

No special permissions required. The workflow uses `contents: read` internally to checkout code and read the VERSION file.


### `tag.yml`

Automatically creates Git tags based on a version file. Checks if the tag already exists before creating it, preventing duplicate tag errors. Supports plain text version files (e.g. `VERSION`) and JSON files (e.g. `package.json`).

```yaml
jobs:
  create-tag:
    uses: tnoff/github-workflows/.github/workflows/tag.yml@v1
    with:
      version_file: ./VERSION
```

For a JSON file like `package.json`:

```yaml
jobs:
  create-tag:
    uses: tnoff/github-workflows/.github/workflows/tag.yml@v1
    with:
      version_file: ./package.json
      version_file_type: json
      version_json_key: version
```

**Inputs:**

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `version_file` | ❌ | `./VERSION` | Path to version file |
| `version_file_type` | ❌ | `plain` | File type: `plain` (raw text) or `json` |
| `version_json_key` | ❌ | `version` | Key to extract when `version_file_type` is `json` |
| `runner_labels` | ❌ | `["ubuntu-24.04"]` | Runner labels as JSON array |
| `allow_fork_prs` | ❌ | `true` | Allow fork PRs to run (set `false` for self-hosted runners) |

**Outputs:**

| Output | Description |
|--------|-------------|
| `version` | Version from file with `v` prefix (e.g., `v0.0.4`) |
| `tag_created` | `true` if a new tag was created, `false` if skipped |
| `tag_exists` | `true` if tag already existed, `false` if new |

**Permissions:**

The calling workflow must grant `contents: write` permission to create Git tags:

```yaml
jobs:
  create-tag:
    permissions:
      contents: write
    uses: tnoff/github-workflows/.github/workflows/tag.yml@v1
```

### `bump-version.yml`

Bumps the version file on a PR branch by committing the new version directly onto the PR. Designed to be paired with `dependabot-auto-approve.yml` so that dependency updates automatically trigger a version increment before the PR is merged. Once the PR lands on `main`, the existing `auto-tag.yml` + `tag.yml` chain creates the release tag.

The workflow is idempotent: if the version file already differs from the base branch anywhere in the PR, it skips — this is both the loop guard and a "already done" check.

> **Note:** This workflow cannot run on fork PRs because it needs to push a commit back to the PR branch. `allow_fork_prs` defaults to `false`.

```yaml
# In your app repository: .github/workflows/dependabot.yml
name: Dependabot

on:
  pull_request:
    types: [opened, synchronize, reopened]

jobs:
  auto-approve:
    uses: tnoff/github-workflows/.github/workflows/dependabot-auto-approve.yml@v1
    with:
      allowed_update_types: 'minor,patch'

  bump-version:
    needs: auto-approve
    if: needs.auto-approve.outputs.approved == 'true'
    uses: tnoff/github-workflows/.github/workflows/bump-version.yml@v1
    with:
      bump_type: minor
    permissions:
      contents: write
```

**Inputs:**

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `paths` | ❌ | `[]` | JSON array of glob patterns; at least one changed file must match to trigger a bump (e.g., `["src/**", "package.json"]`). Empty array means always run. |
| `bump_type` | ❌ | `patch` | Semver level to increment: `major`, `minor`, or `patch` |
| `version_file` | ❌ | `./VERSION` | Path to version file |
| `version_file_type` | ❌ | `plain` | File type: `plain` (raw text) or `json` |
| `version_json_key` | ❌ | `version` | Key to update when `version_file_type` is `json` |
| `runner_labels` | ❌ | `["ubuntu-24.04"]` | Runner labels as JSON array |
| `allow_fork_prs` | ❌ | `false` | Allow fork PRs to run — must be `false` since the workflow pushes to the PR branch |

**Outputs:**

| Output | Description |
|--------|-------------|
| `old_version` | Version read from the file before the bump |
| `new_version` | Version after the bump (same as `old_version` if skipped) |
| `version_bumped` | `true` if a bump commit was pushed, `false` if skipped |

> **Note:** When the `paths` filter is set and no changed files match, the `bump` job is skipped entirely and all outputs will be empty strings. Callers that consume these outputs should guard against empty values.

**Permissions:**

The calling workflow must grant `contents: write` so the workflow can push the bump commit onto the PR branch:

```yaml
jobs:
  bump-version:
    permissions:
      contents: write
    uses: tnoff/github-workflows/.github/workflows/bump-version.yml@v1
```

---

### `check-pr-labels.yml`

Validates that a PR meets specified label and merge conditions. Useful for conditional workflow execution and cost optimization on private repositories.

```yaml
name: Conditional Build

on:
  pull_request:
    types: [closed]

jobs:
  check-build:
    uses: tnoff/github-workflows/.github/workflows/check-pr-labels.yml@v1
    with:
      required_labels: 'build-docker'
      require_merged: true

  build:
    needs: check-build
    if: needs.check-build.outputs.conditions_met == 'true'
    uses: tnoff/github-workflows/.github/workflows/ocir-push.yml@v1
    with:
      image_name: my-app
    secrets:
      oci_registry: ${{ secrets.OCI_REGISTRY }}
      oci_username: ${{ secrets.OCI_USERNAME }}
      oci_token: ${{ secrets.OCI_TOKEN }}
      oci_namespace: ${{ secrets.OCI_NAMESPACE }}
```

**Inputs:**

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `required_labels` | ❌ | `build-docker` | Comma-separated labels (e.g., `build-docker,deploy`) |
| `require_all_labels` | ❌ | `false` | If true, PR must have ALL labels. If false, ANY label works. |
| `require_merged` | ❌ | `true` | If true, PR must be merged. If false, just check labels. |
| `runner_labels` | ❌ | `["ubuntu-24.04"]` | Runner labels as JSON array |
| `allow_fork_prs` | ❌ | `true` | Allow fork PRs to run (set `false` for self-hosted runners) |

**Outputs:**

| Output | Description |
|--------|-------------|
| `conditions_met` | `true` if all conditions are met, `false` otherwise |
| `pr_merged` | `true` if PR was merged |
| `has_required_labels` | `true` if PR has required labels |
| `pr_labels` | Comma-separated list of all PR labels |

**Permissions:**

The calling workflow must grant `pull-requests: read` permission to access PR labels:

```yaml
jobs:
  check-build:
    permissions:
      contents: read
      pull-requests: read
    uses: tnoff/github-workflows/.github/workflows/check-pr-labels.yml@v1
```

### `dependabot-auto-approve.yml`

Automatically approves and optionally enables auto-merge for Dependabot PRs based on update type (major/minor/patch), package allow/reject lists, and changed file paths. Only runs when the PR author is `dependabot[bot]`.

Git hash updates (where the previous or new version is a 40-character SHA) are always rejected, even if they would otherwise qualify as a patch update. This prevents dependabot from auto-approving action pin changes that carry no meaningful semver signal.

Each call to this workflow is an independent rule. Compose multiple jobs in your calling workflow to express "approve this set of packages under these conditions OR approve that set under those conditions" — since approval and auto-merge are both idempotent, multiple jobs approving the same PR is harmless.

```yaml
# In your app repository: .github/workflows/dependabot.yml
name: Dependabot Auto Approve

on:
  pull_request:
    types: [opened, synchronize, reopened]

jobs:
  auto-approve:
    uses: tnoff/github-workflows/.github/workflows/dependabot-auto-approve.yml@v1
    with:
      allowed_update_types: 'minor,patch'
      reject_packages: 'some-risky-package,another-package'
```

**Inputs:**

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `allowed_update_types` | ❌ | `minor,patch` | Comma-separated semver levels to auto-approve: `major`, `minor`, `patch` |
| `reject_packages` | ❌ | `''` | Comma-separated packages to never auto-approve (takes priority over accept list) |
| `accept_packages` | ❌ | `''` | Comma-separated packages to exclusively auto-approve. If empty, all packages not in the reject list are eligible. |
| `file_pattern` | ❌ | `''` | Glob pattern matched against changed file paths (e.g. `tests/**`). If set, at least one changed file must match for the PR to be eligible. If empty, no file filter is applied. |
| `dependency_groups` | ❌ | `''` | Comma-separated dependabot group names to auto-approve (e.g. `prod-deps,runtime`). Matched against the group name reported by `dependabot/fetch-metadata`. Useful when a single file (e.g. `pyproject.toml`) contains multiple dependency sections that you want to gate independently. If empty, no group filter is applied. |
| `auto_merge` | ❌ | `true` | Enable auto-merge once required checks pass (requires "Allow auto-merge" in repo settings) |
| `auto_merge_packages` | ❌ | `''` | Regex pattern that ALL packages must match to enable auto-merge. If empty, all approved PRs are eligible for auto-merge. |
| `merge_method` | ❌ | `squash` | Merge method: `merge`, `squash`, or `rebase` |
| `add_labels` | ❌ | `''` | Comma-separated labels to add to the PR when approved |
| `remove_labels` | ❌ | `''` | Comma-separated labels to remove from the PR when approved |
| `runner_labels` | ❌ | `["ubuntu-24.04"]` | Runner labels as JSON array |

**Secrets:**

| Secret | Required | Description |
|--------|----------|-------------|
| `bot_token` | ❌ | PAT for a bot user declared in CODEOWNERS. When provided, used instead of `GITHUB_TOKEN` for approving and merging the PR, allowing the bot user to satisfy branch-protection review requirements. |

**Outputs:**

| Output | Description |
|--------|-------------|
| `approved` | `true` if the PR was approved, `false` if skipped |
| `reason` | Human-readable explanation of the decision |

**Permissions:**

The workflow requires `pull-requests: write` to approve and `contents: write` to enable auto-merge. These are granted internally — no extra configuration needed in the calling workflow.

> **Note:** Auto-merge (`auto_merge: true`) requires "Allow auto-merge" to be enabled in your repository settings under **Settings → General → Pull Requests**.
>
> **Note on CODEOWNERS:** The `github-actions[bot]` approval from this workflow does not count toward CODEOWNERS-required reviews. If your branch protection requires a CODEOWNERS review, add a bot user to CODEOWNERS and pass its PAT via the `bot_token` secret (see example below).

**Examples:**

Patch-only, no restrictions:
```yaml
    uses: tnoff/github-workflows/.github/workflows/dependabot-auto-approve.yml@v1
    with:
      allowed_update_types: 'patch'
```

Allow minor/patch but block specific packages:
```yaml
    uses: tnoff/github-workflows/.github/workflows/dependabot-auto-approve.yml@v1
    with:
      allowed_update_types: 'minor,patch'
      reject_packages: 'openssl,cryptography'
```

Only auto-approve a specific set of trusted packages (all update levels):
```yaml
    uses: tnoff/github-workflows/.github/workflows/dependabot-auto-approve.yml@v1
    with:
      allowed_update_types: 'major,minor,patch'
      accept_packages: 'boto3,requests,pydantic'
```

Multi-rule: unrestricted for known-safe packages, patch-only for everything else, and auto-merge anything under `tests/`:
```yaml
jobs:
  # boto3 and friends: approve all semver levels
  auto-approve-boto3:
    uses: tnoff/github-workflows/.github/workflows/dependabot-auto-approve.yml@v1
    with:
      accept_packages: 'boto3,botocore,aiobotocore'
      allowed_update_types: 'major,minor,patch'

  # test dependencies: approve all semver levels, filtered by path
  auto-approve-test-reqs:
    uses: tnoff/github-workflows/.github/workflows/dependabot-auto-approve.yml@v1
    with:
      file_pattern: 'tests/**'
      allowed_update_types: 'major,minor,patch'

  # everything else: patch only
  auto-approve-patch:
    uses: tnoff/github-workflows/.github/workflows/dependabot-auto-approve.yml@v1
    with:
      allowed_update_types: 'patch'
```

Filter by dependabot group — useful for `pyproject.toml` where prod and dev deps live in the same file:
```yaml
# .github/dependabot.yml
updates:
  - package-ecosystem: pip
    directory: /
    schedule:
      interval: weekly
    groups:
      prod-deps:
        dependency-type: production
      dev-deps:
        dependency-type: development
```
```yaml
jobs:
  # Production deps: minor/patch only
  auto-approve-prod:
    uses: tnoff/github-workflows/.github/workflows/dependabot-auto-approve.yml@v1
    with:
      dependency_groups: 'prod-deps'
      allowed_update_types: 'minor,patch'

  # Dev deps: all levels (lower risk)
  auto-approve-dev:
    uses: tnoff/github-workflows/.github/workflows/dependabot-auto-approve.yml@v1
    with:
      dependency_groups: 'dev-deps'
      allowed_update_types: 'major,minor,patch'
```

Add/remove labels on approval:
```yaml
    uses: tnoff/github-workflows/.github/workflows/dependabot-auto-approve.yml@v1
    with:
      allowed_update_types: 'minor,patch'
      add_labels: 'auto-approved,dependencies'
      remove_labels: 'needs-review'
```

Bot user for CODEOWNERS review requirement:
```yaml
# CODEOWNERS contains: * @my-org/bot-account
# BOT_PAT is a PAT for bot-account stored as a repo/org secret
jobs:
  auto-approve:
    uses: tnoff/github-workflows/.github/workflows/dependabot-auto-approve.yml@v1
    with:
      allowed_update_types: 'minor,patch'
    secrets:
      bot_token: ${{ secrets.BOT_PAT }}
```

### `discord-notify.yml`

Sends a failure notification to a Discord channel via webhook. Intended to be called as a dependent job with `if: failure()` after a build job fails.

```yaml
# In your app repository: .github/workflows/ci.yml
jobs:
  build:
    uses: tnoff/github-workflows/.github/workflows/ocir-push.yml@v1
    with:
      image_name: my-app
    secrets:
      oci_registry: ${{ secrets.OCI_REGISTRY }}
      oci_username: ${{ secrets.OCI_USERNAME }}
      oci_token: ${{ secrets.OCI_TOKEN }}
      oci_namespace: ${{ secrets.OCI_NAMESPACE }}

  notify-failure:
    needs: build
    if: failure()
    uses: tnoff/github-workflows/.github/workflows/discord-notify.yml@v1
    secrets:
      discord_webhook_url: ${{ secrets.DISCORD_WEBHOOK_URL }}
```

The notification includes repository, branch, workflow name, actor, commit SHA, and a direct link to the failed run. An optional `message` input can add extra context.

**Inputs:**

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `message` | ❌ | `''` | Additional context to include in the notification |
| `runner_labels` | ❌ | `["ubuntu-24.04"]` | Runner labels as JSON array |

**Secrets:**

| Secret | Required | Description |
|--------|----------|-------------|
| `discord_webhook_url` | ✅ | Discord webhook URL |

**Permissions:**

No special permissions required.

### `coverage-store.yml`

Runs pytest with coverage on `push` to `main` and uploads the result as a named artifact. Used as the baseline for `coverage-check.yml`.

```yaml
# In your app repository: .github/workflows/ci.yml
name: CI

on:
  push:
    branches: [main]

jobs:
  store-coverage:
    uses: tnoff/github-workflows/.github/workflows/coverage-store.yml@v1
    with:
      coverage_source: src/mypackage
      install_command: pip install -e ".[dev]"
```

**Inputs:**

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `coverage_source` | ✅ | - | Space-separated `--cov=` arguments (e.g. `src/mypackage` or `"src/pkg1 src/pkg2"`) |
| `python_version` | ❌ | `3.x` | Python version |
| `pre_install_command` | ❌ | `''` | Command to run before pip install (e.g. `sudo apt-get install -y libpq-dev`) |
| `install_command` | ❌ | `pip install pytest pytest-cov` | Dependency install command |
| `pytest_args` | ❌ | `''` | Extra pytest arguments (no `--cov`/`--cov-report` flags) |
| `working_directory` | ❌ | `.` | Directory to run commands in |
| `artifact_name` | ❌ | `pytest-coverage-baseline` | Artifact name (must match `coverage-check.yml`) |
| `artifact_retention_days` | ❌ | `400` | Days to retain the artifact |
| `runner_labels` | ❌ | `["ubuntu-24.04"]` | Runner labels as JSON array |
| `allow_fork_prs` | ❌ | `true` | Allow fork PRs to run (set `false` for self-hosted runners) |

**Outputs:**

| Output | Description |
|--------|-------------|
| `coverage_percent` | Total coverage percentage (e.g. `87.42`) |

**Permissions:**

No special permissions required. The workflow uses `contents: read` internally.

---

### `coverage-check.yml`

Runs pytest on a PR, downloads the baseline artifact from `main`, and compares overall coverage. The primary failure gate is diff-cover: if any changed or new lines are not covered, the job fails. If overall coverage drops (e.g. because code was removed) but all changed lines are covered, the job posts a warning comment on the PR instead of failing.

```yaml
# In your app repository: .github/workflows/pr.yml
name: PR Checks

on:
  pull_request:
    branches: [main]

jobs:
  coverage:
    uses: tnoff/github-workflows/.github/workflows/coverage-check.yml@v1
    permissions:
      contents: read
      actions: read
    with:
      coverage_source: src/mypackage
      install_command: pip install -e ".[dev]" diff-cover
```

**Inputs:**

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `coverage_source` | ✅ | - | Space-separated `--cov=` arguments (e.g. `src/mypackage` or `"src/pkg1 src/pkg2"`) |
| `python_version` | ❌ | `3.x` | Python version |
| `pre_install_command` | ❌ | `''` | Command to run before pip install (e.g. `sudo apt-get install -y libpq-dev`) |
| `install_command` | ❌ | `pip install pytest pytest-cov diff-cover` | Dependency install command (include `diff-cover`) |
| `pytest_args` | ❌ | `''` | Extra pytest arguments (no `--cov`/`--cov-report` flags) |
| `working_directory` | ❌ | `.` | Directory to run commands in |
| `artifact_name` | ❌ | `pytest-coverage-baseline` | Artifact name (must match `coverage-store.yml`) |
| `fail_on_missing_baseline` | ❌ | `false` | Fail if no baseline artifact is found on main yet |
| `fail_on_diff_cover` | ❌ | `true` | Fail if diff-cover reports less than 100% coverage on changed lines |
| `runner_labels` | ❌ | `["ubuntu-24.04"]` | Runner labels as JSON array |
| `allow_fork_prs` | ❌ | `true` | Allow fork PRs to run (set `false` for self-hosted runners) |

**Outputs:**

| Output | Description |
|--------|-------------|
| `coverage_percent` | Current total coverage percentage |
| `baseline_percent` | Baseline coverage percentage from main branch |
| `coverage_passed` | `true` if coverage did not drop below baseline |

**Permissions:**

The calling workflow must grant `actions: read` (to download artifacts across runs), `contents: read`, and `pull-requests: write` (to post the coverage warning comment):

```yaml
jobs:
  coverage:
    permissions:
      contents: read
      actions: read
      pull-requests: write
    uses: tnoff/github-workflows/.github/workflows/coverage-check.yml@v1
```

---

### `check-action-pins.yml`

Scans all workflow files in `.github/workflows/` and fails if any `uses:` ref is not pinned to a full 40-character commit SHA. Local refs (e.g. `uses: ./.github/workflows/foo.yml`) are ignored.

```yaml
# In your app repository: .github/workflows/pr.yml
jobs:
  check-pins:
    uses: tnoff/github-workflows/.github/workflows/check-action-pins.yml@v1
```

**Inputs:**

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `workflow_dir` | ❌ | `.github/workflows` | Directory to scan |
| `runner_labels` | ❌ | `["ubuntu-24.04"]` | Runner labels as JSON array |
| `allow_fork_prs` | ❌ | `true` | Allow fork PRs to run (set `false` for self-hosted runners) |

**Outputs:**

| Output | Description |
|--------|-------------|
| `violations_found` | `true` if any unpinned actions were detected |

**Permissions:**

No special permissions required. The workflow uses `contents: read` internally.

---

## Self-Hosted Runners

All workflows support self-hosted runners via the `runner_labels` input. When using self-hosted runners on public repositories, set `allow_fork_prs: false` to prevent fork PRs from executing workflows on your infrastructure.

**Example: Using self-hosted OKE runners**

```yaml
jobs:
  build-and-push:
    uses: tnoff/github-workflows/.github/workflows/ocir-push.yml@v1
    with:
      image_name: my-app
      runner_labels: '["self-hosted", "oke"]'
      allow_fork_prs: false
    secrets:
      oci_registry: ${{ secrets.OCI_REGISTRY }}
      oci_username: ${{ secrets.OCI_USERNAME }}
      oci_token: ${{ secrets.OCI_TOKEN }}
      oci_namespace: ${{ secrets.OCI_NAMESPACE }}
```

**How fork protection works:**

When `allow_fork_prs: false`, the workflow will only run if:
- The event is not a pull request, OR
- The pull request originates from the same repository (not a fork)

This prevents external contributors from triggering workflows on your self-hosted runners while still allowing your own PRs and pushes to run normally.

---

## GitLab CI Templates

Templates under `gitlab/` are reusable GitLab CI job definitions. Include them in a consumer repo via `include:` and inherit with `extends:`. Configuration is passed via CI variables; outputs are exposed via `dotenv` artifacts.

### `gitlab/tag.yml`

Equivalent of [`tag.yml`](#tagyml) for GitLab CI. Reads a version file, checks if the tag already exists on the remote, and pushes it if not.

```yaml
# In your app repository's .gitlab-ci.yml
include:
  - project: 'org/ci-workflows'
    ref: main
    file: '/gitlab/tag.yml'

tag-build:
  extends: .tag
  variables:
    VERSION_FILE: './VERSION'
```

For a JSON file like `package.json`:

```yaml
tag-build:
  extends: .tag
  variables:
    VERSION_FILE: './package.json'
    VERSION_FILE_TYPE: 'json'
    VERSION_JSON_KEY: 'version'
```

**Variables:**

| Variable | Default | Description |
|----------|---------|-------------|
| `VERSION_FILE` | `./VERSION` | Path to version file |
| `VERSION_FILE_TYPE` | `plain` | `plain` (raw text) or `json` |
| `VERSION_JSON_KEY` | `version` | Key to extract when `VERSION_FILE_TYPE` is `json` |

**Outputs (via `dotenv` artifact):**

| Variable | Description |
|----------|-------------|
| `VERSION` | Version from file with `v` prefix (e.g., `v0.0.4`) |
| `TAG_CREATED` | `true` if a new tag was created, `false` if skipped |
| `TAG_EXISTS` | `true` if the tag already existed |

### `gitlab/release.yml`

Creates a GitLab Release matching the tag pushed by [`gitlab/tag.yml`](#gitlabtagyml). Reads `VERSION` and `TAG_CREATED` from `.tag`'s dotenv artifact via `needs: artifacts: true`, so it no-ops when the tag already existed instead of creating a duplicate release.

The release description is built from a Keep-a-Changelog formatted `CHANGELOG.md` — the template extracts everything between the `## [X.Y.Z]` heading for the version being released and the next `## [` heading. If no matching section is found, falls back to `"Release <version>"`.

```yaml
# In your app repository's .gitlab-ci.yml
include:
  - project: 'org/ci-workflows'
    ref: main
    file: '/gitlab/tag.yml'
  - project: 'org/ci-workflows'
    ref: main
    file: '/gitlab/release.yml'

stages:
  - tag
  - release

tag-build:
  extends: .tag
  stage: tag
  rules:
    - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH && $CI_PIPELINE_SOURCE != "schedule"
      when: on_success

release:
  extends: .release
  stage: release
  needs:
    - job: tag-build
      artifacts: true
  rules:
    - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH && $CI_PIPELINE_SOURCE != "schedule"
      when: on_success
```

**Variables:**

| Variable | Default | Description |
|----------|---------|-------------|
| `CHANGELOG_FILE` | `CHANGELOG.md` | Path to the changelog. Sections must be headed `## [X.Y.Z] - YYYY-MM-DD`. |

**Inputs (from the upstream `.tag` job's `dotenv` artifact):**

| Variable | Description |
|----------|-------------|
| `VERSION` | Tag name with `v` prefix (e.g. `v1.2.3`) — used as `--tag-name` and in the release title |
| `TAG_CREATED` | `true` if a new tag was pushed; any other value skips the release |

**Permissions:**

The release job uses the GitLab Releases API, which is accessible to the built-in `CI_JOB_TOKEN` — no extra variables or tokens required.

### `gitlab/discord-notify.yml`

Sends Discord notifications for pipeline and merge request events. The embed title, color, and fields adapt automatically based on `NOTIFY_TYPE` and whether the job runs in an MR pipeline context.

> **Note:** GitLab CI pipelines do not trigger on issue events. For issue notifications use GitLab's built-in Discord integration under **Settings → Integrations → Discord**.

```yaml
# In your app repository's .gitlab-ci.yml
include:
  - project: 'org/ci-workflows'
    ref: main
    file: '/gitlab/discord-notify.yml'

notify-failure:
  extends: .discord-notify
  variables:
    NOTIFY_TYPE: failure
    DISCORD_WEBHOOK_URL: $DISCORD_FAILURES_WEBHOOK
  rules:
    - when: on_failure

notify-mr:
  extends: .discord-notify
  variables:
    NOTIFY_TYPE: mr_opened
    DISCORD_WEBHOOK_URL: $DISCORD_MR_WEBHOOK
  rules:
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"
      when: on_success
```

**Variables:**

| Variable | Default | Description |
|----------|---------|-------------|
| `NOTIFY_TYPE` | `failure` | Embed style: `failure`, `success`, `mr_opened`, or `mr_merged` |
| `DISCORD_WEBHOOK_URL` | `$DISCORD_WEBHOOK_URL` | Webhook URL for the target channel. Override per job to send to different channels. Falls back to the `DISCORD_WEBHOOK_URL` project/group CI variable. |
| `NOTIFY_MESSAGE` | `''` | Optional extra text appended to the embed |

**Notification types:**

| Type | Color | Use case |
|------|-------|----------|
| `failure` | Red | Pipeline failed |
| `success` | Green | Pipeline succeeded |
| `mr_opened` | Blue | MR opened or updated |
| `mr_merged` | Purple | MR merged (push to default branch) |

When running in an MR pipeline (`CI_PIPELINE_SOURCE == "merge_request_event"`), the embed automatically includes the MR title, number, and branch arrow (`source → target`) instead of commit SHA and branch.

**Permissions:**

No special permissions required. Set `DISCORD_WEBHOOK_URL` (or a per-channel equivalent) as a masked CI variable under **Settings → CI/CD → Variables**.

---

### `gitlab/renovate.yml`

Runs [Renovate](https://docs.renovatebot.com/) to open MRs for outdated dependencies. Designed to run on a scheduled pipeline — trigger interval is configured in **Settings → CI/CD → Schedules**, not in the YAML itself.

When the schedule fires, Renovate scans the repo against its `renovate.json` config, opens MRs for any outdated dependencies it finds, and rebases existing Renovate MRs if a newer version has since been released. If nothing is outdated it does nothing.

```yaml
# In your app repository's .gitlab-ci.yml
include:
  - project: 'org/ci-workflows'
    ref: main
    file: '/gitlab/renovate.yml'

renovate:
  extends: .renovate
  rules:
    - if: $CI_PIPELINE_SOURCE == "schedule"
```

A `renovate.json` at the repo root controls which managers are enabled and any package rules:

```json
{
  "$schema": "https://docs.renovatebot.com/renovate-schema.json",
  "extends": ["config:recommended"],
  "enabledManagers": ["pre-commit", "docker"],
  "labels": ["dependencies"]
}
```

**Variables:**

| Variable | Required | Description |
|----------|----------|-------------|
| `RENOVATE_TOKEN` | ✅ | GitLab PAT with `api` scope — used to open and update MRs |
| `GITHUB_COM_TOKEN` | optional | GitHub PAT (no scopes needed beyond public read) — lets Renovate fetch release notes from github.com when updating dependencies whose source/changelog lives there. Without it, MR bodies show "Release Notes retrieval for this MR were skipped because no github.com credentials were available." |

**Permissions:**

Create a GitLab PAT with `api` scope and store it as a masked CI variable named `RENOVATE_TOKEN` under **Settings → CI/CD → Variables**. Then create a schedule under **Settings → CI/CD → Schedules** (e.g. `0 3 * * 1` for Monday at 3am).

For release notes from public GitHub repos, also create a GitHub PAT (Personal access tokens (classic) → no scopes needed; or fine-grained with public repo read), store it as a masked CI variable named `GITHUB_COM_TOKEN`, and Renovate will pick it up automatically.

---

### `gitlab/bump-version.yml`

Auto-bumps the patch version on a branch by comparing the `VERSION` file against the default branch. If they match (not yet bumped), increments the patch version, commits, and pushes back to the source branch. Idempotent — exits cleanly if already bumped, preventing push loops.

Authenticates the push using `GITLAB_PUSH_TOKEN` (GitLab PAT, project access token, or deploy token with `write_repository` scope) when set, otherwise falls back to `CI_JOB_TOKEN` with CI job token push access enabled under **Settings → CI/CD → Token Access**.

**Recommended: set `GITLAB_PUSH_TOKEN`.** Pushes authored with `CI_JOB_TOKEN` do not trigger a follow-up pipeline (GitLab's infinite-loop guard), so the MR head advances past the latest pipeline's SHA and the MR widget reports `ci_must_pass` with no pipeline to show. A PAT-authored push triggers a fresh pipeline on the bump commit and keeps the MR widget green.

```yaml
# In your app repository's .gitlab-ci.yml
include:
  - project: 'org/ci-workflows'
    ref: main
    file: '/gitlab/bump-version.yml'

bump-version:
  extends: .bump-version
  rules:
    - if: $CI_PIPELINE_SOURCE == "merge_request_event" && $CI_MERGE_REQUEST_SOURCE_BRANCH_NAME =~ /^renovate\//
```

For a JSON file like `package.json`:

```yaml
bump-version:
  extends: .bump-version
  variables:
    VERSION_FILE: 'package.json'
    VERSION_FILE_TYPE: 'json'
    VERSION_JSON_KEY: 'version'
  rules:
    - if: $CI_PIPELINE_SOURCE == "merge_request_event" && $CI_MERGE_REQUEST_SOURCE_BRANCH_NAME =~ /^renovate\//
```

**Variables:**

| Variable | Default | Description |
|----------|---------|-------------|
| `VERSION_FILE` | `VERSION` | Path to the version file |
| `VERSION_FILE_TYPE` | `plain` | `plain` (raw text) or `json` |
| `VERSION_JSON_KEY` | `version` | Key holding the version when `VERSION_FILE_TYPE` is `json` |
| `COMPARE_BRANCH` | `$CI_DEFAULT_BRANCH` / `main` | Branch to compare against |
| `BUMP_CHANGELOG` | `""` | Set to `"true"` to also prepend a new section to `CHANGELOG_FILE` and stage it as part of the bump commit. |
| `CHANGELOG_FILE` | `CHANGELOG.md` | Path to the changelog. Only used when `BUMP_CHANGELOG` is `"true"`. |

**Changelog updates:**

When `BUMP_CHANGELOG=true`, the template prepends a `## [X.Y.Z] - YYYY-MM-DD` section to `CHANGELOG_FILE` immediately before the first existing version heading (or at the end of the file if none exist). The entry under `### Changed` is built from the MR title:

- If the title matches renovate's `<type>(deps): update dependency <name> to <version>` pattern (e.g. `fix(deps): update dependency tox to v4.53.1`), it becomes `Bumped tox to v4.53.1`.
- Otherwise, the MR title is used verbatim.

The update is idempotent — if a section for the new version already exists in the file, the changelog is left untouched.

```yaml
bump-version:
  extends: .bump-version
  variables:
    BUMP_CHANGELOG: 'true'
  rules:
    - if: $CI_PIPELINE_SOURCE == "merge_request_event" && $CI_MERGE_REQUEST_SOURCE_BRANCH_NAME =~ /^renovate\//
```

---

### `gitlab/docker-push.yml`

Builds a Docker image for one or more platforms and pushes two tags to an OCI-compatible registry: the short commit SHA and `latest`. Uses Docker-in-Docker (`docker:27-dind`) and installs QEMU binfmt handlers via `tonistiigi/binfmt` so cross-platform builds work without a native runner for each architecture.

```yaml
# In your app repository's .gitlab-ci.yml
include:
  - project: 'org/ci-workflows'
    ref: main
    file: '/gitlab/docker-push.yml'

docker-push:
  extends: .docker-push
  stage: build
  needs: []
  rules:
    - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH && $CI_PIPELINE_SOURCE != "schedule"
      when: on_success
```

Override the target platform:

```yaml
docker-push:
  extends: .docker-push
  variables:
    DOCKER_PLATFORM: 'linux/amd64'
```

**Variables:**

| Variable | Default | Description |
|----------|---------|-------------|
| `DOCKER_PLATFORM` | `linux/arm64` | Platform(s) to build (passed to `--platform`) |
| `OCI_REGISTRY_64` | *(required)* | OCI registry hostname (e.g. `registry.example.com`), base64-encoded |
| `OCI_NAMESPACE_64` | *(required)* | Registry namespace / organisation, base64-encoded |
| `OCI_REPO_NAME_64` | *(required)* | Image repository name, base64-encoded |
| `OCI_USERNAME_64` | *(required)* | Registry login username, base64-encoded |
| `OCI_TOKEN_64` | *(required)* | Registry login password / token, base64-encoded |

All values are base64-encoded so short ones (e.g. namespace, repo name) clear GitLab's masking length requirement. The template decodes them into shell variables before use.

**Permissions:**

No special GitLab CI permissions required. Set the `OCI_*_64` values as masked CI variables under **Settings → CI/CD → Variables**.

---

### `gitlab/trufflehog.yml`

Scans the repo for leaked secrets using [TruffleHog](https://github.com/trufflesecurity/trufflehog). On a merge request pipeline, scans only the commits added in the MR (using `CI_MERGE_REQUEST_DIFF_BASE_SHA` as the `--since-commit`). On any other pipeline (push to default branch, scheduled, manual), scans the full git history of the current branch.

By default, runs with `--only-verified --fail` so the job fails only when TruffleHog confirms a finding by validating the credential against its issuing API. This keeps noise low; flip `TRUFFLEHOG_EXTRA_ARGS` to drop `--only-verified` if you want unverified findings to fail too.

```yaml
# In your app repository's .gitlab-ci.yml
include:
  - project: 'org/ci-workflows'
    ref: main
    file: '/gitlab/trufflehog.yml'

trufflehog:
  extends: .trufflehog
  rules:
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"
    - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH && $CI_PIPELINE_SOURCE != "schedule"
```

Exclude generated paths or known-safe fixtures by pointing `TRUFFLEHOG_EXCLUDE_PATHS` at a regex file committed to the repo:

```yaml
trufflehog:
  extends: .trufflehog
  variables:
    TRUFFLEHOG_EXCLUDE_PATHS: '.trufflehog-exclude'
```

```
# .trufflehog-exclude — one regex per line
^vendor/
^tests/fixtures/
\.lock$
```

**Variables:**

| Variable | Default | Description |
|----------|---------|-------------|
| `TRUFFLEHOG_IMAGE` | `docker.io/trufflesecurity/trufflehog:latest` | Container image to run |
| `TRUFFLEHOG_EXTRA_ARGS` | `--only-verified --fail` | Flags appended to `trufflehog git` |
| `TRUFFLEHOG_EXCLUDE_PATHS` | `''` | Path to a file of newline-separated regex path excludes |
| `TRUFFLEHOG_FULL_HISTORY` | `false` | Set to `true` to force a full-history scan even on MR pipelines |

**Permissions:**

No special CI permissions required. The job runs with the default `CI_JOB_TOKEN` and only reads the working tree.

> **Note:** GitLab also ships built-in [Secret Detection](https://docs.gitlab.com/ee/user/application_security/secret_detection/) (Gitleaks-based) on paid tiers. Use that if you already have the security dashboard wired up; pick TruffleHog when you want verified-secret detection (it validates findings against the issuing API to filter false positives).

---

### `gitlab/trufflehog-image.yml`

Companion to `gitlab/trufflehog.yml`. The source-level template scans tracked files; this one scans an assembled image's layers, which catches secrets that leak via a `RUN` command or a copied-then-deleted file but never appear in tracked source.

The template scans a `docker save` tarball produced by an upstream build job — it does not build the image itself. TruffleHog reads the OCI tarball directly via `file://`, so the scan job runs on a slim `alpine:3` image with no Docker-in-Docker service. Wire it up with `needs:` to a job that publishes the tarball as an artifact.

```yaml
# In your app repository's .gitlab-ci.yml
include:
  - project: 'org/ci-workflows'
    ref: main
    file: '/gitlab/trufflehog-image.yml'

build-image:
  stage: build
  image: docker.io/library/docker:27
  services:
    - docker.io/library/docker:27-dind
  script:
    - docker build -t app:$CI_COMMIT_SHORT_SHA .
    - docker save app:$CI_COMMIT_SHORT_SHA -o image.tar
  artifacts:
    paths:
      - image.tar

trufflehog-image:
  extends: .trufflehog-image
  needs:
    - job: build-image
      artifacts: true
  variables:
    TRUFFLEHOG_IMAGE_TARBALL: image.tar
  rules:
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"
    - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH && $CI_PIPELINE_SOURCE != "schedule"
```

**Variables:**

| Variable | Default | Description |
|----------|---------|-------------|
| `TRUFFLEHOG_IMAGE_TARBALL` | *(required)* | Path to a `docker save` tarball, typically fetched from an upstream build job's artifacts. |
| `TRUFFLEHOG_VERSION` | `''` | Pin a TruffleHog release (e.g. `3.83.7`). Empty installs the latest release. |
| `TRUFFLEHOG_EXTRA_ARGS` | `--only-verified --fail --concurrency=2` | Flags appended to `trufflehog docker`. The concurrency cap keeps memory predictable on larger images (TruffleHog otherwise spawns one worker per CPU); raise it if you need throughput and have headroom. |

**Permissions:**

No registry credentials required — the scan job neither pulls nor pushes. The upstream build job that produces the tarball is what needs Docker-in-Docker; the scan job itself does not.

> **Note:** This template installs TruffleHog by piping the upstream `install.sh` from `raw.githubusercontent.com` at job time. Pin `TRUFFLEHOG_VERSION` if your security policy disallows running unpinned upstream scripts.

---

### `gitlab/tag.yml` — Permissions

The CI job must be able to push tags to the repository. There are two options:

**Option A — CI job token (simpler):** Enable push access for the built-in `CI_JOB_TOKEN` under **Settings → CI/CD → Token Access → "Allow CI job token to push to this repository"**. No extra variables needed; the template configures the remote automatically.

**Option B — Deploy or personal access token:** Create a token with `write_repository` scope and store it as a CI variable named `GITLAB_PUSH_TOKEN`. The template will use it automatically when present. This is required if your GitLab instance doesn't support job token push access (self-hosted GitLab < 16.2).

```yaml
# Settings → CI/CD → Variables
GITLAB_PUSH_TOKEN = <your deploy or PAT token>  # masked, not protected unless branch-locked
```
