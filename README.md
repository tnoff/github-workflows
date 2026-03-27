# GitHub Workflows

Reusable GitHub Actions workflows for standardizing CI/CD across all application repositories.

> **For Contributors:** See [DEVELOPMENT.md](./DEVELOPMENT.md) for local workflow validation and development setup.

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
| `coverage_source` | ✅ | - | Argument to `--cov=` (e.g. `src/mypackage`) |
| `python_version` | ❌ | `3.x` | Python version |
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

Runs pytest on a PR, downloads the baseline artifact from `main`, and compares overall coverage. Fails the check if coverage drops below the baseline. Also runs `diff-cover` to report which lines in the PR's changed code are uncovered (informational only — never blocks merging).

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
| `coverage_source` | ✅ | - | Argument to `--cov=` (e.g. `src/mypackage`) |
| `python_version` | ❌ | `3.x` | Python version |
| `install_command` | ❌ | `pip install pytest pytest-cov diff-cover` | Dependency install command (include `diff-cover`) |
| `pytest_args` | ❌ | `''` | Extra pytest arguments (no `--cov`/`--cov-report` flags) |
| `working_directory` | ❌ | `.` | Directory to run commands in |
| `artifact_name` | ❌ | `pytest-coverage-baseline` | Artifact name (must match `coverage-store.yml`) |
| `fail_on_missing_baseline` | ❌ | `false` | Fail if no baseline artifact is found on main yet |
| `runner_labels` | ❌ | `["ubuntu-24.04"]` | Runner labels as JSON array |
| `allow_fork_prs` | ❌ | `true` | Allow fork PRs to run (set `false` for self-hosted runners) |

**Outputs:**

| Output | Description |
|--------|-------------|
| `coverage_percent` | Current total coverage percentage |
| `baseline_percent` | Baseline coverage percentage from main branch |
| `coverage_passed` | `true` if coverage did not drop below baseline |

**Permissions:**

The calling workflow must grant `actions: read` (to download artifacts across runs) and `contents: read`:

```yaml
jobs:
  coverage:
    permissions:
      contents: read
      actions: read
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
