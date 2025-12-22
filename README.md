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

**Outputs:**

| Output | Description |
|--------|-------------|
| `version` | Version from file with `v` prefix (e.g., `v0.0.4`) |
| `tag_created` | `true` if a new tag was created, `false` if skipped |
| `tag_exists` | `true` if tag already existed, `false` if new |

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

**Outputs:**

| Output | Description |
|--------|-------------|
| `conditions_met` | `true` if all conditions are met, `false` otherwise |
| `pr_merged` | `true` if PR was merged |
| `has_required_labels` | `true` if PR has required labels |
| `pr_labels` | Comma-separated list of all PR labels |
