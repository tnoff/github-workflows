# GitHub Workflows

Reusable GitHub Actions workflows for standardizing CI/CD across all application repositories.

> **For Contributors:** See [DEVELOPMENT.md](./DEVELOPMENT.md) for local workflow validation and development setup.

## Available Workflows

### `ocir-push.yml`

Builds and pushes Docker images to OCI Container Registry (OCIR) with version tagging from a VERSION file.

### `tag.yml`

Automatically creates Git tags based on the VERSION file. Checks if the tag already exists before creating it, preventing duplicate tag errors.

### `check-pr-labels.yml`

Validates that a PR meets specified label and merge conditions. Useful for conditional workflow execution and cost optimization on private repositories.

**Features:**
- ✅ Reads version from VERSION file
- ✅ Tags with: version, commit SHA, and 'latest' (on main)
- ✅ Multi-platform builds (amd64/arm64)
- ✅ Docker layer caching via GitHub Actions cache
- ✅ Detailed build summary in GitHub UI

**Usage:**

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

## Tagging Strategy

The workflow generates the following Docker image tags when called:

- `<version>` - From VERSION file (e.g., `0.0.4`, `1.2.3`)
- `<commit-sha>` - Short commit SHA (7 chars)
- `latest` - Always points to the most recent build

### Example Tags
If VERSION file contains `0.0.4` and commit SHA is `abc1234567890def`, with `OCI_REGISTRY` set to `iad.ocir.io` and `OCI_NAMESPACE` set to `my-namespace`:
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
   - `OCI_REGISTRY` - Your OCIR URL (e.g., `iad.ocir.io`)
   - `OCI_USERNAME` - Your OCIR username
   - `OCI_TOKEN` - Your OCIR auth token
   - `OCI_NAMESPACE` - Your OCIR namespace

   These are typically injected by terraform via the `infra` workspace.

4. **Test the workflow**:
   - Push to main - should build and push with all tags

## Automated Git Tagging

The `tag.yml` workflow automatically creates Git tags based on your VERSION file, making releases trackable and preventing duplicate tags.

### Usage Example

Add tagging after your deployment:

```yaml
name: CI/CD

on:
  push:
    branches: [main]

jobs:
  deploy:
    uses: tnoff/github-workflows/.github/workflows/ocir-push.yml@v1
    with:
      image_name: my-app
    secrets:
      oci_registry: ${{ secrets.OCI_REGISTRY }}
      oci_username: ${{ secrets.OCI_USERNAME }}
      oci_token: ${{ secrets.OCI_TOKEN }}
      oci_namespace: ${{ secrets.OCI_NAMESPACE }}

  # Automatically tag the commit with version from VERSION file
  create-tag:
    needs: deploy
    uses: tnoff/github-workflows/.github/workflows/tag.yml@v1
```

This will:
1. Read the `VERSION` file (e.g., `0.0.4`)
2. Check if tag `v0.0.4` exists
3. Create the tag if it doesn't exist
4. Skip if the tag already exists (no error)

### Configuration

**Inputs:**

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `version_file` | ❌ | `./VERSION` | Path to VERSION file |

**Outputs:**

| Output | Type | Description |
|--------|------|-------------|
| `version` | string | Version from file with `v` prefix (e.g., `v0.0.4`) |
| `tag_created` | boolean | `true` if a new tag was created, `false` if skipped |
| `tag_exists` | boolean | `true` if tag already existed, `false` if new |

### Using Outputs

Capture and use the workflow outputs in subsequent jobs:

```yaml
jobs:
  create-tag:
    uses: tnoff/github-workflows/.github/workflows/tag.yml@v1
    # Outputs: version, tag_created, tag_exists

  notify:
    needs: create-tag
    runs-on: ubuntu-latest
    steps:
      - name: Notify on new release
        if: needs.create-tag.outputs.tag_created == 'true'
        run: |
          echo "🎉 New release created: ${{ needs.create-tag.outputs.version }}"
          # Send Slack notification, update docs, etc.

      - name: Skip notification if tag exists
        if: needs.create-tag.outputs.tag_exists == 'true'
        run: |
          echo "ℹ️  Tag ${{ needs.create-tag.outputs.version }} already exists, skipping notification"
```

