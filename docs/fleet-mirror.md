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
| `GITLAB_MIRROR_TOKEN` | `resource:default/gitlab-ci-api-key` | `gitlab_group_service_account_access_token.fleet_mirror` in `terraform/infra/gitlab.tf` | GitLab API reads (project list, remote mirrors, branches) and the push. Scopes `read_api` and `write_repository`, on the `tnoff-ci` service account with the group Maintainer role (protected `main` requires it) |
| `CI_APP_CLIENT_ID`, `CI_APP_PRIVATE_KEY` | `resource:default/ci-github-app-key` | The `tnoff-ci` GitHub App | Minting the per-run GitHub token |

`GITLAB_MIRROR_TOKEN` is minted by `terraform/infra` and written to this repo's
Actions secrets by `terraform/infra/repos.tf` (`module.github_workflows`). There
is no operator-held copy: nobody mints or pastes this token. It is deliberately
written here only, not to every repo: one consumer is one copy to rotate.

## Rotating the GitLab token

The token expires after 90 days. `rotation_configuration` (`rotate_before_days = 14`,
`expiration_days = 90`) makes a `terraform apply` that runs in the last 14 days
re-mint it and rewrite the secret in the same apply. Outside that window an apply
changes nothing.

`apply:infra` runs only when `infra/` changes, so do not wait for that. Inside the
window (days 76 to 90 after minting), dispatch a full apply:

1. Run `gh workflow run apply.yml --repo tnoff/terraform` (from `main` only).
   The token minted on 2026-11-01 opens its window about 2027-01-16 and expires
   about 2027-01-30.
2. Confirm `apply:infra` is green. It re-minted the token and rewrote
   `GITLAB_MIRROR_TOKEN` here.
3. To rotate early, raise `rotate_before_days` above the days remaining and land
   it under `terraform/infra/` as a normal PR. Check that the `apply:infra` plan
   shows the token being replaced; if it does not, the window has not opened.
4. Verify with a dry run, which still authenticates and reads GitLab:

   ```bash
   gh workflow run fleet-mirror.yml --repo tnoff/github-workflows -f dry_run=true
   gh run watch --repo tnoff/github-workflows
   ```

   A dry run proves the token authenticates and can read. It does not prove
   write scope; that is only exercised by a real push, which happens whenever a
   GitHub repo has moved ahead of its GitLab copy. Watch the next hourly run
   that pushes something.
   Terraform replaces the old token, so there is nothing to revoke by hand.
   A run that failed with a 403 after a rotation means the new token is
   missing a scope; fix `scopes` in `infra/gitlab.tf`.

## Failure modes

| Symptom | Cause | What to do |
|---|---|---|
| `GITLAB_MIRROR_TOKEN is unset` | The secret is missing from this repo | Apply `terraform/infra`; it writes the secret |
| 401 from GitLab on every run | The token expired: no apply ran in the 14-day window | Run `gh workflow run apply.yml --repo tnoff/terraform` and check that `apply:infra` replaces the token. If it only plans no change, raise `rotate_before_days` in `infra/gitlab.tf` |
| Fails at the first GitLab call with 403 | Token lacks `read_api`, was revoked, or lost its Maintainer role | Check `scopes` in `terraform/infra/gitlab.tf` and the service account's group role |
| One repo fails `not a fast-forward` | Someone wrote to the GitLab copy | Resolve by hand; the job will not force-push |
| App token step fails | `tnoff-ci` key rotated without updating `CI_APP_*` here | Update this repo's `CI_APP_*` secrets by hand (the bootstrap stack cannot own its own repo) |

Failures notify through `notify-failure.yml` like the repo's other scheduled
jobs.
