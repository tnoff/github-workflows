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

**Reference:** full `inputs`/`secrets`/`outputs` documentation, generated from this workflow's `on.workflow_call` block: [`docs/workflows/ocir-push.md`](docs/workflows/ocir-push.md)

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

**Reference:** full `inputs`/`secrets`/`outputs` documentation, generated from this workflow's `on.workflow_call` block: [`docs/workflows/docker-build-check.md`](docs/workflows/docker-build-check.md)

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

**Reference:** full `inputs`/`secrets`/`outputs` documentation, generated from this workflow's `on.workflow_call` block: [`docs/workflows/docker-push.md`](docs/workflows/docker-push.md)

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

**Reference:** full `inputs`/`secrets`/`outputs` documentation, generated from this workflow's `on.workflow_call` block: [`docs/workflows/tag.md`](docs/workflows/tag.md)

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

**Reference:** full `inputs`/`secrets`/`outputs` documentation, generated from this workflow's `on.workflow_call` block: [`docs/workflows/release.md`](docs/workflows/release.md)

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

**Reference:** full `inputs`/`secrets`/`outputs` documentation, generated from this workflow's `on.workflow_call` block: [`docs/workflows/assemble-changelog.md`](docs/workflows/assemble-changelog.md)

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

**Reference:** full `inputs`/`secrets`/`outputs` documentation, generated from this workflow's `on.workflow_call` block: [`docs/workflows/bump-version.md`](docs/workflows/bump-version.md)

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

**Reference:** full `inputs`/`secrets`/`outputs` documentation, generated from this workflow's `on.workflow_call` block: [`docs/workflows/trigger-bump-dispatch.md`](docs/workflows/trigger-bump-dispatch.md)

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

**Reference:** full `inputs`/`secrets`/`outputs` documentation, generated from this workflow's `on.workflow_call` block: [`docs/workflows/check-pr-labels.md`](docs/workflows/check-pr-labels.md)

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

**Reference:** full `inputs`/`secrets`/`outputs` documentation, generated from this workflow's `on.workflow_call` block: [`docs/workflows/discord-notify.md`](docs/workflows/discord-notify.md)

The `source_*` overrides exist because a reusable workflow runs **inside the caller's run**: `github.run_id`, `github.workflow` and `github.repository` all describe the caller. That is right when a job reports its own failure, and wrong when a workflow reports on a run that already finished — every field would name the reporter. `notify-failure.yml` and `startup-failure-sweep.yml` both set them.

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

**Reference:** full `inputs`/`secrets`/`outputs` documentation, generated from this workflow's `on.workflow_call` block: [`docs/workflows/techdocs-publish.md`](docs/workflows/techdocs-publish.md)

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

**Reference:** full `inputs`/`secrets`/`outputs` documentation, generated from this workflow's `on.workflow_call` block: [`docs/workflows/coverage-store.md`](docs/workflows/coverage-store.md)

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

**Reference:** full `inputs`/`secrets`/`outputs` documentation, generated from this workflow's `on.workflow_call` block: [`docs/workflows/coverage-check.md`](docs/workflows/coverage-check.md)

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

**Reference:** full `inputs`/`secrets`/`outputs` documentation, generated from this workflow's `on.workflow_call` block: [`docs/workflows/tox.md`](docs/workflows/tox.md)

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

**Reference:** full `inputs`/`secrets`/`outputs` documentation, generated from this workflow's `on.workflow_call` block: [`docs/workflows/pre-commit.md`](docs/workflows/pre-commit.md)

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

**Reference:** full `inputs`/`secrets`/`outputs` documentation, generated from this workflow's `on.workflow_call` block: [`docs/workflows/trufflehog.md`](docs/workflows/trufflehog.md)

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

**Reference:** full `inputs`/`secrets`/`outputs` documentation, generated from this workflow's `on.workflow_call` block: [`docs/workflows/spellcheck.md`](docs/workflows/spellcheck.md)

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

**Reference:** full `inputs`/`secrets`/`outputs` documentation, generated from this workflow's `on.workflow_call` block: [`docs/workflows/renovate.md`](docs/workflows/renovate.md)

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

**Reference:** full `inputs`/`secrets`/`outputs` documentation, generated from this workflow's `on.workflow_call` block: [`docs/workflows/branch-cleanup.md`](docs/workflows/branch-cleanup.md)

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

**Reference:** full `inputs`/`secrets`/`outputs` documentation, generated from this workflow's `on.workflow_call` block: [`docs/workflows/check-action-pins.md`](docs/workflows/check-action-pins.md)

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

**Reference:** full `inputs`/`secrets`/`outputs` documentation, generated from this workflow's `on.workflow_call` block: [`docs/workflows/check-workflow-contracts.md`](docs/workflows/check-workflow-contracts.md)

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
