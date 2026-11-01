# Fleet mirror

`fleet-mirror.yml` is the hourly job that pushes GitHub `main` to the frozen
GitLab copies, so the GitLab side stays usable as break-glass instead of
freezing at each repo's flip commit. It is fleet automation, not a reusable
workflow: nothing calls it with `uses:`, and it takes no per-repo
configuration. It is modelled in Backstage as the `fleet-mirror` Component
(`type: service`), a subcomponent of `github-workflows`.

The reasoning behind the design (why a push from Actions, why no repo list, why
`ci.skip`, why it never force-pushes) is in the header comment of
[`fleet-mirror.yml`](https://github.com/tnoff/github-workflows/blob/main/.github/workflows/fleet-mirror.yml).
This page records how to operate it and what it depends on.

## What it does

| | |
|---|---|
| Schedule | Hourly (`17 * * * *`), plus manual `workflow_dispatch` |
| Reads | Every repo in the GitHub account, through a short-lived `tnoff-ci` App installation token |
| Writes | The matching project in the GitLab group `tnoff-projects`, as the `tnoff-ci` service account |
| Concurrency | One run at a time (`group: fleet-mirror`), never cancelled mid-push |
| Failure | A non-fast-forward or rejected push fails the run and is reported; it is never resolved by force-pushing |

A GitLab project is mirrored only if it has no enabled remote mirror of its own,
has a GitHub counterpart, and its default branch is a strict ancestor of
GitHub's. Everything else is skipped or fails loudly.

## Credentials

| Secret on this repo | Backstage resource | Source | Used for |
|---|---|---|---|
| `GITLAB_MIRROR_TOKEN` | `resource:default/gitlab-ci-api-key` | `gitlab_ci_api_key` in terraform-admin | GitLab API reads (project list, remote mirrors, branches) and the push. Needs scopes `read_api` and `write_repository` (or `api`) and the group Maintainer role (protected `main` requires it) |
| `CI_APP_CLIENT_ID`, `CI_APP_PRIVATE_KEY` | `resource:default/ci-github-app-key` | The `tnoff-ci` GitHub App | Minting the per-run GitHub token |

`GITLAB_MIRROR_TOKEN` is written to this repo's Actions secrets by
`terraform/infra/repos.tf` (`module.github_workflows`), from the same
`gitlab_ci_api_key` input that terraform-admin rotates. It is deliberately
written here only, not to every repo: one consumer is one copy to rotate.

## Rotating the GitLab token

1. Mint a new token on the `tnoff-ci` service account with `read_api` and
   `write_repository` (or `api`). `write_repository` alone fails every API call
   with a 403, which the 2026-11-01 rotation hit. A token's scopes cannot be
   edited afterwards, so a wrong scope means minting again. Do not mint it on a
   human user.
2. Follow the operator-rotated procedure in terraform-admin's
   `docs/secret-rotation.md` for `gitlab_ci_api_key`.
3. Land a change under `terraform/infra/` so `apply:infra` rewrites
   `GITLAB_MIRROR_TOKEN`.
4. Verify with a dry run, which still authenticates and reads GitLab:

   ```bash
   gh workflow run fleet-mirror.yml --repo tnoff/github-workflows -f dry_run=true
   gh run watch --repo tnoff/github-workflows
   ```

   A dry run proves the token authenticates and can read. It does not prove
   write scope; that is only exercised by a real push, which happens whenever a
   GitHub repo has moved ahead of its GitLab copy. Watch the next hourly run
   that pushes something.
5. Revoke the old token only after a run has succeeded with the new one.

## Failure modes

| Symptom | Cause | What to do |
|---|---|---|
| `GITLAB_MIRROR_TOKEN is unset` | The secret is missing from this repo | Apply `terraform/infra`; it writes the secret |
| Fails at the first GitLab call with 403 | Token lacks `read_api`, was revoked, or lost its Maintainer role | Check scopes and role; re-mint if a scope is missing (above) |
| One repo fails `not a fast-forward` | Someone wrote to the GitLab copy | Resolve by hand; the job will not force-push |
| App token step fails | `tnoff-ci` key rotated without updating `CI_APP_*` here | Update this repo's `CI_APP_*` secrets by hand (the bootstrap stack cannot own its own repo) |

Failures notify through `notify-failure.yml` like the repo's other scheduled
jobs.
