# Reusable workflows

`.github/workflows/` here is the CI and release surface for the fleet. GitHub
Actions is the only CI; the former `gitlab/` templates were deleted on
2026-09-07. Every workflow with a `workflow_call` trigger is a callable
building block, and its exact `inputs` / `secrets` / `outputs` are documented
in a generated page under `workflows/` (linked below). This page covers what
those pages cannot: how the workflows are consumed, the cross-repo contracts,
and the workflows that are not callable.

## Calling a workflow

Consumers pin a **full commit SHA** with a trailing comment naming the
workflow's release tag, and Renovate moves the pin (see
`renovate/default-github.json`). There are no floating `@v1` / `@v0` tags.

Every workflow is versioned **independently**. Its version lives in
`versions/<workflow>.version`, you raise it in the PR that changes the
workflow (`self-ci.yml` fails the PR if you forget), and `self-release.yml`
tags it `<workflow>-vX.Y.Z` (e.g. `docker-push-v1.3.0`) on merge. A change to
`tox.yml` therefore bumps only `tox`, and only the repos that call `tox.yml`
get a Renovate PR. A new reusable workflow starts at `1.0.0`.

```yaml
jobs:
  pre-commit:
    uses: tnoff/github-workflows/.github/workflows/pre-commit.yml@<40-char-sha>  # pre-commit-v1.0.0
```

A pin with no version comment still works but is tracked the old way, to the
head of `main`, and so is bumped by every commit here. Add the comment.

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
| Release | [`bump-version`](workflows/bump-version.md) | Commit a version bump onto a PR branch; idempotent, skips fork PRs, peels its own prior bump (`X-Auto-Bump: version` trailer) on rebase. One `version_file`, or many via `version_files_command` (the consumer prints which files this PR needs bumped; all land in one commit) | none (App token) |
| Release | [`tag`](workflows/tag.md) | Create a git tag from `VERSION` or a JSON file; no-op if the tag exists. Pushes as the `tnoff-ci` App because the default token triggers no downstream run | none (App token) |
| Release | [`release`](workflows/release.md) | GitHub release for a tag `tag` just created, notes from the matching `CHANGELOG.md` section | `contents: write` |
| Release | [`assemble-changelog`](workflows/assemble-changelog.md) | Fold `changelog.d/*.md` fragments into `CHANGELOG.md` and push; pairs with `tag`'s `gate_on_fragments`. Several packages with their own version file and changelog fold in one commit via `version_files_command` | none (App token) |
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

## Changelog fragments and versions

`bump-version` (with `bump_changelog: true`) writes a `changelog.d/` fragment on
a PR; `assemble-changelog` folds the fragments into `CHANGELOG.md` on `main`;
`tag` (with `gate_on_fragments: true`) defers until the fold has run.

- **A fragment needs a `VERSION` bump in the same PR.** Folding files the
  fragments under the version in `VERSION`. If that version already has a
  `## [X]` section, `assemble-changelog` fails the job rather than append a
  second one: `tag` would find the tag present and skip, `release` would skip
  with it, and every job would stay green while the change ships under the
  next tag with notes filed under the old one. It fails instead of
  auto-bumping because choosing the next version is the author's call.
- A fold push that fails and is re-run after
  another PR bumped `VERSION` files the still-pending fragments under the newer
  version, leaving a gap in the headings (for example 2.5.78 then 2.5.80, no
  `v2.5.79`). No content is lost, and images are tagged by commit SHA, so
  nothing dangles. Compare the `## [` headings with `git tag` to spot it.
