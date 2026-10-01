# Reusable workflows

`.github/workflows/` here is the CI and release surface for the fleet. GitHub
Actions is the only CI; the former `gitlab/` templates were deleted on
2026-09-07. Every workflow with a `workflow_call` trigger is a callable
building block, and its exact `inputs` / `secrets` / `outputs` are documented
in a generated page under `workflows/` (linked below). This page covers what
those pages cannot: how the workflows are consumed, the cross-repo contracts,
and the workflows that are not callable.

## Calling a workflow

Consumers pin a **full commit SHA**, and Renovate (`github-actions` manager)
moves the pin. There are no floating `@v1` / `@v0` tags -- only release tags
`v0.0.N` (cut by `self-tag.yml` from `VERSION`).

```yaml
jobs:
  pre-commit:
    uses: tnoff/github-workflows/.github/workflows/pre-commit.yml@<40-char-sha>
```

Rules that follow from SHA pinning:

- An input, secret, or output change that is not backwards compatible breaks
  consumers the moment Renovate bumps the pin. Prefer a new input with a
  default, or a new file, and rename a key and its callers in the same commit.
- A mismatch between a caller's `with:` / `secrets:` and the callee fails at
  **startup**: no job, no check, no `workflow_run` event. Add
  [`check-workflow-contracts`](workflows/check-workflow-contracts.md) to CI in
  every repo that pins a workflow from here; it reads both sides of the
  contract at the pinned SHA. `startup-failure-sweep.yml` (below) is the
  backstop for anything that slips through.
- `check-action-pins` and the `check-action-sha-pin` pre-commit hook enforce
  that every `uses:` is a 40-character SHA.
- Every callable workflow takes `runner_labels` (JSON array, default
  `["ubuntu-24.04"]`). Those with an `allow_fork_prs` input default to
  skipping fork PRs, so they never run untrusted code with the caller's
  secrets.

## Catalogue

Per-workflow inputs, secrets and outputs are on the linked generated pages.
"Permissions" is what the *calling job* must grant; everything else uses
`contents: read` internally.

