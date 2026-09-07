# AGENTS.md

Guidance for AI coding agents working in this repository. For the full
catalogue of reusable workflows / templates (inputs, secrets, outputs,
examples) see [README.md](README.md); for local setup, linting, and
testing changes see [DEVELOPMENT.md](DEVELOPMENT.md).

## What this repo is

A central catalogue of reusable CI building blocks consumed by application
repositories:

| Layout | Consumer |
|---|---|
| `.github/workflows/*.yml` | GitHub Actions repositories (`uses: tnoff/github-workflows/.github/workflows/<file>@<ref>`) |

The README has the authoritative list. A parallel `gitlab/*.yml` surface
existed until 2026-09-07, when GitLab CI was retired fleet-wide; GitLab is now
a readable mirror that runs nothing. Several workflow headers still explain
themselves by contrast with the GitLab template they were ported from — that
history is deliberate, but the files it names are gone.

## What this repo is NOT

It does not host any consumer-side workflow / pipeline. It only exports
reusable building blocks. The repo's own `.github/workflows/auto-tag.yml`
(or similar self-management workflow) is internal plumbing for tagging
*this* repo and is not a public surface.

## Non-obvious rules to honour

### Consumers pin by `@v<N>` or by commit SHA — preserve backwards compatibility

Apps reference these workflows by version tag (`@v0`, `@v1`) or commit
SHA. Any change that alters the inputs, secrets, outputs, or behaviour
of an existing workflow is a **breaking change** and must go behind a
new major version tag. Documentation-only or new-input-with-default
changes can ride the existing tag.

### VERSION file is the single source of truth for app versions

Apps that consume `ocir-push.yml` / `buildkit-docker-push.yml` read
their version from a `VERSION` file at the repo root. Rules:

- Semantic versioning (`MAJOR.MINOR.PATCH`)
- **No `v` prefix** (workflows fail on `v0.0.4`)
- No trailing whitespace

`bump-version.yml` increments this file automatically; `tag.yml` reads it
and creates the matching git tag.

### Standard image tagging

When `ocir-push.yml` / `buildkit-docker-push.yml` push an image they
produce three tags on `main`:

- `<version>` — from the VERSION file (e.g. `0.0.4`)
- `<commit-sha>` — 7-character short SHA
- `latest` — only on main builds

On PRs / MRs the workflow only produces the SHA tag (and may build
without pushing, depending on inputs).

Downstream Kubernetes manifests should reference pinned SHA tags in
prod and `latest` only in dev — this is enforced by `conftest` policies
in the [`docker-apps`](../docker-apps) repo.

### Pre-commit + actionlint are the gate

Every PR runs the pre-commit suite. `actionlint` catches workflow
syntax / expression errors before they make it into a release. Don't
disable hooks (`--no-verify`) when committing — if a hook is wrong, fix
the hook config or the file, not the bypass. See
[DEVELOPMENT.md](DEVELOPMENT.md) for setup.

## Canonical remote

The authoritative remote is **GitHub**: `github.com/tnoff/github-workflows`.
Open pull requests there. This flipped on 2026-08-26 (see the docs corpus,
`projects/github-canonical-migration.md`); before that GitLab was canonical
and GitHub was a push mirror, so anything claiming otherwise predates the
flip.

The GitLab copy is a **readable mirror only**, kept current hourly by
`.github/workflows/fleet-mirror.yml`. It runs no CI: `.gitlab-ci.yml` and the
13 `gitlab/*.yml` templates were deleted fleet-wide on 2026-09-07 when the
GitLab break-glass path was withdrawn rather than repaired (see the docs
corpus, `projects/github-canonical-migration.md`, "Continuity when GitHub is
down"). Do not reintroduce a GitLab CI surface here.
