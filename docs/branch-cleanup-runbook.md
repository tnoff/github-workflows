# Stale branch cleanup

Scheduled pruning of throwaway automation branches (`bump/*`,
`renovate/*`) that accumulate in GitLab because nothing deletes them.

## Why they pile up

The image-bump job in `docker-apps` (`.bump-image-pin-base`, see
image promotion (docker-apps TechDocs)) pushes a branch `bump/<source>-<tag>`
per image and opens an MR with `remove_source_branch: true`. GitLab only
honors that flag on **merge** — when a newer bump supersedes an older
one, the job *closes* the stale MR via the API and the branch is
orphaned. Renovate behaves the same way: `renovate/*` branches whose MRs
are never merged are not pruned (no `branchPrune` is configured).

A 2026-06-27 census of `docker-apps` found **90 branches, 78 of them
`bump/*`** (39 were `bump/discord-bot-*`), and only 2 open MRs. The
entire pile had no open MR.

## How the cleanup works

A reusable template `gitlab/branch-cleanup.yml` in `github-workflows`
defines `.branch-cleanup`. Consumers extend it and gate it on the
schedule source:

```yaml
branch-cleanup:
  extends: .branch-cleanup
  stage: cleanup
  image: $CI_ALPINE_UTILS_IMAGE
  rules:
    - if: $CI_PIPELINE_SOURCE == "schedule"
```

It deletes a branch only when **all** of these hold:

1. the name matches `CLEANUP_BRANCH_PATTERN` (default `^(bump|renovate)/`);
2. it is not `protected` and not the `default` branch;
3. it is **not** the source branch of any open MR;
4. its last commit is older than `CLEANUP_AGE_DAYS` (default **30**).

Everything else — `gitlab`, `secrets`, `fix/*`, `feat/*`,
`config-as-cm/*`, the `revert-*` UI reverts — falls outside the pattern
and is never a candidate. The allowlist is the safety guarantee, not a
blocklist.

Deletion is reversible by construction: a bump re-pushes on the next
image build, and Renovate recreates a branch if the dependency is still
outstanding. So a wrongly-deleted branch self-heals on the next run.

### Scheduling and token

No new schedule or token is needed. The job rides the **existing weekly
Renovate schedule** (`local.weekly_schedule` in `terraform/infra/repos.tf`,
cron `0 0 * * 0`) and reuses **`RENOVATE_TOKEN`** (the `tnoff-robot` bot
PAT, group-level, already `api`-scoped — covers branch deletion). Running
alongside Renovate is safe: cleanup only removes branches ≥30 days old
with no open MR, while Renovate's fresh branches are 0 days old and carry
open MRs.

## Going live (dry-run first)

The template ships `DRY_RUN: "true"`. The `docker-apps` rollout followed
this sequence and is now **live**:

1. Land `gitlab/branch-cleanup.yml` in `github-workflows`
   (`github-workflows!46`; a non-UTC `committed_date` parse fix landed in
   `github-workflows!47`).
2. In `docker-apps`, pin the new `github-workflows` SHA and add the
   include + the `branch-cleanup` job (in the existing `cleanup` stage) on
   the schedule rule — shipped dry-run in `docker-apps!423`, with the SHA
   bump for the date fix in `docker-apps!424`.
3. Let a scheduled pipeline run in dry-run; read its `would delete:` lines
   in the job log (validated against live data: 21 candidates, 0 parse
   errors, allowlist excluded every hand-made branch).
4. Flip `DRY_RUN: "false"` to go live (`docker-apps!433`).

The first live run (2026-06-30) deleted **23** stale `bump/*` branches
(sources: `discord-bot` ×14, `database-backup` ×3, `magic-mirror` ×3,
`personal-website` ×2, `oke-security-scanner` ×1); the allowlist held (no
hand-made branch touched) and the job exited clean.

## Rollout to the rest of the fleet

Once `docker-apps` proved the predicate live, the same wiring was extended
to every other `tnoff-projects` repo that has the Renovate include and an
active weekly schedule (19 repos). Each MR adds the `branch-cleanup.yml`
include (pinned `github-workflows@a5e9849f`, the date-fix SHA), a
`branch-cleanup` job in the existing **`renovate`** stage — these repos
have no `cleanup` stage, and the template's default `alpine:3` image is
used, so there is no `image:` override — and, where the repo already has
discord-notify wiring, a `notify-cleanup-failure` mirroring
`notify-renovate-failure`. All ship **live** (`DRY_RUN: "false"`).

| Repo | Wiring MR | Notify job |
|---|---|---|
| `docker-apps` | `docker-apps!423` / `!424` / `!433` (merged, live) | yes |
| `backup-tool` | `backup-tool!24` | yes |
| `ci-base-images` | `ci-base-images!20` | yes |
| `dappertable` | `dappertable!34` | yes |
| `database-backup` | `database-backup!49` | yes |
| `discord-bot` | `discord-bot!110` | yes |
| `eastbay` | `eastbay!24` | yes |
| `enheduanna` | `enheduanna!36` | yes |
| `harpocrates` | `harpocrates!60` | yes |
| `hathor` | `hathor!37` | yes |
| `magic-mirror-docker` | `magic-mirror-docker!33` | yes |
| `oci-bastion-keepalive` | `oci-bastion-keepalive!9` | yes |
| `oci-monitoring-exporter` | `oci-monitoring-exporter!8` | yes |
| `oke-security-scanner` | `oke-security-scanner!58` | yes |
| `personal-website` | `personal-website!24` | yes |
| `public-transit` | `public-transit!39` | yes |
| `terraform` | `terraform!154` | yes |
| `terraform-modules` | `terraform-modules!27` | yes |
| `MMM-BartTimes` | `MMM-BartTimes!9` | no (no discord-notify) |
| `terraform-admin` | `terraform-admin!12` | no (no discord-notify) |

All 20 wiring MRs are **merged and live** — `docker-apps` on 2026-06-30,
the 19 siblings on 2026-07-01 (`MMM-BartTimes` on 2026-06-30). The
rollout is complete: every `tnoff-projects` repo with an active weekly
schedule now prunes its own stale `bump/*` / `renovate/*` branches on the
weekly cron.

## Extending to other repos

The template is repo-agnostic. To cover another repo: add the
`github-workflows` include + a `branch-cleanup` job gated on
`$CI_PIPELINE_SOURCE == "schedule"`, and make sure the repo has a
pipeline schedule (terraform `schedules` map on the
`terraform-modules/gitlab/repo` module) and `RENOVATE_TOKEN` in scope.
Tune `CLEANUP_BRANCH_PATTERN` if the repo uses other automation
prefixes.

## Cross-references

- System context: [CI templates](ci-templates.md) (the template repo),
  image promotion (docker-apps TechDocs) (where `bump/*` branches originate).
- Template: `github-workflows` `gitlab/branch-cleanup.yml`.

---

## Verified against

| Project | SHA | Date |
|---|---|---|
| `github-workflows` | `b0c827a` | 2026-07-14 |
| `docker-apps` | `74a42e0` | 2026-07-14 |

Template added in `github-workflows!46` (non-UTC date fix in `!47`); wired live and **merged across all 20 repos** (`docker-apps` + 19 siblings), rollout completed 2026-07-01 — see **Rollout to the rest of the fleet** above.
