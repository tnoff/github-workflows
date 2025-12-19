# GitHub Workflows

Reusable GitHub Actions workflows for standardizing CI/CD across all application repositories.

> **For Contributors:** See [DEVELOPMENT.md](./DEVELOPMENT.md) for local workflow validation and development setup.

## Available Workflows

### `ocir-push.yml`

Builds and pushes Docker images to OCI Container Registry (OCIR) with version tagging from a VERSION file.

### `tag.yml`

Creates Git tags based on the VERSION file. Automatically checks if a tag already exists before creating a new one.

**Features:**
- ✅ Reads version from VERSION file
- ✅ Tags with: version, commit SHA, and 'latest' (on main)
- ✅ Multi-platform builds (amd64/arm64)
- ✅ Docker layer caching via GitHub Actions cache
- ✅ Conditional push (build-only for PRs)
- ✅ Detailed build summary in GitHub UI

**Usage:**

```yaml
# In your app repository: .github/workflows/ci.yml
name: CI/CD

on:
  push:
    branches: [main]
  pull_request:

jobs:
  # Build and test on PRs (don't push)
  build-check:
    if: github.event_name == 'pull_request'
    uses: tnoff/github-workflows/.github/workflows/ocir-push.yml@v1
    with:
      image_name: my-app
      push_image: false  # Don't push on PRs
    secrets:
      oci_registry: ${{ secrets.OCI_REGISTRY }}
      oci_username: ${{ secrets.OCI_USERNAME }}
      oci_password: ${{ secrets.OCI_PASSWORD }}

  # Build and push on main branch
  deploy:
    if: github.event_name == 'push' && github.ref == 'refs/heads/main'
    uses: tnoff/github-workflows/.github/workflows/ocir-push.yml@v1
    with:
      image_name: my-app
      platforms: linux/amd64,linux/arm64
    secrets:
      oci_registry: ${{ secrets.OCI_REGISTRY }}
      oci_username: ${{ secrets.OCI_USERNAME }}
      oci_password: ${{ secrets.OCI_PASSWORD }}
```

**Inputs:**

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `image_name` | ✅ | - | Name of the Docker image |
| `dockerfile_path` | ❌ | `./Dockerfile` | Path to Dockerfile |
| `docker_context` | ❌ | `.` | Docker build context |
| `platforms` | ❌ | `linux/amd64,linux/arm64` | Platforms to build |
| `version_file` | ❌ | `./VERSION` | Path to VERSION file |
| `push_image` | ❌ | `true` | Whether to push the image |

**Secrets:**

| Secret | Required | Description |
|--------|----------|-------------|
| `oci_registry` | ✅ | OCI Registry URL with namespace (e.g., `iad.ocir.io/my-namespace`) |
| `oci_username` | ✅ | OCI Username |
| `oci_password` | ✅ | OCI Password/Auth Token |

**Outputs:**

| Output | Description |
|--------|-------------|
| `version` | Version read from VERSION file |
| `image_tags` | Full image tags that were built |

## Tagging Strategy

The workflow generates the following tags:

### On Pull Requests (with `push_image: false`)
- `<commit-sha>` - Short commit SHA (7 chars)

### On Main Branch Push
- `<version>` - From VERSION file (e.g., `0.0.4`, `1.2.3`)
- `<commit-sha>` - Short commit SHA (7 chars)
- `latest` - Always points to the most recent main build

### Example Tags
If VERSION file contains `0.0.4` and commit SHA is `abc1234567890def`, with `OCI_REGISTRY` set to `iad.ocir.io/my-namespace`:
```
iad.ocir.io/my-namespace/my-app:0.0.4
iad.ocir.io/my-namespace/my-app:abc1234
iad.ocir.io/my-namespace/my-app:latest
```

## VERSION File Format

Create a `VERSION` file in the root of your repository:

```
0.0.4
```

**Best Practices:**
- Use semantic versioning (e.g., `1.2.3`)
- No `v` prefix needed
- No whitespace or newlines after version
- Update VERSION file in the same PR as version changes

## Setting Up a New App

1. **Add VERSION file** to your app repository:
   ```bash
   echo "0.0.1" > VERSION
   git add VERSION
   git commit -m "Add VERSION file for standardized tagging"
   ```

2. **Create `.github/workflows/ci.yml`** in your app repository using the example above

3. **Ensure secrets are configured** in your repository:
   - `OCI_REGISTRY` - Your OCIR URL with namespace (e.g., `iad.ocir.io/my-namespace`)
   - `OCI_USERNAME` - Your OCIR username
   - `OCI_PASSWORD` - Your OCIR auth token

   These are typically injected by terraform via the `infra` workspace.

4. **Test the workflow**:
   - Create a PR - should build but not push
   - Merge to main - should build and push with all tags

## Migrating Existing Apps

Apps that already use GitHub Actions can be migrated by:

1. Keep existing VERSION file (if present) or create one
2. Replace workflow file with the standardized version
3. Update image references in Kubernetes manifests to use new tags
4. Remove old workflow files

## Future Workflows

Planned additions:
- `python-test.yml` - Run pytest with coverage
- `python-lint.yml` - Run pylint/ruff
- `semantic-release.yml` - Auto-bump VERSION file
- `docker-scan.yml` - Security scanning with Trivy