| Area | Workflow | What it does | Caller permissions |
|---|---|---|---|
| Images | [`docker-push`](workflows/docker-push.md) | Build and push to OCIR under a moving tag (`latest`, or `tag_override`) and an immutable short-SHA tag, one digest. Registry, namespace and repo name are plain inputs (a job output containing secret material is silently blanked by GitHub) | none |
| Images | [`docker-build-check`](workflows/docker-build-check.md) | PR-time build with no push, then a secret scan of the built image | none |
| Images | [`trigger-bump-dispatch`](workflows/trigger-bump-dispatch.md) | After a push, ask docker-apps to rewrite its image pin (see [bump contract](#image-bump-contract)) | none |
| Images | [`ocir-push`](workflows/ocir-push.md) | Legacy image push driven by a `VERSION` file and OCI secrets; superseded by `docker-push` | none |
| Release | [`bump-version`](workflows/bump-version.md) | Commit a version bump onto a PR branch; idempotent, skips fork PRs, peels its own prior bump (`X-Auto-Bump: version` trailer) on rebase | none (App token) |
| Release | [`tag`](workflows/tag.md) | Create a git tag from `VERSION` or a JSON file; no-op if the tag exists. Pushes as the `tnoff-ci` App because the default token triggers no downstream run | none (App token) |
| Release | [`release`](workflows/release.md) | GitHub release for a tag `tag` just created, notes from the matching `CHANGELOG.md` section | `contents: write` |
| Release | [`assemble-changelog`](workflows/assemble-changelog.md) | Fold `changelog.d/*.md` fragments into `CHANGELOG.md` and push; pairs with `tag`'s `gate_on_fragments` | none (App token) |
| Quality | [`pre-commit`](workflows/pre-commit.md) | Run all hooks (`language: system` hooks need their binary installed another way; `docker_image` hooks work) | none |
| Quality | [`tox`](workflows/tox.md) | Discover `py<X><Y>` tox envs into a matrix plus a diff-cover gate; the trailing `result` job is the one stable name to require in a ruleset | none |
| Quality | [`spellcheck`](workflows/spellcheck.md) | `pyspelling`; the caller commits the config | none |
| Quality | [`trufflehog`](workflows/trufflehog.md) | Verified-secret scan: PR commits on `pull_request`, full history otherwise | none |
| Quality | [`codeql`](workflows/codeql.md) | CodeQL SAST, results to the caller's code-scanning alerts (private repos need Advanced Security) | `security-events: write` |
| Quality | [`coverage-store`](workflows/coverage-store.md) / [`coverage-check`](workflows/coverage-check.md) | Legacy pytest-coverage baseline artifact and PR comparison (diff-cover gate); `tox` covers this now | `check`: `actions: read`, `pull-requests: write` |
| Quality | [`check-pr-labels`](workflows/check-pr-labels.md) | Gate a job on PR labels / merged state | `pull-requests: read` |
| Guards | [`check-action-pins`](workflows/check-action-pins.md) | Fail on any `uses:` not pinned to a 40-char SHA | none |
| Guards | [`check-workflow-contracts`](workflows/check-workflow-contracts.md) | Validate pinned reusable-workflow calls against the callee | none |
| Automation | [`renovate`](workflows/renovate.md) | Self-hosted Renovate as the `tnoff-ci` App (keeps per-repo `renovate.json`); run on a schedule | none (App token) |
| Automation | [`branch-cleanup`](workflows/branch-cleanup.md) | Prune stale automation branches (see [runbook](#branch-cleanup)) | none |
| Automation | [`discord-notify`](workflows/discord-notify.md) | Failure embed to a Discord webhook. `source_*` inputs exist because a reusable workflow runs inside the caller's run, so `github.run_id` etc. describe the caller; set them when reporting on a run that already finished | none |
| Docs | [`techdocs-publish`](workflows/techdocs-publish.md) | Build mkdocs with `@techdocs/cli` and publish to the TechDocs S3 bucket (see [contract](#techdocs-publish-contract)) | none |

Most callers chain the release workflows:

```yaml
jobs:
  tag:
    uses: tnoff/github-workflows/.github/workflows/tag.yml@<sha>
    secrets:
      app_client_id: ${{ secrets.CI_APP_CLIENT_ID }}
      app_private_key: ${{ secrets.CI_APP_PRIVATE_KEY }}
  release:
    needs: tag
    permissions:
      contents: write
    uses: tnoff/github-workflows/.github/workflows/release.yml@<sha>
    with:
      version: ${{ needs.tag.outputs.version }}
      tag_created: ${{ needs.tag.outputs.tag_created }}
```

## Image bump contract

A producer repo's `docker-push` followed by `trigger-bump-dispatch` fires a
`repository_dispatch` of type `bump-image-pin` at `tnoff/docker-apps`, whose
`bump-image-pin.yml` rewrites the image's pin and opens a PR. (The catalog
models this as the `image-bump` API.)

```yaml
  trigger-bump:
    needs: push                    # the docker-push job
    uses: tnoff/github-workflows/.github/workflows/trigger-bump-dispatch.yml@<sha>
    with:
      bump_source: my-app
      image: ${{ needs.push.outputs.image }}
      image_tag: ${{ needs.push.outputs.secondary_tag }}
    secrets:
      app_client_id: ${{ secrets.CI_APP_CLIENT_ID }}
      app_private_key: ${{ secrets.CI_APP_PRIVATE_KEY }}
```

- `bump_source` is **not a free-form label**. docker-apps maps it to an image
  name (the `name:` entry in its `images/kustomization.yaml`) and a new
  producer needs a matching entry there. `image` is only recorded; the image
  name is resolved from `bump_source`.
- The `tnoff-ci` App must be installed on both the producer and the target
  repo (`target_repo`, default `tnoff/docker-apps`); the token is minted for
  the target.
- A failed dispatch only warns by default (`fail_on_error: false`), since the
  image is already pushed.
- Details of the receiving side are in the docker-apps TechDocs
  (image promotion).

## TechDocs publish contract

Backstage runs with `techdocs.builder: external`: the backend only reads from
the S3-compatible bucket, so each repo's CI must build and publish.
`techdocs-publish` does that on a GitHub-hosted runner (which has Docker, as
`techdocs-cli generate` needs). A consumer needs:

- `mkdocs.yml` (with `plugins: [techdocs-core]`) and a `docs/` directory, and
  `backstage.io/techdocs-ref: dir:.` on its `catalog-info.yaml` component;
- a workflow triggered on `push` to `main` with `paths: ['docs/**',
  'mkdocs.yml', 'catalog-info.yaml']` (plus the workflow's own file),
  `concurrency: {group: techdocs-publish, cancel-in-progress: false}`;
- `entity_ref` as `<namespace>/<Kind>/<name>`, case-sensitive
  (e.g. `default/Component/github-workflows`);
- the five `TECHDOCS_S3_*` secrets (access key id, secret key, bucket name,
  endpoint, region), passed through explicitly. They are fleet-wide action
  secrets provisioned by terraform.

This repo's own copy is `self-techdocs-publish.yml`.

## Branch cleanup

`bump-image-pin.yml` and Renovate push throwaway branches (`bump/*`,
`renovate/*`). "Delete branch on merge" only fires on merge, so branches whose
PR was superseded or closed pile up. `branch-cleanup` deletes a branch only
when **all** hold: the name matches `branch_pattern` (default
`^(bump|renovate)/`), it is not protected or the default branch, it is not the
head of an open PR, and its last commit is older than `age_days` (default 30).
The allowlist is the safety guarantee: hand-made branches are never
candidates, and deleting an automation branch self-heals because the owning job
re-creates it.

`dry_run` defaults to **true**, which only logs `would delete:` lines. To
adopt it in a repo, call it from the scheduled workflow that already runs
Renovate, read one dry run's log, then set `dry_run: false`:

```yaml
  branch-cleanup:
    uses: tnoff/github-workflows/.github/workflows/branch-cleanup.yml@<sha>
    with:
      dry_run: false
```

The default `GITHUB_TOKEN` is enough (`contents: write`, `pull-requests: read`
are set inside the workflow).

## Workflows that are not callable

| File | Purpose |
|---|---|
| `notify-failure.yml` | Per-repo `workflow_run` notifier template: Discord alert when any workflow on a non-PR event fails. Must exist on a repo's default branch to fire; each consumer carries its own copy |
| `startup-failure-sweep.yml` | Hourly poll of every repo the `tnoff-ci` App can see for `startup_failure` runs and failed notifiers, which emit no event. Single instance, lives here |
| `fleet-mirror.yml` | Hourly push of GitHub `main` to the frozen GitLab copies (read-only history); never force-pushes |
| `self-ci.yml`, `self-scheduled.yml`, `self-tag.yml`, `self-techdocs-publish.yml` | This repo's own PR checks, weekly Renovate, tagging and TechDocs. They call the library through local `./` paths so a PR is tested with its own edits |

Scheduled GitHub cron slots are frequently dropped, so "hourly" workflows
are best-effort.

## Changing this repo

See [DEVELOPMENT.md](DEVELOPMENT.md) for local linting and the generated
reference pages, and [AGENTS.md](AGENTS.md) for the compatibility rules.