- Renovate PRs only cut a release when their branch starts with `renovate/dev-`
  (see [Renovate presets](#renovate-presets)); consumers gate `bump-version` on
  that prefix. A Renovate PR on any other branch name skips `bump-version`
  silently: the job shows `skipped`, the PR is otherwise green, and it merges
  without a `VERSION` bump or fragment.

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

## Renovate presets

`renovate/*.json` are shared presets, extended from a consumer's `renovate.json`
as `github>tnoff/github-workflows//renovate/<name>`. They carry **no ref**, so
Renovate resolves them from `main` at run time: a preset edit is live for every
consumer on its next run, unlike a workflow edit, which waits for the SHA pin to
move.

| Preset | Use |
|---|---|
| `default-github` | Fleet defaults, including the `tnoff/github-workflows` pin tracker. A bare-SHA `uses:` gets no updates from the built-in `github-actions` manager, so the regex manager here is what keeps those pins moving |
| `python` | Python repos: branch prefixes, grouping |
| `no-automerge` | Extend **last** in repos without a ruleset (private, no required checks). A top-level `"automerge": false` loses to the more specific preset `packageRules`, so it has to be a catch-all rule listed after them |
| `default` | Legacy GitLab-era preset, kept for repos not yet moved |

Rules that are not visible from the JSON:

- **The branch prefix decides whether an update releases.** `python.json` puts
  every `pep621`/`dockerfile` update under `dev-` (consumers run `bump-version`
  only for `renovate/dev-*`, which bumps `VERSION`, writes a fragment and cuts a
  release) and test, lint and build tooling under `test-`, which never releases.
  A test dependency that falls through the list is released as a runtime change,
  so match tooling by glob (`pytest-*`, `tox-*`, `types-*`) and list the `test-`
  rule **last**: `additionalBranchPrefix` is replaced by a later matching rule,
  not concatenated.
- **The `dev-` prefix only covers `pep621` and `dockerfile`.** Updates from any
  other manager (a `custom.regex` pin on a tarball URL, `github-actions`) land
  on a plain `renovate/<dep>` branch, so `bump-version` never runs for them. If
  such a pin is a runtime dependency that should cut a release, give it its own
  rule in the consumer's `renovate.json`:

  ```json
  {
    "matchManagers": ["custom.regex"],
    "matchPackageNames": ["<owner>/<dep>"],
    "additionalBranchPrefix": "dev-"
  }
  ```

  The symptom is a Renovate PR whose `Bump version` job is `skipped` and whose
  head branch lacks `dev-`. Example: dappertable in `public-transit`
  ([#206](https://github.com/tnoff/public-transit/pull/206)). Renaming the
  branch makes Renovate open a new PR; the old one has to be closed by hand.
- `prHourlyLimit` and `prConcurrentLimit` are `0` on purpose.
  `config:recommended` caps at 2 per hour and 10 open, and the perennial
  workflow-pin PR takes one slot, so a repo with a backlog silently never
  reached the deps at the end of the queue (yt-dlp sat unbumped for weeks).
- To see what Renovate would name or group an update, run
  `RENOVATE_PLATFORM=local RENOVATE_DRY_RUN=full LOG_LEVEL=debug npx renovate`
  in a checkout: no token, no PRs. Judge grouping by the branch name, not the PR
  title (a group is titled after its only member that run).
- The `tnoff-ci` App needs **Commit statuses: Read and write**. Renovate posts
  a `renovate/stability-days` status on any branch with a `minimumReleaseAge`
  (the cloud SDK group has one), and when that POST is refused it reports
  `repository-changed` and stops the run partway through the repo -- a 403
  surfaces as the misleading "Repository has changed during renovation -
  aborting". The cause only shows at `log_level: debug`
  (`Caught error setting branch status - aborting`, with
  `x-accepted-github-permissions: statuses=write` on the 403). A recreated App
  or a narrowed permission set brings it back; new permissions also have to be
  accepted on the installation before they apply
  ([#104](https://github.com/tnoff/github-workflows/issues/104)).
  `renovate.yml` fails the job on this result, so it no longer passes silently.

## Tox repos

`tox.yml` runs `tox -e pyXY` once per interpreter in the matrix, so every line
in a shared `[testenv]` `commands` block runs once per Python. Gate static
analysis to the newest interpreter with the factor prefix so it runs once
(`pytest` still runs on every version):

```ini
[testenv]
commands =
    py314: pylint mypkg/
    py314: bandit -r mypkg/
    pytest --cov=mypkg tests/
```

`py314` is also the leg whose coverage `diff-cover` reads. Bump the prefix with
the newest `env_list` entry.

## Workflows that are not callable

| File | Purpose |
|---|---|
| `notify-failure.yml` | Per-repo `workflow_run` notifier template: Discord alert when any workflow on a non-PR event fails. Must exist on a repo's default branch to fire; each consumer carries its own copy |
| `startup-failure-sweep.yml` | Hourly poll of every repo the `tnoff-ci` App can see for `startup_failure` runs and failed notifiers, which emit no event. Single instance, lives here |
| `fleet-mirror.yml` | Hourly push of GitHub `main` to the frozen GitLab copies (read-only history); never force-pushes |
| `self-ci.yml`, `self-scheduled.yml`, `self-release.yml`, `self-techdocs-publish.yml` | This repo's own PR checks, weekly Renovate, per-workflow releases and TechDocs. They call the library through local `./` paths so a PR is tested with its own edits |

Scheduled GitHub cron slots are frequently dropped, so "hourly" workflows
are best-effort.

### What reports a failure

- The required `CI result` check guards **pull requests only**. Workflows that
  run on `push` to `main` or on a schedule (`release`, applies) are outside it,
  and their only reporter is `notify-failure.yml`.
- `notify-failure.yml` fires for `failure` conclusions on non-PR events and
  excludes its own name, so a broken notifier is silent. The sweep reports it.
- A `startup_failure` run creates no job and no `workflow_run` event, so no
  event-driven notifier can see it. Polling is the only mechanism; "nothing is
  failing" and "nothing is reporting" are different claims.
- The sweep's App token needs `Actions: read`. Public repos answer
  `/actions/runs` to any token, so a missing permission shows up only on the
  private repos, and the sweep fails hard naming it rather than skipping them.
- Scheduled crons drop most slots (74% measured over 8 days), so the sweep's
  lookback is 8 hours, wider than the worst observed gap, with a high-water
  mark to suppress duplicates.

## Changing this repo

See [DEVELOPMENT.md](DEVELOPMENT.md) for local linting and the generated
reference pages, and [AGENTS.md](AGENTS.md) for the compatibility rules.