### Advanced: Conditional Deployment

Use tag outputs to control deployment flow:

```yaml
jobs:
  create-tag:
    uses: tnoff/github-workflows/.github/workflows/tag.yml@v1

  # Only deploy to production if this is a new release
  deploy-production:
    needs: create-tag
    if: needs.create-tag.outputs.tag_created == 'true'
    runs-on: ubuntu-latest
    steps:
      - name: Deploy to production
        run: |
          echo "Deploying ${{ needs.create-tag.outputs.version }} to production..."
          kubectl set image deployment/my-app \
            my-app=${{ secrets.OCI_REGISTRY }}/my-app:${{ needs.create-tag.outputs.version }}

  # Create GitHub Release
  create-release:
    needs: create-tag
    if: needs.create-tag.outputs.tag_created == 'true'
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Create GitHub Release
        uses: actions/create-release@v1
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        with:
          tag_name: ${{ needs.create-tag.outputs.version }}
          release_name: Release ${{ needs.create-tag.outputs.version }}
          draft: false
          prerelease: false
```

### Custom VERSION File Location

If your VERSION file is in a non-standard location:

```yaml
jobs:
  create-tag:
    uses: tnoff/github-workflows/.github/workflows/tag.yml@v1
    with:
      version_file: ./config/VERSION
```

### VERSION File Format

Your VERSION file should contain only the version number:

```
0.0.4
```

**Rules:**
- ✅ Use semantic versioning: `MAJOR.MINOR.PATCH`
- ✅ No `v` prefix (the workflow adds it)
- ✅ No trailing whitespace or newlines
- ✅ Single line only

**Examples:**
```
✅ 0.0.4
✅ 1.2.3
✅ 2.0.0-beta.1
❌ v0.0.4        (don't include v prefix)
❌ 0.0.4\n       (no trailing newline)
❌ version: 0.0.4  (no extra text)
```

### Permissions Required

The workflow requires `contents: write` permission to create tags. This is automatically granted when using `workflow_call`, but if you're running it directly, ensure:

```yaml
permissions:
  contents: write
```

### Behavior Summary

| Scenario | Behavior | Output |
|----------|----------|--------|
| VERSION file exists, tag doesn't exist | Creates new tag | `tag_created: true` |
| VERSION file exists, tag exists | Skips (no error) | `tag_created: false, tag_exists: true` |
| VERSION file missing | Workflow fails | Error |
| Invalid VERSION format | Creates tag anyway | Tag created with exact content |

### Integration with Docker Builds

Complete CI/CD with building, tagging, and deployment:

```yaml
name: Complete CI/CD Pipeline

on:
  push:
    branches: [main]

jobs:
  # 1. Build and push Docker image
  build:
    uses: tnoff/github-workflows/.github/workflows/ocir-push.yml@v1
    with:
      image_name: my-app
    secrets:
      oci_registry: ${{ secrets.OCI_REGISTRY }}
      oci_username: ${{ secrets.OCI_USERNAME }}
      oci_token: ${{ secrets.OCI_TOKEN }}
      oci_namespace: ${{ secrets.OCI_NAMESPACE }}

  # 2. Create Git tag from VERSION file
  tag:
    needs: build
    uses: tnoff/github-workflows/.github/workflows/tag.yml@v1

  # 3. Scan the image for vulnerabilities
  scan:
    needs: build
    uses: tnoff/github-workflows/.github/workflows/docker-scan.yml@v1
    with:
      image_name: my-app:${{ needs.build.outputs.version }}
      severity: HIGH,CRITICAL
    secrets:
      oci_registry: ${{ secrets.OCI_REGISTRY }}
      oci_username: ${{ secrets.OCI_USERNAME }}
      oci_token: ${{ secrets.OCI_TOKEN }}
      oci_namespace: ${{ secrets.OCI_NAMESPACE }}

  # 4. Deploy to staging (always)
  deploy-staging:
    needs: [build, scan]
    runs-on: ubuntu-latest
    steps:
      - name: Deploy to staging
        run: echo "Deploying to staging..."

  # 5. Deploy to production (only on new releases)
  deploy-production:
    needs: [build, scan, tag]
    if: needs.tag.outputs.tag_created == 'true'
    runs-on: ubuntu-latest
    steps:
      - name: Deploy to production
        run: echo "Deploying ${{ needs.tag.outputs.version }} to production..."
```

