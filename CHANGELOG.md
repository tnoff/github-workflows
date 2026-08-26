# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.0.66] - 2026-08-26

### Fixed

- `docker-push.yml`: `registry`, `namespace` and `repo_name` move from **secrets to inputs**. GitHub refuses to set a job output whose value contains secret material, silently leaving it empty — and the image reference is built from all three, so the `image` output came back blank in the calling workflow. The push itself worked; the damage was downstream.
- `trigger-bump.yml`: refuses to fire with an empty `image` or `image_tag`. A GitLab pipeline variable set to an empty string **overrides** the downstream job's own value, so sending `variables[IMAGE_NAME]=` is worse than sending nothing — the bump job failed with `IMAGE_NAME not configured on this job`, an error pointing at `docker-apps` rather than at the producer that sent the blank.
- Found end-to-end on `database-backup`: image pushed fine, `image_tag: 844e62c` came through (it derives from `git rev-parse`), `image:` was empty, and the triggered pipeline on `docker-apps` failed. Consumers must pass the three as inputs and move them from `action_secrets` to `action_variables`.

### Note

- None of the three were ever credentials — a registry host, an object-storage namespace and a repository name. They were masked on GitLab only because GitLab masks broadly. Only `oci_username` and `oci_token` are secret.

## [0.0.65] - 2026-08-26

### Fixed

- `docker-build-check.yml`: the image secret scan **read nothing and passed**. `trufflehog docker --image <name>` treats a bare name as a *registry* reference — "otherwise an image registry is assumed" — so it tried to pull the local-only `build-check:<sha>` tag from Docker Hub, got `UNAUTHORIZED`, scanned `"bytes": 0`, and still exited 0. Fixed with the `docker://` prefix, which points it at the local daemon.
- Caught on the first real image build (`tnoff/database-backup#206`) and reproduced locally: a local-only tag without the prefix gives 0 bytes and exit 0, with the prefix gives 266 chunks and 8.9 MB. A bare `alpine:3` does *not* reproduce it, because that image genuinely exists on Docker Hub and gets pulled — which is why this passed review.
- Added a guard that fails the step when the scan reports 0 bytes. The prefix fixes the known cause, but any future variant resolving to an unreadable image would pass silently again, and a green scan that read nothing is worse than a red one.

## [0.0.64] - 2026-08-26

### Added

