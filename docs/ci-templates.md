# Shared CI templates (github-workflows)

How `github-workflows` provides reusable CI templates consumed by every
other repo in `~/Code`, plus the GitHub Actions side that still exists
during the GitLab migration.

## TL;DR

> **Inverted since this was written — 2026-09-05.** This document describes
> `github-workflows` as mid-migration with the **GitLab** half "actively
> evolving". That is backwards now. Every one of the 26 projects is
> GitHub-canonical, the `gitlab/` templates are frozen break-glass, and the
> Actions workflows under `.github/workflows/` are the only side that runs.
>
> Specifics below that are no longer true:
>
> - **The pre-baked CI images are retired.** `CI_K8S_LINT_IMAGE`,
>   `CI_ALPINE_UTILS_IMAGE`, `CI_TERRAGRUNT_UTILS_IMAGE` and the rest were
>   removed as GitLab group variables; the images' own repo is archived. Their
>   replacement is pinned tool downloads in the consuming workflow — see
>   `docker-apps/.github/actions/k8s-lint-tools`.
> - **The self-hosted runners and the `ci` node pool are gone**, so anything
>   about cold starts, the warm ci floor, or `tags: [self-hosted]` describes a
>   world that no longer exists. Actions runs on GitHub-hosted runners.
> - **`trigger-bump.yml` has a successor**, `trigger-bump-dispatch.yml`, using
>   `repository_dispatch` instead of GitLab's pipeline-trigger API.
>
> The template-by-template reference below is still useful as a record of what
> each GitLab template did, and several Actions workflows are direct ports.
> Treat platform claims as historical. See
> [`projects/github-canonical-migration.md`](https://github.com/tnoff/docs/blob/main/projects/github-canonical-migration.md).

- **github-workflows is a dual-platform template repo, mid-migration.** It
  ships **14 GitLab CI templates** under `gitlab/` (the actively evolving
  half) and **9 GitHub Actions reusable workflows** under
  `.github/workflows/` (still consumed where the GitHub mirror runs). The
  repo name predates the GitLab side.
- **Consumed via `include: project:`** on every personal-project
  `.gitlab-ci.yml`. Templates expose hidden jobs (`.tag`, `.trigger-bump`,
  `.buildkit-docker-push`, etc.) that consumers `extends:`.
- **Versioned as `vX.Y.Z` git tags** + `CHANGELOG.md`. **README says
  `ref: main`, real consumers pin SHAs** managed by Renovate — worth
  knowing.
- The repo **dogfoods itself**: its own `.gitlab-ci.yml` uses
  `include: local:` to ride the same templates, so any breaking change to
  a template breaks this repo's pipeline first.

## Template catalog (GitLab side)

The canonical reference is the ~46 KB `README.md` in the repo; this is the
short index — go there for inputs, secrets, and usage blocks.
| Template | Exposed job | Concern |
|---|---|---|
| `gitlab/tag.yml` | `.tag` | Push `vX.Y.Z` git tag if `VERSION` advanced. |
| `gitlab/release.yml` | `.release` | Extract Keep-a-Changelog section, POST `/releases`. |
| `gitlab/bump-version.yml` | `.bump-version` | Patch-bump `VERSION` (+ optional CHANGELOG) on a Renovate MR branch. |
| `gitlab/buildkit-docker-push.yml` | `.buildkit-docker-push` | Out-of-cluster buildkit build + push to OCIR (`:SHA`, `:latest`, or `:$TAG_OVERRIDE-<sha>` + `:$TAG_OVERRIDE`). Emits `IMAGE=<full ref>` dotenv. Imports + exports S3 layer cache when `BUILDKIT_CACHE_BUCKET` is set (see [S3 layer cache](#s3-layer-cache)). Replaced the retired dind `.docker-push`. |
| `gitlab/buildkit-build-check.yml` | `.buildkit-build-check` | MR-time "does the Dockerfile compile" check; emits a `docker save` tarball for downstream scanners. Imports + exports the same S3 layer cache as `.buildkit-docker-push`. |
| `gitlab/tox-pipeline.yml` | `.tox-generate`, `.tox-pipeline` | Generates and triggers a child pipeline from `tox -l` (works around GitLab not accepting list job vars). `TOX_BASE_IMAGE` opt-in skips apt-install in favor of a pre-baked `ci-base-images` image. |
| `gitlab/spellcheck.yml` | `.spellcheck` | Run `pyspelling` against a project's spellcheck config. |
| `gitlab/trufflehog.yml` | `.trufflehog` | Git-history secret scan (MR-scoped on MRs). |
| `gitlab/trufflehog-image.yml` | `.trufflehog-image` | Scan a `docker save` tarball — no dind required. |
| `gitlab/renovate.yml` | `.renovate` | Scheduled Renovate run. |
| `gitlab/trigger-bump.yml` | `.trigger-bump` | Cross-project pipeline trigger (see below). |
| `gitlab/branch-cleanup.yml` | `.branch-cleanup` | Scheduled prune of merged/stale branches (added `c3e8e55`). |
| `gitlab/assemble-changelog.yml` | `.assemble-changelog` | Fold per-MR `changelog.d/<slug>.md` fragments into `CHANGELOG.md` at release time; pushes the fold to the default branch (added `54fe29a`, `github-workflows!65`). See [`projects/renovate-version-changelog-conflicts.md`](https://github.com/tnoff/docs/blob/main/projects/renovate-version-changelog-conflicts.md). |

**Retired:** `gitlab/discord-notify.yml` (`.discord-notify`) was deleted in
`github-workflows!82` (v0.0.53, 2026-08-15) once it had no consumers left —
`failure` had already retired into the Grafana `gitlab-ci-job-failure` alert,
and `mr_opened` / `mr_merged` went with the `#mr-opened` / `#mr-merged`
channels. See
[`findings/2026-08-15-mr-notify-retirement.md`](https://github.com/tnoff/docs/blob/main/findings/2026-08-15-mr-notify-retirement.md).
There is now **no direct CI → Discord sender** on the GitLab side; every
CI-failure signal routes through Grafana.

## Template catalog (GitHub Actions side)

Still active for repos whose GitHub mirror runs CI. Called via
`uses: tnoff/github-workflows/.github/workflows/X.yml@v1`.
The GitHub-side `discord-notify.yml` is **not** retired — it is
failure-only and unrelated to the GitLab template above.

`.github/workflows/`: `ocir-push.yml`, `tag.yml`, `bump-version.yml`,
`check-pr-labels.yml`, `dependabot-auto-approve.yml`, `discord-notify.yml`,
`coverage-store.yml`, `coverage-check.yml`, `check-action-pins.yml`.

`AGENTS.md` was consolidated in `6dfd3c0` (2026-06-06) and now covers both
the GitLab and GitHub trees. The historical "AGENTS is stale" warning no
longer applies. Shared Renovate presets also moved in-tree under
`renovate/` (`default.json`, `python.json`) in `b008ef7` for consumers
to `extends`. The `default.json` preset sets `dependencyDashboard: false`
(`github-workflows!37`, 2026-06-16) so `config:recommended` does not
open the per-repo Dependency Dashboard GitLab work item; `docker-apps`
mirrors the override in its own `renovate.json` (`docker-apps!269`)
since it opts into `config:recommended` directly rather than via the
shared preset.

> **Retired:** `gitlab/docker-push.yml` (`.docker-push`) was dind-based
> and had zero in-tree consumers; removed in 0.0.44 (`0aed690`,
> 2026-06-01) in favor of `.buildkit-docker-push`, which all 6 producers
> have since adopted. **Breaking** for any external consumer still
> extending `.docker-push`. See [`findings/2026-05-29.md`](https://github.com/tnoff/docs/blob/main/findings/2026-05-29.md)
> for the pre-retirement analysis.

## The `.trigger-bump` template

`gitlab/trigger-bump.yml` (introduced in `cdd34af`, 2026-05-13) is the
**producer-side counterpart to docker-apps's `.bump-image-pin-base`**.
Pulled out of pattern duplicated across the six producer repos.

Mechanism — POSTs to `/projects/$TARGET_PROJECT_ID/trigger/pipeline` with:

- `token=$TARGET_TRIGGER_TOKEN`
- `variables[BUMP_SOURCE]` — gates the downstream job.
- `variables[IMAGE_NAME]`, `variables[IMAGE_TAG]=$CI_COMMIT_SHORT_SHA` —
  passed to docker-apps.
- `variables[SOURCE_PROJECT_ID]=$CI_PROJECT_ID`,
  `variables[SOURCE_SHA]=$CI_COMMIT_SHA` — added `262ca72b`
  (`github-workflows!51`, 2026-07-04). Let the downstream bump job link the
  MR back to the producing MR (`Source MR:`) and a changelog compare view
  (`Changelog:`). Derived from predefined CI vars, so no per-consumer
  config; consumers on an older ref simply don't send them (the links are
  best-effort). See image promotion (docker-apps TechDocs).

Defaults: `TARGET_PROJECT_ID=$DOCKER_APPS_PROJECT_ID`,
`TARGET_TRIGGER_TOKEN=$DOCKER_APPS_TRIGGER_TOKEN`. Both are pushed onto
each producer's GitLab project by `terraform-admin` via the
`terraform_gitlab` module (see infra bootstrap (terraform-admin TechDocs)).

End-to-end image promotion now reads:

```
producer repo (.docker-push)  →  producer repo (.trigger-bump)
   →  docker-apps (.bump-image-pin-base, opens MR)
   →  MR merged
   →  Flux reconciles
   →  OKE rolls out
```

See image promotion (docker-apps TechDocs) for the docker-apps side.

## Consumption pattern

Consumers pin **full commit SHAs**, not tags or `main`, despite README
saying otherwise. Renovate handles the bumps. Three sampled consumers:

| Consumer | Pinned SHA | Tag | Templates included |
|---|---|---|---|
| `discord-bot` | `f94e713c` | `v0.0.47` | `tag`, `discord-notify`, `renovate`, `bump-version`, `trufflehog`, `trufflehog-image`, `buildkit-build-check`, `buildkit-docker-push`, `trigger-bump`, `tox-pipeline` |
| `docker-apps` | `f94e713c` | `v0.0.47` | `discord-notify`, `renovate`, `trufflehog` |
| `terraform` | `b008ef77` | `v0.0.48` | `discord-notify`, `renovate`, `trufflehog` |

As of 2026-06-08, HEAD is `e584647` on `v0.0.48` (TAG_OVERRIDE +
TOX_BASE_IMAGE shipped in `ea299f8`, with a regex fix in `e584647`).
`terraform` has Renovate-bumped to v0.0.48; `discord-bot` and
`docker-apps` are one version behind on v0.0.47 — typical staggered
Renovate cadence. Breaking changes still warrant caution.

## Versioning + dogfooding

Real `vX.Y.Z` git tags are produced by `gitlab/tag.yml` running on this
repo's own default-branch pushes (`.gitlab-ci.yml` `include: local:`).
`VERSION` is currently `0.0.49` (HEAD is `b0c827a`; `v0.0.49` was tagged at `b75554a`).
`release.yml` exists but isn't wired into this repo's own CI yet — tags
ship, GitLab Releases don't.

The dogfood path means a broken template breaks this repo's pipeline
first. Useful early-warning canary.

## Breaking changes worth knowing

From `CHANGELOG.md`:

- **0.0.44** — `.docker-push` removed. **Breaking** for any external
  consumer still extending it; migrate to `.buildkit-docker-push`, which
  expects an out-of-cluster `buildkitd` Deployment rather than dind. All
  6 in-tree producers migrated in the same release wave.
- **0.0.37** — all OCI creds renamed to `_64` (base64) form. Consumers
  must rename CI vars and re-encode values when they Renovate-bump past
  this.
- **0.0.36** — `.trufflehog-image` no longer uses dind; requires an
  upstream `docker save` tarball artifact. Removed inputs:
  `DOCKERFILE_PATH`, `DOCKER_CONTEXT`, `DOCKER_BUILD_ARGS`.

If a consumer is stale enough to predate any of these, the Renovate bump
will require coordinated CI-variable or job-definition changes.

## Adoption status

The dedup work flagged in [`findings/2026-05-30-ci-dedup.md`](https://github.com/tnoff/docs/blob/main/findings/2026-05-30-ci-dedup.md)
has shipped. As of 2026-06-08:

| Template | Adoption |
|---|---|
| `.trigger-bump` | All 6 producers. |
| `.buildkit-docker-push` | All 6 producers. |
| `.buildkit-build-check` | All 6 producers. |
| `.tox-pipeline` (`.tox-generate` + `.tox-pipeline`) | All 7 Python repos via `TOX_BASE_IMAGE`: `discord-bot`, `oke-security-scanner`, `backup-tool` (`backup-tool!19`), `hathor` (`hathor!29`), `public-transit` (`public-transit!29`), `enheduanna` (`enheduanna!25`), `dappertable` (`dappertable!27`). |
| `.spellcheck` | `eastbay`, `personal-website` so far; remaining 2 pending. |

Inline `trigger-bump-docker-apps` and inline `docker-push-*` jobs are gone
from all producer `.gitlab-ci.yml` files.

## Pre-baked CI base images (`ci-base-images`)

`tnoff-projects/ci-base-images` publishes one OCIR image per Python minor
(`ci-base-images:3.11`, `:3.12`, `:3.13`, `:3.14`) with `build-essential +
git + ffmpeg + postgresql` (apt) and `tox + diff-cover` (pip) baked in.
`build-essential` was added in `ci-base-images!7` (2026-06-14) so consumers
don't need `TOX_EXTRA_APT` workarounds when a dep compiles a C extension
(e.g. `crc32c`, a transitive dep of the OCI SDK, has no prebuilt wheel for
Python 3.14/aarch64). The `postgresql` (server) package — not
`postgresql-client` — is required so consumers using `pytest-postgresql`
can call `pg_ctlcluster` to start a local cluster (caught when
discord-bot first opted in: client-only made every DB test error with
`psycopg.OperationalError`). Consumers opt in by setting

```yaml
TOX_BASE_IMAGE: '${CI_BASE_IMAGE_PATH}:$${PYTHON_VERSION}'
TOX_GENERATE_IMAGE: '${CI_BASE_IMAGE_PATH}:3.14'
```

on a `.tox-generate` job; the template then skips the per-job
`apt-get install` preamble + `pip install tox` / `pip install diff-cover`
entirely and uses the pre-baked images as the matrix runtime.

> **The doubled `$$` on `TOX_BASE_IMAGE` is required.** GitLab expands
> `${VAR}` references in the consumer's `variables:` block at
> parent-pipeline time. `CI_BASE_IMAGE_PATH` exists at that scope and
> expands to the OCIR ref; `PYTHON_VERSION` only exists inside the
> child pipeline's matrix and would otherwise expand to empty. The
> doubled `$` keeps the literal `${PYTHON_VERSION}` token in the value
> so `.tox-generate`'s heredoc writes it verbatim into the child YAML,
> where the matrix substitutes per minor at runtime. Discovered the
> hard way on `discord-bot!60` — the first pipeline generated
> `image: iad.ocir.io/tnoff/ci-base-images:` and every tox job failed
> on the missing tag.

> **`TOX_GENERATE_IMAGE` is a single concrete tag, not templated.** The
> parent `.tox-generate` job runs once per MR (not per matrix entry) —
> it just needs Python + tox to introspect `tox -l` and write the child
> YAML. Pin to whichever minor matches the current latest in
> `ci-base-images/tox.ini` (`:3.14` as of 2026-06-16); see the
> "Manual bumps when a Python minor lands" gotcha below.

- Tags: mutable `:3.X` (overwritten on every rebuild from `main` — picks
  up Debian/Python security updates) + immutable `:3.X-<short-sha>`
  (pin if you need strict reproducibility).
- `CI_BASE_IMAGE_PATH` is a plaintext group-level GitLab variable
  provisioned by `terraform/infra/gitlab.tf` — image refs aren't
  secrets so it skips the `_64` masking dance the OCIR push creds use.
- The OCIR repo + per-project push IAM user are provisioned in
  `terraform/oci/oci.tf` (modules `ci_base_images_container_repo` +
  `gitlab_ci_base_images_push`). Pulls reuse the existing
  `apps_container_bot_read` blanket policy — no IAM change needed for
  consumers to pull.
- The base image's apt list is intentionally a single kitchen-sink set
  rather than per-flavor images. Adding a new system dep means editing
  one Dockerfile; the cost is a few extra MB of image pull for lean
  consumers that don't use the dep.

This is a `tox`-only optimization; non-tox CI paths (`.buildkit-docker-push`
itself, `.tag`, `.discord-notify`, etc.) keep using whatever image they
were using before — typically `docker.io/moby/buildkit` or `alpine:3`.

## Non-Python CI images (`ci-spellcheck`, `ci-rust-tauri`, `ci-k8s-lint`)

The same repo also builds three single-tag images for non-tox CI jobs that
previously installed packages inline on every MR. Each pushes `:latest` +
`:<sha>` to its own OCIR repo; the `gitlab_ci_base_images_push` IAM user's
policy was expanded to cover all four repos via an `any {}` where clause.

| Image | Base | Baked-in deps | Consumer | Group var |
|---|---|---|---|---|
| `ci-spellcheck` | `python:3.14-slim-bookworm` | `aspell`, `aspell-en`, `pip install pyspelling` | `.spellcheck` template | `CI_SPELLCHECK_IMAGE` |
| `ci-rust-tauri` | `rust:1` | 7 Tauri/WebKit2GTK libs + `clippy` | `harpocrates` `rust-check` | `CI_RUST_TAURI_IMAGE` |
| `ci-k8s-lint` | `python:3.14-slim-bookworm` | `git`, `curl`, `kubeconform` 0.6.7, `kube-linter` 0.7.2, `conftest` 0.67.0, `pre-commit` | `docker-apps` `pre-commit` | `CI_K8S_LINT_IMAGE` |

Each group variable (`CI_SPELLCHECK_IMAGE` etc.) is a full image ref
including `:latest`, provisioned by `terraform/infra/gitlab.tf` —
same plaintext/unmasked pattern as `CI_BASE_IMAGE_PATH`. Per-image
`OCI_REPO_NAME_64` pipeline variables on the `ci-base-images` project
are provisioned in `terraform/infra/repos.tf`; the build jobs in
`ci-base-images/.gitlab-ci.yml` override `OCI_REPO_NAME_64` per image.

The `.spellcheck` template (`github-workflows!36`) now uses
`image: $CI_SPELLCHECK_IMAGE` with no `before_script`; `harpocrates!54` and
`docker-apps!261` consumer jobs similarly drop their inline install steps.
All three depend on `terraform!73` (OCIR repos + group vars) and
`ci-base-images!8` (the image builds) merging first.

> **`ci-k8s-lint` tool versions are ARG-pinned in the Dockerfile**, not CI
> variables, so bumping a tool version requires a `ci-base-images` MR.
> Renovate is not yet wired to update these ARG defaults.

## S3 layer cache

`.buildkit-build-check` and `.buildkit-docker-push` pass
`--import-cache type=s3,…` + `--export-cache type=s3,…,mode=max` to
`buildctl` when `BUILDKIT_CACHE_BUCKET` is set in the environment —
keyed on `$CACHE_NAME` (default `$CI_PROJECT_NAME-$DOCKERFILE_NAME`,
so multi-image repos like `discord-bot`'s `Dockerfile` +
`Dockerfile.dispatcher` cache independently). Wired in
[github-workflows!34](https://gitlab.com/tnoff-projects/github-workflows/-/merge_requests/34);
see [`findings/2026-06-11-ci-queue-saturation.md`](https://github.com/tnoff/docs/blob/main/findings/2026-06-11-ci-queue-saturation.md#2-buildkit-s3-cache-provisioned-but-never-invoked)
for the trace that motivated it (every build started cold).

> **The two templates aren't symmetric on export.** `.buildkit-build-check`
> (MR) exports `mode=max`; the merge-time `.buildkit-docker-push` used to as
> well — on *both* its `:sha` and `:latest` builds — re-exporting the
> identical cache the build-check already seeded, i.e. three exports per
> merged change and a ~1.4-core `buildkitd` spike on the saturated ci pool.
> [github-workflows!66](https://gitlab.com/tnoff-projects/github-workflows/-/merge_requests/66)
> (merged 2026-07-07) makes the push job **import-only** by default (export
> behind `PUSH_EXPORT_CACHE`, default `false`); the MR→MR warm-cache chain is
> unaffected because build-check still exports. Rolled out to all 7 producers
> and confirmed live (`import=on export=false`, no export step) 2026-07-08.
> Full analysis in
> [`findings/2026-07-07-buildkit-merge-cache-export.md`](https://github.com/tnoff/docs/blob/main/findings/2026-07-07-buildkit-merge-cache-export.md).

The infrastructure all the halves of this rely on:

- **Bucket** — `gitlab_buildkit_cache` module in
  `terraform/oci/oci.tf` provisions an OCI Object Storage bucket plus
  an HMAC user for buildctl's S3-compat backend.
- **Secret** — `kubernetes_secret_v1.gitlab_runner_buildkit_s3_creds`
  in `terraform/apps/main.tf` writes `AWS_ACCESS_KEY_ID`,
  `AWS_SECRET_ACCESS_KEY`, `AWS_ENDPOINT_URL_S3`, `AWS_REGION`, and
  `BUILDKIT_CACHE_BUCKET` to a Secret named `buildkit-s3-creds` in
  the `gitlab-runner` namespace.
- **Injection (job pod side)** — the runner's `pod_spec` patch in
  `docker-apps/infrastructure/controllers/gitlab-runner/values.yaml`
  injects `buildkit-s3-creds` into every job pod's `build` container
  via `envFrom`. **Requires `FF_USE_ADVANCED_POD_SPEC_CONFIGURATION = true`**
  in the runner's `[runners.feature_flags]` — without that flag the
  `[runners.kubernetes.pod_spec]` stanza is silently ignored.
- ~~**Injection (buildkitd side)** — buildctl in the job pod is just a
  gRPC client; the actual S3 PUT/GET happens inside the in-cluster
  `buildkitd` Deployment. So `buildkit-s3-creds` is also injected on
  the buildkitd container via `envFrom` in
  `docker-apps/apps/gitlab-runner/k8s/buildkit.yaml`. Same Secret,
  symmetric injection.~~ **Superseded 2026-07-21 — there is no second
  injection point any more.** [`ci-scale-to-zero`](https://github.com/tnoff/docs/blob/main/projects/ci-scale-to-zero.md)
  Phase 2 retired the standing `buildkitd` Deployment so the ci pool can
  scale to zero; `.buildkit-build-check` now starts an **ephemeral
  `buildkitd` inside the job pod** on a local unix socket. The daemon
  therefore inherits the job container's own environment, and the single
  job-pod-side injection above covers both `buildctl` and the S3 syscalls.
  `docker-apps/apps/gitlab-runner/k8s/buildkit.yaml` no longer exists
  (verified 2026-08-23). The original hazard still applies to any future
  remote-builder setup: the creds must follow whichever container actually
  issues the S3 calls, or the AWS SDK chain falls through to EC2 IMDS and
  fails — this is OCI, not AWS.

So the cache is on automatically for any job that extends one of these
two templates while running on the OKE runner. Consumers running on a
different runner (no `buildkit-s3-creds` injected → `BUILDKIT_CACHE_BUCKET`
absent in the job pod) silently fall back to no remote cache — the
templates check the env before adding the flags.

~~Worth knowing about the in-cluster `buildkitd` Deployment alongside
this: it uses `emptyDir: {}` for `/var/lib/buildkit` and `strategy:
type: Recreate`, so its in-process cache is volatile across pod
restarts.~~ **Superseded — the conclusion is now stronger, not weaker.**
With `buildkitd` ephemeral and per-job, there is no local layer store
that survives *any* build, let alone a pod restart: **S3 is the only
cache there is.** That is worth holding onto when reasoning about build
times — a "cache hit" is a download-and-extract from object storage, not
a free local lookup, and it is measurably not free (~40 s for
`discord-bot`'s dependency layer; see
[`projects/ci-perf.md`](https://github.com/tnoff/docs/blob/main/projects/ci-perf.md) scope #11/#12).

**`buildkitd` is pinned to `v0.30.0` and Renovate is disabled for it** —
the *pin* survived the topology change, but its home moved: it now rides
the `$CI_BUILDKIT_IMAGE` CI image rather than a docker-apps Deployment.
The `matchPackageNames: ["docker.io/moby/buildkit"]` / `enabled: false`
rule is still present in `docker-apps/renovate.json` (verified
2026-08-23). Two things to check when next in that repo, both flagged
rather than fixed here: whether that Renovate rule still has anything to
match, and whether the `apps/gitlab-runner/kustomization.yaml` patch
commented "buildkitd tolerates the ci-pool taint" is now targeting a
Deployment that no longer exists. The pin rationale itself is unchanged: `v0.31+` swapped buildkit's S3 cache exporter to a package that sends
`aws-chunked` PutObjects unconditionally, which OCI Object Storage's
S3-compat endpoint rejects with a 501. See
[`findings/2026-07-05-buildkit-s3-cache-aws-chunked-501.md`](https://github.com/tnoff/docs/blob/main/findings/2026-07-05-buildkit-s3-cache-aws-chunked-501.md)
before bumping this image again — the obvious-looking checksum-env-var
fix does not work.

## Skipping image jobs on cosmetic MRs (`.image-build-rules` pattern)

Adopted across all 9 consumers of `.buildkit-build-check` (and most
that pair it with `.trufflehog-image`). Each repo's `.gitlab-ci.yml`
defines a hidden `.image-build-rules` job:

```yaml
.image-build-rules:
  rules:
    - if: $CI_PIPELINE_SOURCE == "merge_request_event" && $CI_MERGE_REQUEST_SOURCE_PROJECT_ID != $CI_PROJECT_ID
      when: manual
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"
      changes:
        - Dockerfile
        - <python source / static assets / requirements>
        - <anything COPY'd in the Dockerfile>
    - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH && $CI_PIPELINE_SOURCE != "schedule"
```

and the `docker-build*` + `trufflehog-image*` jobs reference it:

```yaml
docker-build-bot:
  extends: .buildkit-build-check
  variables: { ... }
  rules: !reference [.image-build-rules, rules]
```

What this gates: MRs that don't touch anything baked into the image
(Renovate `github-workflows` digest bumps, `renovate.json` tweaks,
doc-only edits) **skip the image rebuild + trufflehog-image scan
entirely**. On `discord-bot` that pair is ~10–17 min combined; under
`concurrent: 2` it directly delayed every contending pipeline's
tox jobs.

The per-repo `changes:` glob is specific to what each Dockerfile
actually `COPY`s in — not boilerplate. Two of the consumers
(`hathor`, `public-transit`) have `COPY . .` Dockerfiles, so their
glob is a *positive list of files that affect runtime* rather than a
literal mirror of the Dockerfile — docs and tests technically end up
in the image layer but won't trigger a rebuild, which is the optimization
point.

Pattern shipped 2026-06-11 across:

| Consumer | MR | Image-build job name |
|---|---|---|
| `discord-bot` | [!67](https://gitlab.com/tnoff-projects/discord-bot/-/merge_requests/67) | `docker-build-bot`, `docker-build-dispatcher` |
| `database-backup` | [!41](https://gitlab.com/tnoff-projects/database-backup/-/merge_requests/41) | `build-check` |
| `eastbay` | [!16](https://gitlab.com/tnoff-projects/eastbay/-/merge_requests/16) | `build-check` |
| `enheduanna` | [!22](https://gitlab.com/tnoff-projects/enheduanna/-/merge_requests/22) | `docker-build` |
| `hathor` | [!26](https://gitlab.com/tnoff-projects/hathor/-/merge_requests/26) | `docker-build` |
| `magic-mirror-docker` | [!24](https://gitlab.com/tnoff-projects/magic-mirror-docker/-/merge_requests/24) | `build-check` |
| `oke-security-scanner` | [!39](https://gitlab.com/tnoff-projects/oke-security-scanner/-/merge_requests/39) | `validate-docker` |
| `personal-website` | [!18](https://gitlab.com/tnoff-projects/personal-website/-/merge_requests/18) | `docker-build` |
| `public-transit` | [!26](https://gitlab.com/tnoff-projects/public-transit/-/merge_requests/26) | `docker-build` |

## Gotchas

- **README + template headers say `ref: main`** but every real consumer
  pins SHAs. Document/reality skew, not a bug.
- **`diff-cover` previously used `when: always`**, so it would run and
  crash on missing `coverage.xml` whenever a tox env failed. Fixed in
  `github-workflows!35` (2026-06-14) — changed to `when: on_success` so
  the coverage stage is skipped entirely on a tox failure.
- **The `cleanup-*` CronJob plumbing isn't here.** The
  `kubectl create job --from=cronjob/cleanup-*` calls live inline in
  `docker-apps/.gitlab-ci.yml`. Candidate for future consolidation into a
  `.trigger-image-cleanup` template, paralleling the `.trigger-bump`
  precedent.
- **`TOX_GENERATE_IMAGE` needs a manual bump when a new Python minor
  lands.** Renovate manages the `github-workflows` `ref:` but doesn't
  touch the `:3.X` tag inside `TOX_GENERATE_IMAGE`'s value string. When
  `ci-base-images/tox.ini` + the `build:` matrix grow a new minor
  (e.g. `3.15`), bump `:3.14` → `:3.15` in each consumer's
  `tox-generate` block as a one-line follow-up. The parent runs Python
  + tox only, so anything modern works — there's no breakage on a
  stale minor, just a missed opportunity to drift forward with the
  rest of the fleet. Affects the 5 Python tox consumers:
  `discord-bot`, `oke-security-scanner`, `enheduanna`, `hathor`,
  `public-transit`.

---

## Verified against

| Project | SHA | Date |
|---|---|---|
| `github-workflows` | `b0c827a` | 2026-07-14 |
| `ci-base-images` | `f964340` | 2026-07-14 |
| `discord-bot` | `7130650` | 2026-07-14 |
| `vault-app` | `8263939` | 2026-07-14 |
| `docker-apps` | `74a42e0` | 2026-07-14 |
| `terraform` | `eaa9770` | 2026-07-14 |

*Related: image promotion (docker-apps TechDocs) (docker-apps consumer side of
`.trigger-bump`), infra bootstrap (terraform-admin TechDocs) (where the pipeline trigger token
comes from), [`findings/2026-06-11-ci-queue-saturation.md`](https://github.com/tnoff/docs/blob/main/findings/2026-06-11-ci-queue-saturation.md) (the
investigation behind the S3-cache wiring and `.image-build-rules`
adoption), [`projects/ci-perf.md`](https://github.com/tnoff/docs/blob/main/projects/ci-perf.md) (closed 2026-08-23; carries the
full outcomes log, and the measured case for the one lever it did not
take — dropping the docker-save tarball handoff from
`.buildkit-build-check`).*