## PR Label Checking

The `check-pr-labels.yml` workflow validates that a PR meets specific label and merge conditions. This is especially useful for **cost optimization** on private repositories where you want to control when workflows execute.

### Use Cases

- 💰 **Cost Optimization** - Only build when explicitly requested via labels
- 🎯 **Selective Builds** - Build only PRs marked with specific labels
- 🔒 **Approval-Based Builds** - Require team member to add label before building
- 📊 **Workflow Control** - Fine-grained control over when builds execute

### Usage Example

Basic usage with default settings (requires `build-docker` label and merged PR):

```yaml
name: Conditional Build

on:
  pull_request:
    types: [closed]

jobs:
  # Check if build should proceed
  check-build:
    uses: tnoff/github-workflows/.github/workflows/check-pr-labels.yml@v1

  # Only build if conditions are met
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

### Configuration

**Inputs:**

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `required_labels` | ❌ | `build-docker` | Comma-separated labels required (e.g., `build-docker,deploy`) |
| `require_all_labels` | ❌ | `false` | If true, PR must have ALL labels. If false, ANY label works. |
| `require_merged` | ❌ | `true` | If true, PR must be merged. If false, just check labels. |

**Outputs:**

| Output | Type | Description |
|--------|------|-------------|
| `conditions_met` | boolean | `true` if all conditions are met, `false` otherwise |
| `pr_merged` | boolean | `true` if PR was merged |
| `has_required_labels` | boolean | `true` if PR has required labels |
| `pr_labels` | string | Comma-separated list of all PR labels |

### Checking Strategies

**1. Default: Merged + Single Label (Cost Optimized)**

Only build when PR is merged AND has `build-docker` label:

```yaml
check-build:
  uses: tnoff/github-workflows/.github/workflows/check-pr-labels.yml@v1
  # Defaults: require_merged=true, required_labels='build-docker'
```

**Workflow:**
1. Developer creates PR → No build
2. Team reviews PR → No build
3. Team adds `build-docker` label → No build yet
4. PR is merged → ✅ Build runs

**2. Multiple Labels (ANY)**

Build if PR has `build-docker` OR `hotfix` label:

```yaml
check-build:
  uses: tnoff/github-workflows/.github/workflows/check-pr-labels.yml@v1
  with:
    required_labels: 'build-docker,hotfix'
    require_all_labels: false
```

**3. Multiple Labels (ALL)**

Build only if PR has BOTH `build-docker` AND `approved` labels:

```yaml
check-build:
  uses: tnoff/github-workflows/.github/workflows/check-pr-labels.yml@v1
  with:
    required_labels: 'build-docker,approved'
    require_all_labels: true
```

**4. Label Only (No Merge Required)**

Build anytime PR has the label, even if not merged:

```yaml
check-build:
  uses: tnoff/github-workflows/.github/workflows/check-pr-labels.yml@v1
  with:
    required_labels: 'preview-build'
    require_merged: false
```

Useful for preview deployments or testing builds before merge.

### Complete Example with Notifications

```yaml
name: Smart Build Workflow

on:
  pull_request:
    types: [closed, labeled]

