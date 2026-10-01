# github-workflows

Reusable GitHub Actions workflows: the CI and release surface for the whole
fleet (tests, secret scans, image builds and pushes, tagging and releases,
Renovate, TechDocs publishing, image-pin bump dispatch). GitHub is canonical;
GitLab holds a read-only mirror that runs nothing.

## Using a workflow

Call a workflow from a consumer repo and pin it to a full commit SHA (there
are no floating `@v1` tags; Renovate keeps the SHA current):

```yaml
# .github/workflows/ci.yml in the consuming repo
jobs:
  pre-commit:
    uses: tnoff/github-workflows/.github/workflows/pre-commit.yml@<40-char-sha>
  contracts:
    uses: tnoff/github-workflows/.github/workflows/check-workflow-contracts.yml@<40-char-sha>
```

Add `check-workflow-contracts` to every repo that pins a workflow from here: an
input or secret mismatch fails at startup with no job and no check, so nothing
else will show it.

## Documentation

- [Reusable workflows guide](https://github.com/tnoff/github-workflows/blob/main/docs/ci-templates.md):
  catalogue of every workflow, the pinning rules, and the cross-repo contracts
  (image bump dispatch, TechDocs publish, branch cleanup).
- `docs/workflows/<name>.md`: generated inputs, secrets and outputs for each
  reusable workflow.
- [DEVELOPMENT.md](https://github.com/tnoff/github-workflows/blob/main/docs/DEVELOPMENT.md):
  linting and testing changes. [AGENTS.md](https://github.com/tnoff/github-workflows/blob/main/docs/AGENTS.md):
  compatibility rules for contributors and agents.

Pull requests and issues go to https://github.com/tnoff/github-workflows.
