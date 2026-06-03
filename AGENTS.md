# AGENTS.md

Guidance for AI coding agents working in this repository. For the full
catalogue of reusable workflows / templates (inputs, secrets, outputs,
examples) see [README.md](README.md); for local setup, linting, and
testing changes see [DEVELOPMENT.md](DEVELOPMENT.md).

## What this repo is

A central catalogue of two parallel sets of reusable CI building blocks
consumed by application repositories:

| Layout | Consumer |
|---|---|
| `.github/workflows/*.yml` | GitHub Actions repositories (`uses: tnoff/github-workflows/.github/workflows/<file>@<ref>`) |
| `gitlab/*.yml` | GitLab CI repositories (`include: { project: 'tnoff-projects/github-workflows', file: '/gitlab/<file>', ref: '<ref>' }`) |

The GitHub Actions and GitLab CI sets are not always one-to-one — some
templates exist in only one. The README has the authoritative list for
each.

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

### Two parallel template surfaces — keep them in sync where they overlap

`gitlab/tag.yml` and `.github/workflows/tag.yml` (and similarly for
`bump-version`, `discord-notify`, etc.) share semantics. When you change
the behaviour of one, audit the other for the same change — drifting
the GitHub and GitLab versions of "what should be the same template"
creates the same class of bug across every consumer.

### VERSION file is the single source of truth for app versions

Apps that consume `ocir-push.yml` / `buildkit-docker-push.yml` read
their version from a `VERSION` file at the repo root. Rules:

- Semantic versioning (`MAJOR.MINOR.PATCH`)
- **No `v` prefix** (workflows fail on `v0.0.4`)
- No trailing whitespace

`bump-version.yml` / `gitlab/bump-version.yml` increments this file
automatically; `tag.yml` / `gitlab/tag.yml` reads it and creates the
matching git tag.

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

### Local validation for GitLab CI

`actionlint` only covers GitHub Actions. For changes to `gitlab/`
templates, validate locally with `gitlab-ci-local` before pushing — it
catches stage ordering, `extends` misuse, and variable interpolation
bugs that GitLab's server-side lint won't flag until pipeline run time.

## Canonical remote

The authoritative remote is GitLab:
`gitlab.com/tnoff-projects/github-workflows`. The GitHub remote is a
mirror used for GitHub Actions consumers. New GitLab CI `include:`
references should use `project: 'tnoff-projects/github-workflows'`.