- `.github/workflows/trigger-bump.yml`: the last of the 13 GitLab templates. **All templates are now ported.**
- This is the *transitional* shape, deliberately. `docker-apps` is private, does not exist on GitHub, and is scheduled last because it is the Flux source — so every image repo that flips before it still triggers a bump on the GitLab-hosted `docker-apps`. The mechanism is unchanged (a form POST to GitLab's pipeline trigger API); it just runs from an Action. When `docker-apps` flips this becomes a `repository_dispatch` and the GitLab trigger token goes away. Porting it twice is cheaper than blocking every image repo behind the last one.

### Degraded until `docker-apps` flips

- `SOURCE_PROJECT_ID` and `SOURCE_SHA` are **omitted**, so the bump MR loses its "Source MR" back-link and changelog compare link. Once a producer is GitHub-canonical its commits no longer exist on the stale GitLab copy, so those lookups would query a project ID that cannot resolve the SHA. The downstream job already treats missing values as the documented "producer predates this" path and omits the links, so sending unresolvable values would only buy two failed API calls per bump. The bump itself is unaffected.
- A forward-looking `SOURCE_URL` is sent instead — current `docker-apps` ignores it harmlessly, and a GitHub-side successor can use it to restore the back-link.

## [0.0.63] - 2026-08-26

### Added

- `.github/workflows/docker-build-check.yml` and `.github/workflows/docker-push.yml`: the Actions counterparts to `/gitlab/buildkit-build-check.yml`, `/gitlab/trufflehog-image.yml` and `/gitlab/buildkit-docker-push.yml`. The bespoke buildkit machinery is dropped rather than ported.

### Removed in the port

- **The in-job buildkitd.** Both GitLab templates started an ephemeral `buildkitd` on a unix socket — which required a privileged pod — and drove it with `buildctl`, because the cluster buildkitd Deployment had been retired so the ci pool could scale to zero. `docker/setup-buildx-action` replaces it.
- **The S3 layer cache, and the ephemeral-storage tuning it forced.** `--export-cache mode=max` writes every intermediate layer to disk before shipping it, which is why those jobs carried `KUBERNETES_EPHEMERAL_STORAGE_REQUEST: 12Gi` / `LIMIT: 18Gi` after a build took a node down. `discord-bot` measured 16.4 GiB — more than a GitHub-hosted runner's ~14 GB, so the GitLab shape would not have fitted at all. The GitHub cache backend has no equivalent local multiplier.
- **The image-handoff bucket.** `build-check` exported a `docker save` tarball to OCI Object Storage keyed by pipeline ID so the separate scan job could fetch it. That existed only because two GitLab jobs are two pods; here the image is already in the local daemon, so build and scan are one job. For `discord-bot` that turns five build jobs plus five scan jobs into five — and job count is what GitHub bills.
- **The base64 wrapping of OCI credentials.** `OCI_USERNAME_64` and friends were encoded because GitLab masking requires single-line values with a restricted character set. GitHub secrets have no such constraint.
- **The double build.** The GitLab push job ran `buildctl` twice, once per tag, because a single build takes one `--output`. `build-push-action` takes a tag list, so the image is built once and both tags share a digest.

## [0.0.62] - 2026-08-26

### Added

- `renovate/no-automerge.json`: a catch-all preset that disables automerge, to be extended **last** so it overrides the automerge rules in `default-github` (the shared reusable-workflow pin) and `python` (the test-dependencies group).
- It exists for repos with no branch ruleset, which on a personal account means every **private** repo: private-repo rulesets require GitHub Pro, so there are no required status checks for GitHub's auto-merge to wait on and a Renovate PR would merge whether or not CI passed. That is strictly worse than the GitLab behaviour it replaces — `only_allow_merge_if_pipeline_succeeds` is true on `docs`, `terraform` and `docker-apps` today.
- Note a top-level `"automerge": false` does **not** work here: `packageRules` are more specific and win over it, so the preset rules would still automerge. It has to be a catch-all `packageRule` applied after them.

## [0.0.61] - 2026-08-25

### Added

- `renovate/default-github.json`: fleet Renovate defaults for repos that have flipped to GitHub-canonical, parallel to `renovate/default.json`. Both have to coexist until the migration finishes, so this is a second preset rather than an edit to the first.
- Found while flipping `dappertable`: **17 of 26 repos extend the GitLab-hosted presets** (`gitlab>tnoff-projects/github-workflows//renovate/…`). The pilot was one of the nine that do not, which is why it never surfaced. Flipped repos extend `github>tnoff/github-workflows//renovate/default-github` instead, so nothing on the GitHub side needs GitLab credentials to resolve its own config.

### Changed from the GitLab preset

- `gitIgnoredAuthors` becomes `github-actions[bot]@users.noreply.github.com`. Without this Renovate's modified-branch guard sees the bump-version commit as a foreign edit and refuses to rebase the branch.
- The shared-pin automerge rule is retargeted from the `git-refs` datasource and `https://gitlab.com/tnoff-projects/github-workflows` to the built-in `github-actions` manager and `tnoff/github-workflows` — both the datasource and the package name differ on GitHub.
- `hostRules` capping github.com to `concurrentRequestLimit: 2` is **absent**. It existed only to stop the terraform manager's provider fan-out (oracle/oci ships 13 platform zips at ~65MiB each) OOMKilling a 1500Mi build container on the self-hosted runner; a hosted runner has 16GB, so the cap now only costs wall-clock.
- The packageRule disabling `gitlabci-include` is **absent** — that manager is never enabled here.
- The `.gitlab-ci.yml` include-ref `customManager` is **absent**, superseded by the built-in `github-actions` manager. The terraform-modules `.tf` regex carries over unchanged, since that repo is still GitLab-hosted and still SHA-pinned.
- `renovate/python.json` is unchanged and shared by both: its content is platform-neutral, and the `dev-` prefix stays load-bearing because the ported `bump-version` keys on `renovate/dev-` exactly as the GitLab job keyed on the same prefix.

## [0.0.60] - 2026-08-25

### Added

- `.github/workflows/spellcheck.yml`, `tag.yml`, `release.yml` and `assemble-changelog.yml`: the remaining templates `dappertable` consumes. With `tox.yml` from 0.0.59 that completes all 9 of its includes.
- `tag.yml` replaces the dotenv artifact handoff — `build.env` carrying VERSION / TAG_CREATED / TAG_EXISTS to the release job — with workflow outputs. `release.yml` replaces 25 lines of curl + jq + HTTP-code handling against the GitLab releases API with one `gh release create`.
- `spellcheck.yml` drops `$CI_SPELLCHECK_IMAGE` along with the rest of `ci-base-images`: aspell from apt and pyspelling from pip take seconds on a hosted runner and need no registry, cleanup CronJob or pull secret.
- The changelog-format logic in `assemble-changelog.yml` is carried over unchanged — the awk that turns a fragment paragraph into a bullet, and the awk that splices the new section above the first `## [` heading. Both encode bugs already paid for, and neither is about the platform.

### Note

- `assemble-changelog.yml` pushes to the **default branch**, which the fleet's rulesets now protect. Its `push_token` must belong to an identity the ruleset bypasses — they bypass the repository-admin role only, so an admin PAT works and a write-scoped bot token is rejected at the push rather than by the API call before it. It must also not be the default `GITHUB_TOKEN`: the fragment-gating design depends on the fold push triggering a follow-up run, and a `GITHUB_TOKEN` push triggers nothing — so the tag is never cut and the release never happens, with every job green.

## [0.0.59] - 2026-08-25

### Added

- `.github/workflows/tox.yml`: Python tox matrix plus a diff-cover gate on changed lines, the Actions counterpart to `/gitlab/tox-pipeline.yml`. Three jobs — `discover` reads `tox -l` and emits a JSON array, `tox` consumes it via `fromJSON()` as a matrix, and `diff-cover` gates the highest interpreter's `coverage.xml` against the PR base branch.
- It is roughly a third the size of the GitLab template, because most of that template is workarounds that do not survive the move. The dynamic parent→child pipeline existed only because GitLab cannot take a YAML list as a job-level variable, so the matrix had to be generated as YAML, published as an artifact and triggered as a child pipeline. The ~60-line S3 cache of `.tox/` existed because self-hosted runners had no free cache, and it carried an OCI SigV4 workaround per line — `AWS_DEFAULT_REGION` vs `AWS_REGION`, path addressing for the underscore bucket, `when_required` checksums, and staging the tarball to a file because streaming forced chunked signing that OCI rejects. `actions/cache` replaces all of it. `dependencies: []` existed to stop GitLab pulling 1.27 GB of unrelated artifacts, and the re-emitted `default: retry:` block existed because child pipelines do not inherit it.

## [0.0.58] - 2026-08-25

### Added

- `.github/workflows/renovate-auto-approve.yml`: approves (and optionally auto-merges) Renovate's own PRs, so CODEOWNERS plus a ruleset with `require_code_owner_review` stays satisfiable. GitHub does not permit a PR author to approve their own PR, so a bot-authored PR needs an approval from a different code owner before automerge can proceed.
- Deliberately not a port of `dependabot-auto-approve.yml`. That one is built on `dependabot/fetch-metadata` for the semver level; Renovate has no equivalent action and encodes the update class in the branch name via `additionalBranchPrefix`, so the branch pattern is the filter instead.
- Two failure modes are guarded rather than documented-and-hoped: the workflow refuses to run if `approval_token` belongs to the PR author (the self-approval case, which is what happens if it is handed Renovate's own token), and the header states that callers must keep `synchronize` in their `pull_request` trigger — rulesets set `dismiss_stale_reviews_on_push`, and `bump-version` pushes to Renovate branches after the PR opens, dismissing the approval. Re-firing on `synchronize` is what makes it converge.

## [0.0.57] - 2026-08-25

### Fixed

- `.github/workflows/trufflehog.yml`: the default `extra_args` no longer passes `--fail`. The action already invokes the CLI with `--fail --no-update --github-actions` and appends `extra_args` after it, and trufflehog's flag parser rejects a repeated flag outright — `flag 'fail' cannot be repeated`. The `--only-verified --fail` default was carried over verbatim from the GitLab template, where the CLI was invoked directly and both flags were ours to supply. Caught by the first real run, `tnoff/MMM-BartTimes#3`.

## [0.0.56] - 2026-08-25

### Added

- `.github/workflows/trufflehog.yml`, `.github/workflows/renovate.yml`, `.github/workflows/branch-cleanup.yml`: GitHub Actions counterparts to the GitLab templates of the same name, as `workflow_call` reusable workflows. These are the first four templates ported for the GitHub-canonical migration, chosen because 15-19 repos each consume them. All actions are pinned to full commit SHAs per `check-action-pins.yml`.
- `renovate.yml` deliberately drops `GITHUB_COM_TOKEN`. On GitLab, Renovate needed a separate github.com token purely for release notes, and an undefined variable expanding to an empty string 401'd every lookup. When the platform *is* GitHub the platform token covers release notes, so the whole failure mode is gone rather than ported.
- `branch-cleanup.yml` needs no PAT: the default `GITHUB_TOKEN` with `contents: write` can delete refs, unlike the GitLab template which required `CLEANUP_TOKEN`.

### Changed

- `.github/workflows/bump-version.yml`: rewritten to match what the GitLab template grew after this tree was last touched in April. It now computes the target version from the *base* branch rather than the branch tip, marks its own commits with an `X-Auto-Bump: version` trailer, and on re-run peels and recomputes that commit against the current base before pushing with `--force-with-lease`. Without the peel a stale bump stacks and is applied away on rebase with no conflict to notice — which matters here because Renovate rebases constantly. Also adds conflict-free changelog fragments (`bump_changelog` / `changelog_dir`) and an optional `git_push_token`; pushing with the default `GITHUB_TOKEN` triggers no downstream workflow, so required checks never report on the bump commit.

## [0.0.55] - 2026-08-18

### Removed

- `gitlab/buildkit-build-check.yml`: the `artifacts:` block is gone. `0.0.54` kept it as a fallback so the include pin could roll through consumer repos in arbitrary order — with `IMAGE_HANDOFF_BUCKET` unset the tarball stayed on disk and uploaded as before. All ten consumers are now on `b6d70f45`, so the fallback has no users. Removing it also clears the `WARNING: <tarball>: no matching files` that the empty artifact upload printed in **every** build job log, which was cosmetic but permanent.

### Changed

- `gitlab/buildkit-build-check.yml`: an unset `IMAGE_HANDOFF_BUCKET` is now a hard error at the top of the upload step, rather than a silent fall-through to a local file. The variable reaches every job pod from the runner's `buildkit-s3-creds` Secret via `envFrom`, so an empty value means the job is not on the `self-hosted` runner or the Secret changed — both worth failing loudly for. Without the `artifacts:` fallback the alternative was a confusing 404 in the downstream scan job, one stage later and further from the cause. The elevated runner (`oke-elevated`) does **not** carry that Secret, but no build-check job targets it — they all run under the `self-hosted` tag.

## [0.0.54] - 2026-08-15

### Changed

- `gitlab/buildkit-build-check.yml`: the docker-save tarball is now handed to the paired `.trufflehog-image` job through OCI Object Storage instead of a GitLab job artifact, and `expire_in` drops from `1 day` to `2 hours`. Those tarballs were the entire GitLab namespace artifact footprint — **13.9 GB of a 14.0 GB rollup**, about 1.27 GB per `discord-bot` MR pipeline across five images — and the scan job is their only consumer: across all ten repos on this template the tarball path appears exactly twice, as `OUTPUT_TARBALL` and as `TRUFFLEHOG_IMAGE_TARBALL`. Nothing publishes from it; `push:image-*` extends `.buildkit-docker-push` with `needs: []` and rebuilds. On the S3 path the local file is removed after upload so the `artifacts:` block stores a few bytes rather than hundreds of MB. **Both paths still work**: when `IMAGE_HANDOFF_BUCKET` is unset the tarball stays put and the artifact behaves exactly as before, which is what makes it safe for Renovate to roll the include pin through consumer repos in arbitrary order.
- `gitlab/buildkit-build-check.yml`: `BUILDKIT_IMAGE` now defaults to `$CI_BUILDKIT_IMAGE` (the pre-baked `ci-buildkit` image — `moby/buildkit:v0.30.0` plus `aws-cli`) rather than the upstream `docker.io/moby/buildkit:v0.30.0` literal. Upstream buildkit ships `buildkitd` and `buildctl` only, so it has no client that can write the bucket. This has to change in the **same** release as the upload logic: `IMAGE_HANDOFF_BUCKET` is set fleet-wide in the runner's `buildkit-s3-creds` Secret, so it cannot distinguish a repo that has the new image from one that does not — the image and the code that needs it must arrive together on a pin bump. The buildkit version pin is unchanged and is now frozen against Renovate in `ci-base-images`: v0.31 sends `aws-chunked` content encoding on the S3 cache export and OCI rejects it with a 501.
- `gitlab/trufflehog-image.yml`: fetches the tarball from `IMAGE_HANDOFF_BUCKET` when the producer put it there, then asserts the file is non-empty before scanning. The fetch deliberately has **no** `2>/dev/null` and **no** `|| true` — this is a secret-scanning gate, so a failed fetch fails the job. A silent skip would leave the pipeline green with nothing scanned, which is worse than the artifact-based status quo. Contrast the `.tox` cache in `tox-pipeline.yml`, which fails soft on purpose because a miss only costs a rebuild. No-op when the variable is unset.
- `gitlab/tox-pipeline.yml`: `.tox-generate` gains `dependencies: []`. It is a bare job in a stage after the build-check stage, so GitLab's default had it downloading artifacts from **every** preceding stage — in `discord-bot` that meant pulling all five image tarballs (~1.27 GB) to run a one-second `tox -l`, **82 seconds of a 145-second job**. Also affects `enheduanna`, `hathor`, `public-transit`, and `oke-security-scanner`. Independent of the handoff change and worth taking on its own.

## [0.0.53] - 2026-08-15

### Removed

- `gitlab/discord-notify.yml`: deleted. The template has no consumers left. Its `failure` type went away fleet-wide when the `notify:*-failure` jobs retired into the Grafana `gitlab-ci-job-failure` alert, and `0.0.52` removed the last straggler (the `assemble-changelog` EXIT trap). Its remaining two types, `mr_opened` and `mr_merged`, are retired here: the `#mr-opened` / `#mr-merged` Discord channels, their webhooks, and the `DISCORD_MR_OPENED_WEBHOOK` / `DISCORD_MR_MERGED_WEBHOOK` group variables are being torn down in `terraform`, and all 20 consumer repos have dropped their `notify:mr-*` jobs and the include. GitLab's own MR list, todos, and email notifications cover what these pings answered. The GitHub-side `.github/workflows/discord-notify.yml` is **unaffected** — it is failure-only and still consumed by GitHub-mirror CI. Consumers pinned to an older `ref:` keep resolving the file at that ref; nothing breaks until they advance the pin, by which point the include is already gone from their config.

## [0.0.52] - 2026-08-15

### Removed

- `gitlab/assemble-changelog.yml`: drop the advisory Discord failure notification (the `_notify_failure` EXIT trap, the `DISCORD_FAILURE_WEBHOOK` variable, and the now-unused `curl` install in `before_script`). Added in `b0c827a` (!68, 2026-07-12) to cover a gap — `assemble-changelog` runs in `.pre`, so when it failed the push-stage `notify:*-failure` jobs were skipped on unmet `needs` and nobody was told. That gap closed when the `gitlab-ci-metrics` Phase 2 alert (`GitLab CI job failed after final retry`) broadened to `type!="check"`: GCPE labels this job `type=maintenance`, so the alert already covers it and routes to the same `#ci-alerts` channel via the `DiscordCI` contact point. The trap was therefore posting a **duplicate** — once immediately, once from Grafana ~5m later — for every failure. It also posted silently (`curl -sf … >/dev/null 2>&1 || true`), which is why it outlived the fleet-wide `notify:*-failure` retirement that removed every other direct CI→Discord sender. Confirmed still firing on `discord-bot` 2026-08-15 (fold push rejected by the pre-receive hook). No consumer action needed beyond advancing the include pin; repos that set `DISCORD_FAILURE_WEBHOOK` explicitly will find it inert. Once all 13 consumers are past this ref, the `DISCORD_BUILD_FAILURE_WEBHOOK` group variable (`terraform` `infra/gitlab.tf`) has no remaining reader and can be retired.

## [0.0.51] - 2026-08-03

### Fixed

- `gitlab/renovate.yml`: default `GITHUB_COM_TOKEN` to `$GITHUB_BOT_TOKEN` instead of `$GITHUB_COM_TOKEN`. `GITHUB_COM_TOKEN` is defined at **no** scope — not group, not project — so GitLab expanded it to an empty string, Renovate presented that empty token to github.com, and github.com returned `401 unauthorized`. 18 of the 22 Renovate repos already override the default in their own `renovate:` job; the remaining stragglers silently ran with a broken github.com token. This is loudest on terraform repos, where the terraform manager resolves terraform core plus every provider via `github-releases`, and merely cosmetic elsewhere (missing release notes in MR bodies). `GITHUB_BOT_TOKEN` is defined at `tnoff-projects` group scope, so consumers inherit it with no per-repo setup. Repos that set `GITHUB_COM_TOKEN` in their own job are unaffected — a job-level variable still wins over the template default. Diagnosed in `terraform-admin!37`; see docs MR !87.

## [0.0.50] - 2026-08-03

### Fixed

- `renovate/default.json`: cap concurrent `github.com` requests at 2 via a `hostRules` entry. The terraform manager's lockfile `updateArtifacts` downloads and unzips **every** platform build of a provider to compute its `h1:` hash, and issues those fetches at the default queue concurrency of 16. For `oracle/oci` — 13 platform zips at ~65MiB each — that parallel fan-out drove the runner's `build` container past its 1500Mi memory limit and it was OOMKilled. The GitLab Kubernetes executor's **attach strategy does not detect a dead build container**, so the job emitted nothing further and burned the full 1h timeout instead of failing. Observed on `terraform-admin`, whose scheduled Renovate job timed out repeatedly: the container's working set was pinned at 1398-1472MiB against the 1500Mi cap and its cgroup metrics vanished ~6min in, while the `helper` container kept reporting for the remaining ~45min.
- `gitlab/renovate.yml`: add `timeout: 30m` to `.renovate`. This is a backstop for the attach-strategy hang above, not a budget — Renovate itself completes in 1.5-12min on these repos. It is deliberately **not** tighter: the pod can sit `Pending` for 8-20min waiting on an A1 ci node to cold-start from zero, and that wait counts against the job timeout, so a 15m cap would false-fire on scale-from-zero. Note `job_execution_timeout` is not in the `stuck_or_timeout_failure` retry class, so a wedged job is capped at one 30m burn rather than retried.

## [0.0.49] - 2026-06-25

### Added

- `gitlab/tox-pipeline.yml`: the generated child pipeline now writes `/etc/pip.conf` from `PIP_INDEX_URL` / `PIP_EXTRA_INDEX_URL` / `PIP_TRUSTED_HOST` before running tox, so pip (including inside tox-created venvs, where env passthrough is unreliable) resolves through a configured index — the Nexus pull-through cache. **With automatic fallback:** pip has no native index failover, so the job TCP-probes `PIP_INDEX_URL` at start — if Nexus is reachable it's used (with pypi as extra-index for fresh releases), and if not, pip.conf points at `PIP_EXTRA_INDEX_URL` (pypi.org) instead, so a Nexus outage degrades CI to "no cache", never "no installs". The probe uses only `python3` (no `curl` dependency). **No-op until `PIP_INDEX_URL` is set**, so this is inert for every consumer until the Nexus CI cutover flips that variable. Applies to both the tox matrix job and the diff-cover job, in both the slim-image and `TOX_BASE_IMAGE` paths.

## [0.0.47] - 2026-06-01

### Added

- `gitlab/spellcheck.yml`: new reusable template exposing `.spellcheck` for running pyspelling against a project's spellcheck config. Inputs: `SPELLCHECK_NAME` (default `Markdown`; consumers using HTML sites override to `html`), `SPELLCHECK_CONFIG` (default `.spellcheck/spellcheck.yml`). Consolidates the inline pyspelling jobs across four in-tree consumers (`dappertable`, `enheduanna`, `eastbay`, `personal-website`).

## [0.0.46] - 2026-06-01

### Added

- `gitlab/tox-pipeline.yml`: new reusable templates exposing `.tox-generate` and `.tox-pipeline` for Python tox matrix testing plus a diff-cover coverage gate. GitLab CI doesn't accept YAML lists as job variables, so `.tox-generate` introspects `tox -l` and writes a child pipeline YAML that `.tox-pipeline` then triggers via `include: artifact:`. Inputs on `.tox-generate`: `TOX_EXTRA_APT` (appended after the default `git` so per-repo extras like discord-bot's `sqlite3 ffmpeg` don't lose `git`), `DIFF_COVER_FAIL_UNDER` (default 100), `DIFF_COVER_COMPARE_BRANCH` (default `origin/main`). The generated child pipeline always pins images as `docker.io/library/python:<X.Y>-slim` so the template works on runtimes that enforce CRI-O `short-name-mode = "enforcing"`. Consolidates the ~70-line copy-pasted heredoc generator across seven in-tree Python repos (`dappertable`, `backup-tool`, `enheduanna`, `hathor`, `public-transit`, `vault-app`, `oke-security-scanner`) plus discord-bot's older hand-rolled matrix.

## [0.0.45] - 2026-06-01

### Added

- `gitlab/buildkit-build-check.yml`: new reusable template exposing `.buildkit-build-check` for MR-time "does the Dockerfile compile" validation. Builds a local image with buildkit (out-of-cluster, no dind) and emits a `docker save` tarball as an artifact so downstream MR jobs (e.g. `.trufflehog-image`) can scan without rebuilding. Same buildkit-via-cluster-service transport as `.buildkit-docker-push` (0.0.44). Inputs: `BUILDKIT_IMAGE` (centralizes the `v0.29.0`/`v0.30.0` drift that had crept into individual repos), `CONTEXT_DIR` / `DOCKERFILE_DIR` / `DOCKERFILE_NAME` / `BUILD_ARGS` / `OUTPUT_NAME` / `OUTPUT_TARBALL`. Default `rules:` runs on every MR with fork-MRs requiring a maintainer to manually trigger. Consolidates the `build-check` / `docker-build` / `validate-docker` jobs that were copy-pasted across eight in-tree consumers.

## [0.0.44] - 2026-06-01

### Added

- `gitlab/buildkit-docker-push.yml`: new reusable template exposing `.buildkit-docker-push` for building OCI images with buildkit (out-of-cluster via `buildctl --addr`, no dind) and pushing `:SHA` and `:latest` tags to OCIR. Emits `IMAGE=<full ref>` to a dotenv artifact so downstream jobs (e.g. `.trigger-bump`) can pick up the reference without re-decoding the `OCI_*_64` CI variables. Same auth mechanism as the removed `.docker-push` (base64-encoded `OCI_USERNAME_64`/`OCI_TOKEN_64`/`OCI_REGISTRY_64`/`OCI_NAMESPACE_64`/`OCI_REPO_NAME_64`). Supports multi-image consumers by overriding `OCI_REPO_NAME_64` per job, plus `DOCKERFILE_NAME` / `DOCKERFILE_DIR` / `CONTEXT_DIR` / `BUILD_ARGS` / `PLATFORM` for build customization. Consolidates the inline buildkit jobs that were copy-pasted across all six in-tree producer repos.

### Removed

- `gitlab/docker-push.yml` (`.docker-push`): removed. The dind-based template had zero in-tree consumers — every producer was running its own inline buildkit-via-cluster-service job that `.buildkit-docker-push` now consolidates. **Breaking** for any external consumer still extending `.docker-push`; migrate to `.buildkit-docker-push` (which expects an out-of-cluster `buildkitd` Deployment rather than dind).

## [0.0.43] - 2026-05-12

### Added

- `gitlab/trigger-bump.yml`: new reusable template exposing `.trigger-bump` for the *producer* side of the cross-project bump-pin flow. Fires `POST /projects/:id/trigger/pipeline` on a downstream repo (e.g. docker-apps) with `BUMP_SOURCE` / `IMAGE_NAME` / `IMAGE_TAG` as `variables[...]` so the downstream pipeline can rewrite the image pin and open an MR. Defaults `TARGET_PROJECT_ID` / `TARGET_TRIGGER_TOKEN` to `$DOCKER_APPS_PROJECT_ID` / `$DOCKER_APPS_TRIGGER_TOKEN` (the names terraform already provisions), so consumers usually only need to set `BUMP_SOURCE` and wire `needs:` to their `docker-push` job (which must emit `IMAGE` to a dotenv artifact). `allow_failure: true` by default — the image is already pushed by the time the trigger fires, so a downstream automation hiccup shouldn't fail the producer pipeline.

## [0.0.42] - 2026-05-10

### Changed

- `gitlab/release.yml`: dropped the `registry.gitlab.com/gitlab-org/release-cli:v0.24.0` image and now runs on `docker.io/library/alpine:3` with `curl` and `jq` installed in `before_script`. Calls the Releases API directly (`POST /projects/:id/releases`) authenticated with `CI_JOB_TOKEN`. Self-hosted runners that hadn't preheated the release-cli image were hitting `prepare environment: timed out waiting for pod to start` because the registry.gitlab.com pull exceeded the runner's `poll_timeout`; the alpine image is small enough to pull within the default and is already cached on most runners. Behaviour is otherwise unchanged: same CHANGELOG-section extraction, same fallback description, same idempotency on `TAG_CREATED`.

## [0.0.41] - 2026-05-10

### Added

- `gitlab/bump-version.yml`: new optional `BUMP_CHANGELOG` variable. When set to `"true"`, the template also prepends a new `## [X.Y.Z] - YYYY-MM-DD` section to `CHANGELOG_FILE` (default `CHANGELOG.md`) and stages it as part of the bump commit. Entry text is parsed from the MR title when it matches renovate's `<type>(deps): update dependency <name> to <version>` pattern (e.g. `Bumped tox to v4.53.1`); otherwise the MR title is used verbatim. Idempotent — if a section for the new version already exists, the changelog is left untouched.

## [0.0.40] - 2026-05-10

### Added

- `gitlab/release.yml`: new reusable template that creates a GitLab Release matching the tag pushed by `gitlab/tag.yml`. Reads `VERSION` and `TAG_CREATED` from `.tag`'s dotenv artifact via `needs: artifacts: true`, so it no-ops when the tag already existed instead of creating a duplicate release. Pulls the `## [X.Y.Z]` section out of `CHANGELOG.md` (Keep-a-Changelog format) for the release description; falls back to `"Release <version>"` when no matching section is found. `CHANGELOG_FILE` is configurable. Image pinned to `registry.gitlab.com/gitlab-org/release-cli:v0.24.0`.

## [0.0.39] - 2026-05-09

### Changed

- `gitlab/bump-version.yml`: template now sets `stage: .pre` so the bump runs before any consumer-defined stages (validate, test, build, ...). Previously the job inherited GitLab's default `test` stage and consumers' `validate` jobs ran first, burning CI time on a SHA that was about to be superseded by the bump push. Consumers that previously set an explicit `stage:` override on their `bump-version` job can now drop it.
- `gitlab/discord-notify.yml`: webhook failures are now non-fatal — the script logs the error to stderr and exits 0 instead of failing the job. Adds a 10s `urlopen` timeout and catches `URLError` (DNS/network) and unexpected exceptions in addition to `HTTPError`. Notifications are advisory; a Discord outage or webhook misconfiguration should not break the pipeline.

## [0.0.38] - 2026-05-06

### Changed

- `gitlab/bump-version.yml`: when `GITLAB_PUSH_TOKEN` is set, the auth URL now uses `oauth2:<token>` as the basic-auth pair instead of the literal `deploy-token:<token>`. `oauth2:` is the canonical username for personal access tokens, project access tokens, and deploy tokens — the previous form only authenticated correctly for deploy tokens whose username happened to be literally `deploy-token`. The fallback to `gitlab-ci-token:$CI_JOB_TOKEN` is unchanged, but now emits a stderr warning since `CI_JOB_TOKEN`-authored pushes don't trigger a follow-up pipeline (GitLab's infinite-loop guard) and leave the MR widget reporting `ci_must_pass` on the bump commit, while a PAT-authored push triggers a fresh pipeline and keeps the widget green. Doc header and README rewritten to call out the trade-off and recommend `GITLAB_PUSH_TOKEN`.

### Added

- `gitlab/renovate.yml`: new optional `GITHUB_COM_TOKEN` pass-through. When set as a CI variable (any GitHub PAT — no scopes needed beyond public-repo reads), Renovate uses it to fetch release notes from github.com for dependencies whose source/changelog lives there. Without it, MR bodies show "Release Notes retrieval for this MR were skipped because no github.com credentials were available." See [renovate self-hosting docs](https://github.com/renovatebot/renovate/blob/main/docs/usage/examples/self-hosting.md#githubcom-token-for-release-notes).

## [0.0.37] - 2026-05-05

### Changed

- `gitlab/docker-push.yml`: now reads OCI registry credentials from base64-encoded variables (`OCI_USERNAME_64`, `OCI_TOKEN_64`, `OCI_REGISTRY_64`, `OCI_NAMESPACE_64`, `OCI_REPO_NAME_64`) and decodes them in `before_script`. GitLab's masking length requirement rejects short values (e.g. namespace, repo name) when stored as plaintext; base64-encoding lets all of them be stored as masked CI variables. **Breaking** for consumers — rename the CI variables in **Settings → CI/CD → Variables** and store the base64-encoded values (e.g. `printf '%s' "$value" | base64`).

## [0.0.36] - 2026-05-04

### Changed

- `gitlab/trufflehog-image.yml`: dropped the in-job `docker build` / `docker save` flow and the `docker:27-dind` service. The template now requires `TRUFFLEHOG_IMAGE_TARBALL` to point at a `docker save` tarball produced by an upstream build job (wired up via `needs:`), and runs on `docker.io/library/alpine:3` with no Docker daemon. TruffleHog reads the OCI tarball directly via `file://`. Removes the dind memory baseline and ~10s daemon startup from the scan job. **Breaking** for consumers that relied on the self-contained build-and-scan behaviour — they now need an upstream job that publishes the tarball as an artifact. Removed variables: `DOCKERFILE_PATH`, `DOCKER_CONTEXT`, `DOCKER_BUILD_ARGS`.
- `gitlab/trufflehog-image.yml`: default `TRUFFLEHOG_EXTRA_ARGS` now includes `--concurrency=2`. TruffleHog otherwise spawns one scan worker per `runtime.NumCPU()`, which on unbounded CI pods drives memory peaks of 1–2 GiB on larger images. Capping at 2 keeps memory predictable at the cost of ~20–30% scan time; raise it via override when you have headroom.

## [0.0.35] - 2026-05-03

### Added

- `gitlab/bump-version.yml`: now supports JSON version files (e.g. `package.json`) via `VERSION_FILE_TYPE: 'json'` and `VERSION_JSON_KEY` (default `version`), matching the surface area `gitlab/tag.yml` already exposed. JSON files are rewritten with `jq --indent 2`, preserving key order. The default behaviour is unchanged: `VERSION_FILE_TYPE` defaults to `plain` and consumers using a plain-text `VERSION` file need no changes. Adds `jq` to the alpine `apk add` line.

## [0.0.34] - 2026-05-03

### Added

- `gitlab/trufflehog-image.yml`: new optional `TRUFFLEHOG_IMAGE_TARBALL` variable. When set, the template skips the local `docker build` / `docker save` step and scans the supplied tarball directly. Lets a consumer chain off an upstream build job (e.g. `gitlab/docker-push.yml`) via `needs: [<build-job>]` and an artifact, instead of rebuilding the image just to scan it.

## [0.0.33] - 2026-05-03

### Changed

- All template image references are now fully qualified with `docker.io/...` so they work on runtimes that enforce CRI-O's `short-name-mode = "enforcing"` (e.g. Oracle Linux nodes on OKE). Containerd and Docker auto-resolve short names so this is invisible there. Affects:
  - `gitlab/trufflehog.yml`: `trufflesecurity/trufflehog:latest` → `docker.io/trufflesecurity/trufflehog:latest`
  - `gitlab/renovate.yml`: `renovate/renovate:43` → `docker.io/renovate/renovate:43`
  - `gitlab/bump-version.yml`: `alpine:3` → `docker.io/library/alpine:3`
  - `gitlab/discord-notify.yml`: `python:3.14-slim` → `docker.io/library/python:3.14-slim`
  - `gitlab/docker-push.yml`: `docker:27` (image) and `docker:27-dind` (service) → `docker.io/library/docker:27` and `docker.io/library/docker:27-dind`
  - `gitlab/trufflehog-image.yml`: same as docker-push.yml

### Fixed

- `gitlab/tag.yml`: explicitly declares `image: docker.io/library/alpine:3` and a `before_script` that installs `git` and `jq`. Previously the template inherited whatever image the consumer or runner default supplied — fine on shared runners with a fat default that includes `git`, but the script's `git` and `jq` (used on the `VERSION_FILE_TYPE=json` branch) would fail with `command not found` on a minimal alpine runner default.

## [0.0.32] - 2026-05-01

### Fixed

- `gitlab/trufflehog-image.yml`: scanning failed with `UNAUTHORIZED: authentication required` against `index.docker.io` because `trufflehog docker --image <tag>` resolves references through a registry rather than the local Docker daemon, so a bare local tag got normalized to `docker.io/library/<tag>` and pulled. The template now `docker save`s the built image to a tarball and passes `--image "file://$SCAN_TARBALL"`, scanning the local image without any registry round-trip.

## [0.0.31] - 2026-05-01

### Added

- `gitlab/trufflehog.yml`: new reusable GitLab CI template for scanning the repo with [TruffleHog](https://github.com/trufflesecurity/trufflehog). On MR pipelines, scans only commits added in the MR via `--since-commit $CI_MERGE_REQUEST_DIFF_BASE_SHA`; on default-branch / scheduled / manual pipelines, scans the full git history. Defaults to `--only-verified --fail` so the job fails only on credentials TruffleHog validates against the issuing API. Configurable via `TRUFFLEHOG_EXTRA_ARGS`, `TRUFFLEHOG_EXCLUDE_PATHS` (regex file), and `TRUFFLEHOG_FULL_HISTORY`.
- `gitlab/trufflehog-image.yml`: companion template that builds the repo's Dockerfile inside Docker-in-Docker and scans the resulting image with TruffleHog's `docker` mode. Catches secrets baked into image layers (e.g. via a leaky `RUN` command or copied-then-deleted file) that source-level scanning misses. Self-contained — no registry pull or chaining with `gitlab/docker-push.yml` required. Configurable via `DOCKERFILE_PATH`, `DOCKER_CONTEXT`, `DOCKER_BUILD_ARGS`, `TRUFFLEHOG_VERSION`, and `TRUFFLEHOG_EXTRA_ARGS`.

### Changed

- `.gitlab-ci.yml`: this repo now runs `gitlab/trufflehog.yml` on MR pipelines as a `validate`-stage job, dogfooding the new template. Fork MRs require manual trigger, matching the existing `pre-commit` and `notify-mr` jobs.

## [0.0.30] - 2026-04-30

### Added

- `gitlab/docker-push.yml`: new reusable GitLab CI template for building and pushing a multi-arch Docker image. Logs in to an OCI registry, installs QEMU binfmt handlers via `tonistiigi/binfmt`, builds with `--platform` (default `linux/arm64`), and pushes two tags: the short commit SHA and `latest`. Registry credentials and image coordinates are passed via `OCI_REGISTRY`, `OCI_NAMESPACE`, `OCI_REPO_NAME`, `OCI_USERNAME`, and `OCI_TOKEN` CI variables. Platform is overridable via the `DOCKER_PLATFORM` variable.

### Changed

- `.gitlab-ci.yml`: `pre-commit` no longer runs on push to the default branch (merge). Validation only runs on MR pipelines; tag and notify jobs remain on merge.

## [0.0.29] - 2026-04-29

### Added

- `gitlab/bump-version.yml`: new reusable GitLab CI template for auto-bumping the patch version on a branch. Compares the `VERSION` file against the default branch and increments the patch version if it hasn't been bumped yet. Idempotent — exits cleanly if already bumped, preventing push loops. Uses `alpine:3` with `apk add git`. Supports `GITLAB_PUSH_TOKEN` with fallback to `CI_JOB_TOKEN`.

## [0.0.28] - 2026-04-29

### Added

- `gitlab/renovate.yml`: new reusable GitLab CI template for running Renovate. Runs against the current project using `RENOVATE_TOKEN` (GitLab PAT with `api` scope). Intended for scheduled pipelines — wire up via `Settings → CI/CD → Schedules` in GitLab.
- `renovate.json`: Renovate config for this repo. Enables `pre-commit` and `docker` managers to keep pre-commit hook revs and Docker image tags up to date. GitHub Actions manager intentionally excluded pending GitLab migration.

### Fixed

- `gitlab/discord-notify.yml`: requests were blocked by Cloudflare on GitLab shared runners (error code 1010) due to Python's default `Python-urllib` User-Agent. Fixed by sending `DiscordBot (github-workflows, 1.0)` as the User-Agent, which Cloudflare whitelists.
- `gitlab/discord-notify.yml`: webhook URL is now stripped of whitespace before use, preventing 403s caused by trailing newlines in GitLab CI variable values.
- `gitlab/discord-notify.yml`: Discord API response body is now printed on error, making failures easier to diagnose.
- `.gitlab-ci.yml`: notify jobs now use `needs: []` and `when: always` so they run immediately and independently of the validate/tag stages.

## [0.0.27] - 2026-04-29

### Added

- `gitlab/discord-notify.yml`: new GitLab CI template for Discord notifications. Supports four notification types (`failure`, `success`, `mr_opened`, `mr_merged`) with auto-detected MR context (title, branch arrow, MR URL). The target channel is controlled via `DISCORD_WEBHOOK_URL`, overridable per job to route different event types to different channels.
- `.gitlab-ci.yml`: this repo now has its own GitLab CI pipeline. Runs `pre-commit` on MRs and the default branch, creates a git tag on push to main via `gitlab/tag.yml`, and sends Discord notifications to `$DISCORD_MR_WEBHOOK` on MR pipelines and pushes to main.
- `.pre-commit-config.yaml`: added `check-jsonschema` hook (`check-gitlab-ci`) to validate `.gitlab-ci.yml` against the official GitLab CI JSON schema on every commit.

### Fixed

- `gitlab/tag.yml`: git push would fail silently without credentials configured. The script now sets the remote URL to authenticate via `CI_JOB_TOKEN` by default, or `GITLAB_PUSH_TOKEN` if set, before pushing the tag. Also adds `git config user.email/name` required by some runners.

## [0.0.26] - 2026-04-29

### Added

- `gitlab/tag.yml`: new GitLab CI template equivalent of `tag.yml`. Reads a version file (plain text or JSON), checks if the tag already exists, and pushes it if not. Configuration is passed via CI variables (`VERSION_FILE`, `VERSION_FILE_TYPE`, `VERSION_JSON_KEY`). Outputs (`VERSION`, `TAG_CREATED`, `TAG_EXISTS`) are exposed via a `dotenv` artifact for downstream jobs.

## [0.0.25] - 2026-04-24

### Changed

- `coverage-check.yml`: overall coverage drop no longer fails the job — it now posts a warning comment on the PR instead, so teams that delete code aren't blocked by a coverage regression that diff-cover shows is 100% on changed lines.
- `coverage-check.yml`: `fail_on_diff_cover` default changed from `false` to `true` — diff-cover (new/changed line coverage) is now the primary hard gate.
- `coverage-check.yml`: added `pull-requests: write` permission so the warning comment can be posted.
- `coverage-check.yml`: step summary coverage drop status updated from ❌ Failed to ⚠️ Warning to reflect the non-blocking behaviour.

## [0.0.24] - 2026-04-23

### Added

- `dependabot-auto-approve.yml`: new `dependency_groups` input — a comma-separated list of dependabot group names that must match the `dependency-group` reported by `dependabot/fetch-metadata` for the PR to be eligible. Useful for filtering updates by section in files like `pyproject.toml` (e.g. `prod-deps` vs `dev-deps`) without having to enumerate every package in `accept_packages`. If empty, no group filter is applied.

## [0.0.23] - 2026-04-23

### Added

- `bump-version.yml`: new `paths` input — a JSON array of glob patterns that gates the version bump on whether any changed files match. Empty array (default) preserves the existing always-run behaviour. Implemented as a lightweight `check` job that runs `git diff --name-only` against the base branch and matches files using bash `case` glob syntax.

## [0.0.22] - 2026-04-23

### Added

- `bump-version.yml`: new reusable workflow that bumps the version file on a PR branch (major/minor/patch, default patch) and commits the result back onto the PR. Idempotent — skips if the version file was already changed relative to the base branch, preventing re-trigger loops.

## [0.0.21] - 2026-04-22

### Added

- `ocir-push.yml`: new optional `build_args` input (newline-separated `KEY=VALUE` pairs) passed through to `docker/build-push-action`'s `build-args` parameter.

## [0.0.20] - prior

### Fixed

- Address git hash bug (#24)

### Added

- Add flag to fail on diff cover (#23)

### Changed

- Bump `docker/build-push-action` from 7.0.0 to 7.1.0 (#26)
- Bump `actions/upload-artifact` from 7.0.0 to 7.0.1 (#27)
- Bump `docker/login-action` from 4.0.0 to 4.1.0 (#25)
