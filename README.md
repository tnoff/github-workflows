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

Automatically creates Git tags based on the VERSION file. Checks if the tag already exists before creating it, preventing duplicate tag errors.

```yaml
jobs:
  create-tag:
    uses: tnoff/github-workflows/.github/workflows/tag.yml@v1
    with:
      version_file: ./VERSION
```

**Inputs:**

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `version_file` | ❌ | `./VERSION` | Path to VERSION file |
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

Automatically approves and optionally enables auto-merge for Dependabot PRs based on update type (major/minor/patch) and package allow/reject lists. Only runs when the PR author is `dependabot[bot]`.

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
| `auto_merge` | ❌ | `true` | Enable auto-merge once required checks pass (requires "Allow auto-merge" in repo settings) |
| `merge_method` | ❌ | `squash` | Merge method: `merge`, `squash`, or `rebase` |
| `runner_labels` | ❌ | `["ubuntu-24.04"]` | Runner labels as JSON array |

**Outputs:**

| Output | Description |
|--------|-------------|
| `approved` | `true` if the PR was approved, `false` if skipped |
| `reason` | Human-readable explanation of the decision |

**Permissions:**

The workflow requires `pull-requests: write` to approve and `contents: write` to enable auto-merge. These are granted internally — no extra configuration needed in the calling workflow.

> **Note:** Auto-merge (`auto_merge: true`) requires "Allow auto-merge" to be enabled in your repository settings under **Settings → General → Pull Requests**.

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
