# AGENTS.md

This file provides guidance to AI coding agents when working with code in this repository.

## Project Overview

**github-workflows** is a centralized repository containing reusable GitHub Actions workflows for standardizing CI/CD pipelines across all application repositories. This repository implements the "reusable workflows" pattern to ensure consistent Docker image building, tagging, and deployment to OCI Container Registry (OCIR).

## Purpose

Application repositories use similar CI/CD logic for building Docker images and pushing to OCIR. This repository provides shared, versioned workflows that eliminate duplication and ensure consistency across all applications.

## Repository Structure

```
github-workflows/
├── .github/workflows/          # GitHub Actions workflows
│   ├── ocir-push.yml           # Reusable: Docker build & push workflow
│   ├── tag.yml                 # Reusable: Auto-tagging workflow
│   └── auto-tag.yml            # Repo-specific: Tags this repository on merge
├── README.md                   # User-facing documentation
├── DEVELOPMENT.md              # Development setup and workflow validation
└── AGENTS.md                   # This file
```

## Key Workflows

### ocir-push.yml

**Purpose:** Build and push Docker images to OCIR with standardized VERSION file-based tagging.

**Features:**
- Reads version from a VERSION file in the calling repository
- Generates three tags: `<version>`, `<commit-sha>`, `latest` (on main)
- Supports multi-platform builds (linux/amd64, linux/arm64)
- Conditional push (can build-only for PRs without pushing)
- Docker layer caching via GitHub Actions cache
- Rich build summary in GitHub UI

**Usage Pattern:**
```yaml
# In calling repository (e.g., my-app/.github/workflows/ci.yml)
jobs:
  build-check:
    if: github.event_name == 'pull_request'
    uses: tnoff/github-workflows/.github/workflows/ocir-push.yml@v1
    with:
      image_name: my-app
      registry_namespace: my-namespace
      push_image: false
    secrets:
      oci_registry: ${{ secrets.OCI_REGISTRY }}
      oci_username: ${{ secrets.OCI_USERNAME }}
      oci_password: ${{ secrets.OCI_PASSWORD }}
```

**Inputs:**
- `image_name` (required) - Name of the Docker image
- `registry_namespace` (optional) - OCI registry namespace
- `dockerfile_path` (optional, default: `./Dockerfile`) - Path to Dockerfile
- `docker_context` (optional, default: `.`) - Build context
- `platforms` (optional, default: `linux/amd64,linux/arm64`) - Target platforms
- `version_file` (optional, default: `./VERSION`) - Path to VERSION file
- `push_image` (optional, default: `true`) - Whether to push the image

**Secrets:**
- `oci_registry` (required) - OCIR URL (e.g., `iad.ocir.io`)
- `oci_username` (required) - OCIR username
- `oci_password` (required) - OCIR auth token

**Outputs:**
- `version` - Version read from VERSION file
- `image_tags` - Full image tags that were built

## Tagging Strategy

### VERSION File Format
Each application repository should have a VERSION file in the root:
```
0.0.4
```

Rules:
- Semantic versioning format (MAJOR.MINOR.PATCH)
- No `v` prefix
- No trailing whitespace

### Generated Tags

**On Pull Request** (with `push_image: false`):
- `<commit-sha>` - 7-character short SHA

**On Main Branch Push:**
- `<version>` - From VERSION file (e.g., `0.0.4`)
- `<commit-sha>` - 7-character short SHA
- `latest` - Always the most recent main build

**Example:**
```
iad.ocir.io/my-namespace/my-app:0.0.4
iad.ocir.io/my-namespace/my-app:abc1234
iad.ocir.io/my-namespace/my-app:latest
```

## Versioning This Repository

This repository uses Git tags for version stability:

```bash
# Create a new version
git tag -a v1 -m "Version 1.0.0"
git push origin v1

# Apps reference specific versions
uses: tnoff/github-workflows/.github/workflows/ocir-push.yml@v1
```

**Recommended reference strategies:**
- `@v1` - Latest v1.x.x (recommended for stability with updates)
- `@main` - Bleeding edge (for testing new features)
- `@<commit-sha>` - Pinned to specific commit (maximum stability)

## Making Changes to Workflows

When modifying workflows in this repository:

1. **Test locally first** - Use act or test in a sandbox repo
2. **Create a feature branch** - Don't modify main directly
3. **Test with one app** - Update one app to use `@<branch-name>` before merging
4. **Version appropriately:**
   - Patch change (bug fix): Update docs, no new tag needed (apps using `@v1` get it automatically)
   - Minor change (new feature, backward compatible): Update docs, consider `v1.1.0` tag
   - Major change (breaking): Create `v2` tag, document migration path

## Integration with Infrastructure

### Infrastructure-as-Code Integration
Infrastructure tools can create GitHub repositories and inject the OCIR credentials as secrets:
- `OCI_REGISTRY`
- `OCI_USERNAME`
- `OCI_PASSWORD`

These secrets are consumed by the reusable workflows.

### Application Repositories
Each app should:
1. Have a VERSION file in the root
2. Replace existing workflows with calls to this repository's workflows
3. Update on merge to main (or use label-based triggering if preferred)

### Kubernetes Deployments
Kubernetes manifests reference the tagged images. After standardization, they can reliably use:
- `latest` for development environments
- `<version>` for production deployments
- `<commit-sha>` for debugging specific builds

## Migration Guide

For step-by-step migration instructions, see:
- `examples/app-migration-guide.md` - Detailed migration example
- `examples/standard-app-workflow.yml` - Template for new apps

**Migration checklist per app:**
1. ✅ Add VERSION file if not present
2. ✅ Create or update `.github/workflows/ci.yml`
3. ✅ Remove old workflow files
4. ✅ Test with a PR (should build but not push)
5. ✅ Merge and verify push to OCIR
6. ✅ Update Kubernetes manifests if needed

## Future Enhancements

Planned additional workflows:
- `python-test.yml` - Standardized pytest with coverage
- `python-lint.yml` - Standardized linting (pylint, ruff, black)
- `semantic-release.yml` - Auto-bump VERSION file based on conventional commits
- `docker-scan.yml` - Security scanning with Trivy or Snyk
- `multi-stage-build.yml` - Optimized multi-stage Docker builds

## Important Notes for AI Assistants

1. **Don't modify workflows without testing** - Changes affect all consuming repositories
2. **Maintain backward compatibility** - Apps may reference `@v1` and expect consistent behavior
3. **Document all changes** - Update README.md with any workflow modifications
4. **Version appropriately** - Breaking changes require new major version tag
5. **Test before tagging** - Use feature branches and test in a real app repo first
6. **Keep workflows focused** - Each workflow should do one thing well
7. **Use semantic versioning** - Follow semver for repository tags

## Related Documentation

- See `/home/tnorth/Code/AGENTS.md` for overall architecture
- See `/home/tnorth/Code/PROJECTS.md` for the standardization roadmap
- See individual app repositories for usage examples after migration