jobs:
  # Check build conditions
  check:
    uses: tnoff/github-workflows/.github/workflows/check-pr-labels.yml@v1
    with:
      required_labels: 'build-docker,deploy'
      require_all_labels: false  # Either label works

  # Build if conditions met
  build:
    needs: check
    if: needs.check.outputs.conditions_met == 'true'
    uses: tnoff/github-workflows/.github/workflows/ocir-push.yml@v1
    with:
      image_name: my-app
    secrets:
      oci_registry: ${{ secrets.OCI_REGISTRY }}
      oci_username: ${{ secrets.OCI_USERNAME }}
      oci_token: ${{ secrets.OCI_TOKEN }}
      oci_namespace: ${{ secrets.OCI_NAMESPACE }}

  # Notify when build is skipped
  notify-skip:
    needs: check
    if: needs.check.outputs.conditions_met == 'false'
    runs-on: ubuntu-latest
    steps:
      - name: Comment on PR
        uses: actions/github-script@v7
        with:
          script: |
            github.rest.issues.createComment({
              issue_number: context.issue.number,
              owner: context.repo.owner,
              repo: context.repo.repo,
              body: '⏭️ Build skipped. Add `build-docker` label to trigger build on next merge.'
            })

  # Notify on successful build
  notify-success:
    needs: [check, build]
    if: needs.check.outputs.conditions_met == 'true'
    runs-on: ubuntu-latest
    steps:
      - name: Build completed
        run: |
          echo "✅ Build completed for PR with labels: ${{ needs.check.outputs.pr_labels }}"
```

### Cost Savings Example

**Traditional approach (build on every push):**
- 10 PRs/month × 5 pushes per PR = 50 builds
- Cost: ~50 builds × 4 minutes × $0.008/minute = **$1.60/month per repo**

**Label-based approach:**
- 10 PRs/month × 1 final build when labeled = 10 builds
- Cost: ~10 builds × 4 minutes × $0.008/minute = **$0.32/month per repo**

**Savings: 80% reduction** 💰

For 20 repositories: **$25.60/month savings**

### Setup Instructions

1. **Create the workflow** in your repository:
   ```bash
   # .github/workflows/build.yml
   # Use example from above
   ```

2. **Configure branch protection**:
   - Go to Settings → Branches → Branch protection rules
   - Add rule for `main` branch
   - Enable "Require status checks to pass"
   - Add the `build` job as required check
   - This ensures PR can't merge until build label is added and build passes

3. **Add labels to repository**:
   ```bash
   # Using GitHub CLI
   gh label create build-docker --color "0366d6" --description "Trigger Docker build"
   gh label create deploy --color "2ea44f" --description "Deploy to production"
   ```

4. **Team workflow**:
   - Developer creates PR
   - Team reviews code
   - If approved, team member adds `build-docker` label
   - Merge PR → Build runs automatically

### Using Outputs for Complex Logic

```yaml
jobs:
  check:
    uses: tnoff/github-workflows/.github/workflows/check-pr-labels.yml@v1

  # Different actions based on check results
  build-dev:
    needs: check
    if: |
      needs.check.outputs.conditions_met == 'true' &&
      !contains(needs.check.outputs.pr_labels, 'production')
    runs-on: ubuntu-latest
    steps:
      - run: echo "Building for development..."

  build-prod:
    needs: check
    if: |
      needs.check.outputs.conditions_met == 'true' &&
      contains(needs.check.outputs.pr_labels, 'production')
    runs-on: ubuntu-latest
    steps:
      - run: echo "Building for production..."
```

### Troubleshooting

**Build doesn't run even with label:**
- Check that PR is actually merged (if `require_merged: true`)
- Verify label name matches exactly (case-sensitive)
- Check workflow logs for condition evaluation

**Build runs when it shouldn't:**
- Verify `require_all_labels` setting matches your intent
- Check if `require_merged` should be `true`

**Can't see PR labels:**
- Ensure workflow has `pull-requests: read` permission
- Check that workflow triggers on `pull_request` events

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
