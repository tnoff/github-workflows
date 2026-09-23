# GitHub Workflows

Reusable GitHub Actions workflows for standardizing CI/CD across all application repositories.

> **For Contributors:** See [DEVELOPMENT.md](docs/DEVELOPMENT.md) for local workflow validation and development setup.

## Table of Contents

**GitHub Actions (`/.github/workflows/`)**

- [ocir-push.yml](#ocir-pushyml) — Build and push Docker images to OCIR
- [docker-build-check.yml](#docker-build-checkyml) — Build (no push) and secret-scan an image on a PR
- [docker-push.yml](#docker-pushyml) — Build and push an image to OCIR under two tags
- [tag.yml](#tagyml) — Auto-create Git tags from a version file
- [release.yml](#releaseyml) — Cut a GitHub release from a tag, with notes from the changelog
- [assemble-changelog.yml](#assemble-changelogyml) — Fold changelog fragments into CHANGELOG.md at release time
- [bump-version.yml](#bump-versionyml) — Bump the version file on a PR branch
- [trigger-bump-dispatch.yml](#trigger-bump-dispatchyml) — Ask docker-apps to rewrite its image pin after a push
- [check-pr-labels.yml](#check-pr-labelsyml) — Validate PR labels and merge conditions
- [discord-notify.yml](#discord-notifyyml) — Send failure notifications to Discord
- [techdocs-publish.yml](#techdocs-publishyml) — Build and publish a component's TechDocs site
- [coverage-store.yml](#coverage-storeyml) — Store pytest coverage baseline artifact
- [coverage-check.yml](#coverage-checkyml) — Compare PR coverage against baseline
- [tox.yml](#toxyml) — Python tox matrix plus a diff-cover gate
- [pre-commit.yml](#pre-commityml) — Run the repo's pre-commit hooks
- [trufflehog.yml](#trufflehogyml) — Scan a repository for verified secrets
- [spellcheck.yml](#spellcheckyml) — Run pyspelling against a project's spellcheck config
- [renovate.yml](#renovateyml) — Run self-hosted Renovate against the calling repository
- [branch-cleanup.yml](#branch-cleanupyml) — Prune stale automation branches
- [check-action-pins.yml](#check-action-pinsyml) — Enforce SHA-pinned action refs
- [check-workflow-contracts.yml](#check-workflow-contractsyml) — Validate pinned reusable-workflow calls against the callee
- [Self-Hosted Runners](#self-hosted-runners)

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

### `docker-build-check.yml`

Builds an image on a pull request without pushing it, then scans the result for secrets. One workflow that used to be two separate GitLab jobs with an S3 tarball handoff between them -- here the built image is already in the local daemon, so the scan is just another step.

```yaml
# In your app repository: .github/workflows/pr.yml
name: PR Checks

on:
  pull_request:

jobs:
  build-check:
    uses: tnoff/github-workflows/.github/workflows/docker-build-check.yml@v1
    with:
      platform: linux/arm64
```

**Inputs:**

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `context` | ❌ | `.` | Build context directory |
| `dockerfile` | ❌ | `Dockerfile` | Path to the Dockerfile, relative to the repo root |
| `build_args` | ❌ | `''` | Newline-separated build args (`KEY=value` per line) |
| `platform` | ❌ | `linux/arm64` | Target platform. Defaults to match the cluster; paired with an arm64 runner this is a native build, no QEMU |
| `cache` | ❌ | `true` | Use the GitHub Actions layer cache |
| `scan_image` | ❌ | `true` | Scan the built image for secrets |
| `trufflehog_extra_args` | ❌ | `--only-verified` | Extra flags for the image scan. Do not pass `--fail`; the invocation already sets it and trufflehog rejects a repeated flag |
| `runner_labels` | ❌ | `["ubuntu-24.04-arm"]` | Runner labels as JSON array. `ubuntu-24.04-arm` is free for public repos and builds `linux/arm64` natively |
| `allow_fork_prs` | ❌ | `true` | Allow fork PRs to run this workflow |

**Permissions:**

No special permissions required. The workflow uses `contents: read` internally.

### `docker-push.yml`

Builds an image with `docker/build-push-action` and pushes it to OCIR under two tags built from one invocation, so both tags point at the same digest. The registry, namespace, and repo name are plain inputs rather than secrets -- see the note in the workflow file on why: GitHub silently blanks a job output that contains secret material, which previously broke `trigger-bump-dispatch.yml`'s downstream image name.

```yaml
# In your app repository: .github/workflows/ci.yml
name: CI

on:
  push:
    branches: [main]

jobs:
  push:
    uses: tnoff/github-workflows/.github/workflows/docker-push.yml@v1
    with:
      registry: iad.ocir.io
      namespace: my-namespace
      repo_name: my-app
    secrets:
      oci_username: ${{ secrets.OCI_USERNAME }}
      oci_token: ${{ secrets.OCI_TOKEN }}
```

**Inputs:**

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `context` | ❌ | `.` | Build context directory |
| `dockerfile` | ❌ | `Dockerfile` | Path to the Dockerfile, relative to the repo root |
| `build_args` | ❌ | `''` | Newline-separated build args (`KEY=value` per line) |
| `platform` | ❌ | `linux/arm64` | Target platform |
| `tag_override` | ❌ | `''` | When set, tags are `<override>` and `<override>-<short sha>` instead of `latest` and `<short sha>`. Used by producers that publish variants |
| `cache` | ❌ | `true` | Use the GitHub Actions layer cache |
| `runner_labels` | ❌ | `["ubuntu-24.04-arm"]` | Runner labels as JSON array |
| `registry` | ✅ | - | OCIR registry host, e.g. `iad.ocir.io` |
| `namespace` | ✅ | - | OCI object storage namespace |
| `repo_name` | ✅ | - | Repository name within the namespace |

**Secrets:**

| Secret | Required | Description |
|--------|----------|-------------|
| `oci_username` | ✅ | OCIR username, `<namespace>/<user>` |
| `oci_token` | ✅ | OCIR auth token |

**Outputs:**

| Output | Description |
|--------|-------------|
| `image` | Full image reference without a tag |
| `primary_tag` | The moving tag (`latest`, or `tag_override`) |
| `secondary_tag` | The immutable per-commit tag |

**Permissions:**

No special permissions required. The workflow uses `contents: read` internally.

### `tag.yml`

Automatically creates Git tags based on a version file. Checks if the tag already exists before creating it, preventing duplicate tag errors. Supports plain text version files (e.g. `VERSION`) and JSON files (e.g. `package.json`). Authenticates as the `tnoff-ci` GitHub App to push the tag, because the fleet's branch rulesets bypass that App (not a write-scoped bot token) and because a push made with the default `GITHUB_TOKEN` triggers no downstream `release.yml` run.

```yaml
jobs:
  tag:
    uses: tnoff/github-workflows/.github/workflows/tag.yml@v1
    with:
      version_file: ./VERSION
    secrets:
      app_client_id: ${{ secrets.CI_APP_CLIENT_ID }}
      app_private_key: ${{ secrets.CI_APP_PRIVATE_KEY }}
```

For a JSON file like `package.json`:

```yaml
jobs:
  tag:
    uses: tnoff/github-workflows/.github/workflows/tag.yml@v1
    with:
      version_file: ./package.json
      version_file_type: json
      version_json_key: version
    secrets:
      app_client_id: ${{ secrets.CI_APP_CLIENT_ID }}
      app_private_key: ${{ secrets.CI_APP_PRIVATE_KEY }}
```

Chained into `release.yml`:

```yaml
jobs:
  tag:
    uses: tnoff/github-workflows/.github/workflows/tag.yml@v1
    secrets:
      app_client_id: ${{ secrets.CI_APP_CLIENT_ID }}
      app_private_key: ${{ secrets.CI_APP_PRIVATE_KEY }}
  release:
    needs: tag
    uses: tnoff/github-workflows/.github/workflows/release.yml@v1
    with:
      version: ${{ needs.tag.outputs.version }}
      tag_created: ${{ needs.tag.outputs.tag_created }}
```

**Inputs:**

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `version_file` | ❌ | `VERSION` | Path to version file |
| `version_file_type` | ❌ | `plain` | File type: `plain` (raw text) or `json` |
| `version_json_key` | ❌ | `version` | Key to extract when `version_file_type` is `json` |
| `gate_on_fragments` | ❌ | `false` | Set `true` on repos wired for `assemble-changelog.yml`. While changelog fragments are still pending, the job defers (`tag_created=false`) so `assemble-changelog.yml` folds and pushes first; that push fires a follow-up run where the fragment directory is empty, the gate passes, and tag/release run against the assembled changelog |
| `changelog_dir` | ❌ | `changelog.d` | Directory of unassembled fragments; only read when `gate_on_fragments` is `true` |
| `runner_labels` | ❌ | `["ubuntu-24.04"]` | Runner labels as JSON array |

**Secrets:**

| Secret | Required | Description |
|--------|----------|-------------|
| `app_client_id` | ✅ | Client ID of the `tnoff-ci` GitHub App (`CI_APP_CLIENT_ID`) |
| `app_private_key` | ✅ | Private key PEM of the `tnoff-ci` GitHub App (`CI_APP_PRIVATE_KEY`) |

**Outputs:**

| Output | Description |
|--------|-------------|
| `version` | The tag, with a leading `v` (empty when deferred by `gate_on_fragments`) |
| `tag_created` | `true` if a new tag was pushed, `false` if skipped or deferred |
| `tag_exists` | `true` if tag already existed, `false` if new |

**Permissions:**

No extra permissions to grant in the calling workflow -- the job pushes using the minted App token, not the caller's `GITHUB_TOKEN`.

### `release.yml`

Cuts a GitHub release for a tag `tag.yml` created, with release notes lifted from the section of `CHANGELOG.md` matching that version. Skips cleanly when `tag_created` is `false` (the tag job deferred or found an existing tag).

```yaml
jobs:
  tag:
    uses: tnoff/github-workflows/.github/workflows/tag.yml@v1
    secrets:
      app_client_id: ${{ secrets.CI_APP_CLIENT_ID }}
      app_private_key: ${{ secrets.CI_APP_PRIVATE_KEY }}
  release:
    needs: tag
    uses: tnoff/github-workflows/.github/workflows/release.yml@v1
    with:
      version: ${{ needs.tag.outputs.version }}
      tag_created: ${{ needs.tag.outputs.tag_created }}
```

**Inputs:**

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `version` | ✅ | - | Tag to release, with leading `v` (from the tag workflow) |
| `tag_created` | ✅ | - | Whether the tag workflow actually created a tag |
| `changelog_file` | ❌ | `CHANGELOG.md` | Path to the assembled changelog |
| `runner_labels` | ❌ | `["ubuntu-24.04"]` | Runner labels as JSON array |

**Permissions:**

The calling workflow must grant `contents: write` so the job can create the release via `gh release create`:

```yaml
jobs:
  release:
    permissions:
      contents: write
    uses: tnoff/github-workflows/.github/workflows/release.yml@v1
```

### `assemble-changelog.yml`

Folds accumulated `changelog.d/*.md` fragments into `CHANGELOG.md` on the default branch at release time, deletes the fragments, and pushes back. Idempotent -- a no-op when there are no fragments, which is what stops the push it triggers from looping. Refuses to fold into a version that already has a `## [<version>]` section in the changelog, since that would mean whatever added the fragment forgot to bump the version file.

Pairs with `tag.yml`'s `gate_on_fragments` input: while fragments are pending, `tag.yml` defers instead of tagging, this workflow folds and pushes, and the resulting follow-up run tags against the now-assembled changelog.

```yaml
jobs:
  changelog:
    uses: tnoff/github-workflows/.github/workflows/assemble-changelog.yml@v1
    secrets:
      app_client_id: ${{ secrets.CI_APP_CLIENT_ID }}
      app_private_key: ${{ secrets.CI_APP_PRIVATE_KEY }}
```

**Inputs:**

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `version_file` | ❌ | `VERSION` | Path to the version file |
| `version_file_type` | ❌ | `plain` | File type: `plain` (raw text) or `json` |
| `version_json_key` | ❌ | `version` | Key holding the version when `version_file_type` is `json` |
| `changelog_dir` | ❌ | `changelog.d` | Directory holding unassembled fragments |
| `changelog_file` | ❌ | `CHANGELOG.md` | Path to the assembled changelog |
| `runner_labels` | ❌ | `["ubuntu-24.04"]` | Runner labels as JSON array |

**Secrets:**

| Secret | Required | Description |
|--------|----------|-------------|
| `app_client_id` | ✅ | Client ID of the `tnoff-ci` GitHub App (`CI_APP_CLIENT_ID`) |
| `app_private_key` | ✅ | Private key PEM of the `tnoff-ci` GitHub App (`CI_APP_PRIVATE_KEY`) |

**Outputs:**

| Output | Description |
|--------|-------------|
| `assembled` | `true` if a fold commit was pushed, `false` if there were no fragments |

**Permissions:**

No extra permissions to grant in the calling workflow -- the job pushes using the minted App token. The token must not be the default `GITHUB_TOKEN`: the whole fragment-gating design depends on this push triggering the follow-up run that `tag.yml`'s `gate_on_fragments` waits for.

### `bump-version.yml`

Bumps the version file on a PR branch by committing the new version directly onto the PR. The workflow is idempotent: if the version file already differs from the base branch, it skips -- this is both the loop guard and an "already done" check. On a rebase it peels its own prior bump commit (tagged with an `X-Auto-Bump: version` trailer) and recomputes against the new base, rather than stacking a stale bump.

> **Note:** This workflow cannot run on fork PRs because it needs to push a commit back to the PR branch. `allow_fork_prs` defaults to `false`.

```yaml
jobs:
  bump-version:
    uses: tnoff/github-workflows/.github/workflows/bump-version.yml@v1
    with:
      version_file: package.json
      version_file_type: json
    secrets:
      app_client_id: ${{ secrets.CI_APP_CLIENT_ID }}
      app_private_key: ${{ secrets.CI_APP_PRIVATE_KEY }}
```

**Inputs:**

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `paths` | ❌ | `[]` | JSON array of glob patterns; at least one changed file must match to trigger a bump (e.g., `["src/**", "package.json"]`). Empty array means always run. |
| `bump_type` | ❌ | `patch` | Semver level to increment: `major`, `minor`, or `patch` |
| `version_file` | ❌ | `VERSION` | Path to version file |
| `version_file_type` | ❌ | `plain` | File type: `plain` (raw text) or `json` |
| `version_json_key` | ❌ | `version` | Key to update when `version_file_type` is `json` |
| `bump_changelog` | ❌ | `false` | Write a changelog *fragment* for this change under `changelog_dir`, folded in later by `assemble-changelog.yml` |
| `changelog_dir` | ❌ | `changelog.d` | Directory holding unassembled changelog fragments |
| `runner_labels` | ❌ | `["ubuntu-24.04"]` | Runner labels as JSON array |
| `allow_fork_prs` | ❌ | `false` | Allow fork PRs to run — must be `false` since the workflow pushes to the PR branch |

**Secrets:**

| Secret | Required | Description |
|--------|----------|-------------|
| `app_client_id` | ✅ | Client ID of the `tnoff-ci` GitHub App (`CI_APP_CLIENT_ID`) |
| `app_private_key` | ✅ | Private key PEM of the `tnoff-ci` GitHub App (`CI_APP_PRIVATE_KEY`) |

**Outputs:**

| Output | Description |
|--------|-------------|
| `old_version` | Version read from the file before the bump |
| `new_version` | Version after the bump (same as `old_version` if skipped) |
| `version_bumped` | `true` if a bump commit was pushed, `false` if skipped |

> **Note:** When the `paths` filter is set and no changed files match, the `bump` job is skipped entirely and all outputs will be empty strings. Callers that consume these outputs should guard against empty values.

**Permissions:**

No extra permissions to grant in the calling workflow -- the job pushes using the minted App token, not the caller's `GITHUB_TOKEN`.

### `trigger-bump-dispatch.yml`

After a producer pushes a new image, dispatches a `repository_dispatch` event asking `docker-apps` to rewrite its pin and open a PR. `bump_source` is a contract with docker-apps' `bump-image-pin.yml`, not a free-form label -- the receiver maps it to an image name and the files that pin it.

```yaml
jobs:
  push:
    uses: tnoff/github-workflows/.github/workflows/docker-push.yml@v1
    with:
      registry: iad.ocir.io
      namespace: my-namespace
      repo_name: my-app
    secrets:
      oci_username: ${{ secrets.OCI_USERNAME }}
      oci_token: ${{ secrets.OCI_TOKEN }}

  trigger-bump:
    needs: push
    uses: tnoff/github-workflows/.github/workflows/trigger-bump-dispatch.yml@v1
    with:
      bump_source: my-app
      image: ${{ needs.push.outputs.image }}
      image_tag: ${{ needs.push.outputs.secondary_tag }}
    secrets:
      app_client_id: ${{ secrets.CI_APP_CLIENT_ID }}
      app_private_key: ${{ secrets.CI_APP_PRIVATE_KEY }}
```

**Inputs:**

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `bump_source` | ✅ | - | Identifier for this producer. Maps to an image name and pin files on the receiving side -- a contract with docker-apps' `bump-image-pin.yml`, not a free-form label |
| `image` | ✅ | - | Full image reference without a tag. Recorded in the dispatch payload and the log line; NOT used to decide what gets rewritten |
| `image_tag` | ✅ | - | Tag to pin to, normally the short commit SHA |
| `target_repo` | ❌ | `tnoff/docker-apps` | `owner/repo` of the GitOps repository to dispatch to |
| `fail_on_error` | ❌ | `false` | Whether a failed dispatch fails this workflow. Defaults false: the image is already pushed, so a downstream automation hiccup should not retroactively fail the producer |
| `runner_labels` | ❌ | `["ubuntu-24.04"]` | Runner labels as JSON array |

**Secrets:**

| Secret | Required | Description |
|--------|----------|-------------|
| `app_client_id` | ✅ | Client ID of the `tnoff-ci` GitHub App |
| `app_private_key` | ✅ | Private key PEM of the `tnoff-ci` GitHub App. Needs `Contents: write` on the TARGET repo, and must be installed on the target as well as on this producer |

**Permissions:**

No extra permissions to grant in the calling workflow -- the job mints a token scoped to the target repo internally.

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
| `source_repo` | ❌ | `''` | `owner/repo` of the run being reported. Defaults to the calling repo |
| `source_run_url` | ❌ | `''` | URL of the run being reported. Defaults to the calling run |
| `source_workflow` | ❌ | `''` | Name of the workflow being reported. Defaults to the calling workflow |
| `source_branch` | ❌ | `''` | Branch of the run being reported. Defaults to the calling ref |
| `source_actor` | ❌ | `''` | Actor who triggered the run being reported. Defaults to the calling actor |
| `source_sha` | ❌ | `''` | Commit SHA of the run being reported. Defaults to the calling SHA |

The `source_*` overrides exist because a reusable workflow runs **inside the caller's run**: `github.run_id`, `github.workflow` and `github.repository` all describe the caller. That is right when a job reports its own failure, and wrong when a workflow reports on a run that already finished — every field would name the reporter. `notify-failure.yml` and `startup-failure-sweep.yml` both set them.

**Secrets:**

| Secret | Required | Description |
|--------|----------|-------------|
| `discord_webhook_url` | ✅ | Discord webhook URL |

**Permissions:**

No special permissions required.

### `techdocs-publish.yml`

Builds a component's mkdocs site with `@techdocs/cli` and publishes it to an S3-compatible TechDocs storage bucket, on every push that touches its docs. This is the setup TechDocs backends running with `techdocs.builder: external` require -- they only ever read from storage, so something else has to build and publish. GitHub-hosted runners have Docker available by default, which is what `techdocs-cli generate` needs and what a minimal backend image typically does not have.

```yaml
# In your app repository: .github/workflows/techdocs-publish.yml
name: Publish TechDocs

on:
  push:
    branches: [main]
    paths: ['docs/**', 'mkdocs.yml', 'catalog-info.yaml']

jobs:
  publish:
    uses: tnoff/github-workflows/.github/workflows/techdocs-publish.yml@v1
    with:
      entity_ref: default/Component/my-service
    secrets:
      techdocs_s3_access_key_id: ${{ secrets.TECHDOCS_S3_ACCESS_KEY_ID }}
      techdocs_s3_secret_access_key: ${{ secrets.TECHDOCS_S3_SECRET_ACCESS_KEY }}
      techdocs_s3_bucket_name: ${{ secrets.TECHDOCS_S3_BUCKET_NAME }}
      techdocs_s3_endpoint: ${{ secrets.TECHDOCS_S3_ENDPOINT }}
      techdocs_s3_region: ${{ secrets.TECHDOCS_S3_REGION }}
```

**Inputs:**

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `entity_ref` | ✅ | | Backstage entity uid, `namespace/Kind/name` (case-sensitive), e.g. `default/Component/my-service` |
| `legacy_copy_readme_to_index` | ❌ | `false` | Passes `--legacyCopyReadmeMdToIndexMd` to `techdocs-cli generate`, copying `docs/README.md` to `docs/index.md` before building. Defaults off because it's actively harmful when `docs/README.md` already exists: mkdocs treats the resulting pair as a conflict and drops `README.md` from the build, breaking every link that points at it (including a nav entry). mkdocs already falls back to `README.md` as the homepage on its own when no `index.md` exists -- only turn this on for a `docs/` with neither file. |
| `techdocs_cli_version` | ❌ | `1.12.0` | Pinned `@techdocs/cli` version |
| `runner_labels` | ❌ | `["ubuntu-24.04"]` | Runner labels as JSON array |

**Secrets:**

| Secret | Required | Description |
|--------|----------|-------------|
| `techdocs_s3_access_key_id` | ✅ | Access key for a bucket-scoped identity with write access to the TechDocs bucket |
| `techdocs_s3_secret_access_key` | ✅ | Secret key for the same identity |
| `techdocs_s3_bucket_name` | ✅ | Target bucket name |
| `techdocs_s3_endpoint` | ✅ | S3-compatible endpoint URL (e.g. an OCI Object Storage endpoint) |
| `techdocs_s3_region` | ✅ | Region used for SigV4 signing against the endpoint above |

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

### `tox.yml`

A Python tox matrix plus a diff-cover gate against the base branch. `discover` runs `tox -l` to find `py<X><Y>`-style environments and turns them into a JSON matrix; each leg runs its own environment; the highest-versioned leg's coverage feeds `diff-cover`. A trailing `result` job always runs and is the one check name safe to put in a branch ruleset -- the leg names come from a dynamic matrix, so they can't be required directly, and GitHub scores `skipped` as success, which rules out requiring `diff-cover` on its own.

```yaml
# In your app repository: .github/workflows/ci.yml
name: CI

on:
  pull_request:

jobs:
  tox:
    uses: tnoff/github-workflows/.github/workflows/tox.yml@v1
    with:
      extra_apt: 'sqlite3 ffmpeg'
```

**Inputs:**

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `extra_apt` | ❌ | `''` | Space-separated apt packages needed by the test suite (e.g. `sqlite3 ffmpeg`) |
| `pre_commands` | ❌ | `''` | Shell run after `extra_apt` and before tox, in each matrix leg -- for a test suite that needs a running service rather than just a package. Free-form rather than a boolean flag, since a reusable workflow can't attach a service container conditionally |
| `diff_cover_fail_under` | ❌ | `100` | Coverage threshold for changed lines, percent |
| `diff_cover_compare_branch` | ❌ | `''` | Branch to diff against. Empty (default) uses the pull request's own base branch |
| `discover_python_version` | ❌ | `3.x` | Python used to run `tox -l` in the discover job |
| `cache_tox` | ❌ | `true` | Cache the `.tox` virtualenvs between runs |
| `runner_labels` | ❌ | `["ubuntu-24.04"]` | Runner labels as JSON array |
| `allow_fork_prs` | ❌ | `true` | Allow fork PRs to run (set `false` for self-hosted runners) |

**Outputs:**

| Output | Description |
|--------|-------------|
| `python_versions` | JSON array of Python versions discovered from `tox.ini` |

**Permissions:**

No special permissions required. The workflow uses `contents: read` internally.

---

### `pre-commit.yml`

Runs every pre-commit hook across the repository, on a hosted runner with `pip install pre-commit`. Installs Python tooling only -- a hook with `language: system` that shells out to a binary on `PATH` needs that binary present some other way; `language: docker_image` hooks work fine, since hosted runners have Docker.

```yaml
# In your app repository: .github/workflows/ci.yml
jobs:
  pre-commit:
    uses: tnoff/github-workflows/.github/workflows/pre-commit.yml@v1
```

**Inputs:**

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `runner_labels` | ❌ | `["ubuntu-24.04"]` | Runner labels as JSON array |
| `python_version` | ❌ | `3.13` | Python used to run pre-commit itself, not the hooks |
| `extra_packages` | ❌ | `''` | Space-separated pip packages installed alongside pre-commit, for hooks that import them |
| `all_files` | ❌ | `true` | `true` runs `pre-commit run --all-files`. Set `false` to run only the files a pull request changes (ignored outside a `pull_request` event, which falls back to `--all-files`) |
| `fetch_depth` | ❌ | `0` | Checkout depth. Defaults to full history on purpose -- a shallow clone doesn't make a history-reading hook fail, it makes it quietly wrong (e.g. `git log -1 --format=%ad -- <file>` returns the shallow boundary commit's date). Set `1` only once you've checked no hook reads git history |

**Permissions:**

No special permissions required. The workflow uses `contents: read` internally.

---

### `trufflehog.yml`

Scans a repository for verified secrets with TruffleHog. On a `pull_request` event, scans only the commits the PR adds (base..head); on any other event (push to the default branch, schedule, manual) scans the full history of the current branch.

```yaml
# In your app repository: .github/workflows/ci.yml
jobs:
  secrets:
    uses: tnoff/github-workflows/.github/workflows/trufflehog.yml@v1
```

**Inputs:**

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `runner_labels` | ❌ | `["ubuntu-24.04"]` | Runner labels as JSON array |
| `allow_fork_prs` | ❌ | `true` | Allow fork PRs to run (set `false` for self-hosted runners) |
| `extra_args` | ❌ | `--only-verified` | Extra flags appended to the trufflehog invocation. Do not pass `--fail`; the action already runs with `--fail --no-update --github-actions` and trufflehog rejects a repeated flag |
| `exclude_paths` | ❌ | `''` | Path to a file of newline-separated regex path excludes, relative to the repo root. Empty excludes nothing |
| `full_history` | ❌ | `false` | Force a full-history scan even on a `pull_request` event |

**Permissions:**

No special permissions required. The workflow uses `contents: read` internally.

---

### `spellcheck.yml`

Runs `pyspelling` against a project's spellcheck config. The consumer must commit a pyspelling config at `config` that defines the matrix entry named by `name`.

```yaml
# In your app repository: .github/workflows/ci.yml
jobs:
  spellcheck:
    uses: tnoff/github-workflows/.github/workflows/spellcheck.yml@v1
```

**Inputs:**

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `name` | ❌ | `Markdown` | `pyspelling --name` (the matrix entry in the config) |
| `config` | ❌ | `.spellcheck/spellcheck.yml` | Path to the pyspelling config |
| `aspell_packages` | ❌ | `aspell aspell-en` | apt packages providing the dictionaries pyspelling needs |
| `runner_labels` | ❌ | `["ubuntu-24.04"]` | Runner labels as JSON array |
| `allow_fork_prs` | ❌ | `true` | Allow fork PRs to run (set `false` for self-hosted runners) |

**Permissions:**

No special permissions required. The workflow uses `contents: read` internally.

---

### `renovate.yml`

Runs self-hosted Renovate against the calling repository, authenticated as the `tnoff-ci` GitHub App rather than a bot account -- an App's access comes from its installation, so the bot needs no write permission on GitHub at all. Self-hosted rather than the Mend GitHub App so each repo's `renovate.json` keeps its own grouping, `minimumReleaseAge`, and automerge scoping. Run it on a schedule.

```yaml
# In your app repository: .github/workflows/renovate.yml
name: Renovate

on:
  schedule:
    - cron: '10 3 * * 6'
  workflow_dispatch:

jobs:
  renovate:
    uses: tnoff/github-workflows/.github/workflows/renovate.yml@v1
    secrets:
      app_client_id: ${{ secrets.CI_APP_CLIENT_ID }}
      app_private_key: ${{ secrets.CI_APP_PRIVATE_KEY }}
```

**Inputs:**

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `runner_labels` | ❌ | `["ubuntu-24.04"]` | Runner labels as JSON array |
| `log_level` | ❌ | `info` | Renovate `LOG_LEVEL` (`debug` when diagnosing a run) |
| `allowed_commands` | ❌ | `["^bash ci/renovate-terraform-docs\\.sh$"]` | JSON array of regexes allowlisting repo-level `postUpgradeTasks` commands. A repo's own `renovate.json` cannot authorize its own commands -- the allowlist has to live in this self-hosted config |
| `timeout_minutes` | ❌ | `30` | Backstop, not a budget, for a wedged run. Renovate itself finishes in 1.5-12 min across these repos |

**Secrets:**

| Secret | Required | Description |
|--------|----------|-------------|
| `app_client_id` | ✅ | Client ID of the `tnoff-ci` GitHub App (`CI_APP_CLIENT_ID`) |
| `app_private_key` | ✅ | Private key PEM of the `tnoff-ci` GitHub App (`CI_APP_PRIVATE_KEY`) |

**Permissions:**

No extra permissions to grant in the calling workflow -- Renovate authenticates using the minted App token, not the caller's `GITHUB_TOKEN`.

---

### `branch-cleanup.yml`

Prunes stale automation branches (`bump/*`, `renovate/*` by default): deletes branches matching an allowlist pattern that are old enough and are not the head branch of any open PR. Anything outside the pattern -- hand-made feature branches, the default branch, protected branches -- is never touched. Safe by construction: deleting a throwaway automation branch is reversible, since the job that owns it just re-creates it on the next run. Run it on a schedule, alongside Renovate.

```yaml
# In your app repository: .github/workflows/renovate.yml
jobs:
  branch-cleanup:
    uses: tnoff/github-workflows/.github/workflows/branch-cleanup.yml@v1
    with:
      dry_run: false
```

**Inputs:**

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `runner_labels` | ❌ | `["ubuntu-24.04"]` | Runner labels as JSON array |
| `branch_pattern` | ❌ | `^(bump\|renovate)/` | Extended regex of branch names eligible for deletion |
| `age_days` | ❌ | `30` | Minimum age in days (by last commit) before a branch is eligible |
| `dry_run` | ❌ | `true` | Log candidates without deleting |

**Permissions:**

The workflow needs `contents: write` (to delete refs) and `pull-requests: read` (to find open PRs' head branches) internally; the default `GITHUB_TOKEN` covers both, no extra grant needed in the calling workflow.

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

### `check-workflow-contracts.yml`

Resolves every `uses: <owner>/<repo>/.github/workflows/<file>@<sha>` in the repo and checks the passed `with:` / `secrets:` keys against what the callee declares **at that pinned SHA**. Fails on an undeclared key, a missing required one, or a ref that cannot be resolved. Local `./` calls are skipped — they resolve against the caller's own commit, which `actionlint` already validates.

Worth understanding why this is separate from every other check: a workflow-call contract mismatch fails at **startup**. No job is created, no check reports, and no `workflow_run` event fires, so neither the PR checks list nor `notify-failure.yml` can show it — `gh pr checks` says "no checks reported" rather than showing a failure. Between 2026-09-04 and 2026-09-08 that cost 26 dead `Release` runs across 9 repos, from a single upstream secret rename that an automated pin bump carried into consumers.

Add it to CI in every repo that pins a workflow from here. It is the only check that reads both sides of the contract.

```yaml
# In your app repository: .github/workflows/ci.yml
jobs:
  contracts:
    uses: tnoff/github-workflows/.github/workflows/check-workflow-contracts.yml@v1
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
| `violations_found` | `true` if any contract mismatch was detected |

**Permissions:**

`contents: read`. Reads each callee through the default `GITHUB_TOKEN`, which is enough while `github-workflows` is public.

**Note:** renaming an input or secret here is a contract change with every consumer, and Renovate's digest PR will move the pin without renaming the caller's key. Rename and re-pin in the same commit, or not at all.

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
