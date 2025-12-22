# Development Guide

This guide covers local development setup and workflow validation for the github-workflows repository.

## Prerequisites

- Git
- Python 3.8+ (for pre-commit framework)
- Docker (optional, for testing workflows locally with `act`)
- Make (optional, for convenience commands)

## Quick Start

Install pre-commit hooks to automatically validate workflows before committing:

```bash
# Install pre-commit hooks
pre-commit install

# Test the hooks on all files
pre-commit run --all-files
```

That's it! The hooks will now run automatically on every commit.

## Local Workflow Validation

### Installing actionlint

**actionlint** is a static checker for GitHub Actions workflow files. It catches syntax errors, type mismatches, and common mistakes before you push.

#### Option 1: Download Script (Recommended)

```bash
# Download and extract actionlint
bash <(curl https://raw.githubusercontent.com/rhysd/actionlint/main/scripts/download-actionlint.bash)

# Move to your local bin (choose one)
sudo mv ./actionlint /usr/local/bin/          # System-wide
mv ./actionlint ~/.local/bin/                 # User-local (ensure ~/.local/bin is in PATH)
```

#### Option 2: Using Make

```bash
make install-actionlint
```

This will download actionlint and prompt you to move it to `/usr/local/bin/`.

#### Option 3: Using Go

If you have Go installed:

```bash
go install github.com/rhysd/actionlint/cmd/actionlint@latest
```

#### Option 4: Using Package Managers

**macOS (Homebrew):**
```bash
brew install actionlint
```

**Arch Linux:**
```bash
pacman -S actionlint
```

**Other systems:** See [actionlint installation docs](https://github.com/rhysd/actionlint/blob/main/docs/install.md)

### Verify Installation

```bash
actionlint -version
```

You should see output like: `1.7.9 (built with go1.25.4 compiler for linux/amd64)`

## Running Workflow Checks

### Using the Lint Script

The repository includes a `lint.sh` script for convenience:

```bash
./lint.sh
```

This will:
- Check if actionlint is installed
- Lint all workflow files in `.github/workflows/`
- Display errors if any are found
- Exit with code 0 on success, 1 on failure

### Using Make

```bash
# Basic linting
make lint

# Verbose output (shows all checks)
make lint-verbose

# JSON output (useful for tooling/CI)
make lint-json

# Check if actionlint is installed
make check-actionlint
```

### Using actionlint Directly

```bash
# Lint all workflows
actionlint .github/workflows/*.yml

# Lint a specific workflow
actionlint .github/workflows/ocir-push.yml

# Verbose output
actionlint -verbose .github/workflows/*.yml

# Ignore specific rules
actionlint -ignore 'SC2016:' .github/workflows/*.yml
```

## What actionlint Checks

actionlint validates:

- ✅ **YAML syntax errors**
- ✅ **Invalid workflow configurations** (missing required fields, invalid values)
- ✅ **Type mismatches** in expressions (e.g., comparing string to number)
- ✅ **Unknown action names** or invalid action versions
- ✅ **Shell script errors** in `run:` steps (uses shellcheck)
- ✅ **Invalid contexts** (e.g., typos in `github.event.pull_request.title`)
- ✅ **Deprecated features** (old action syntax, deprecated commands)
- ✅ **Security issues** (e.g., unsafe use of `pull_request_target`)
- ✅ **Invalid job dependencies** and output references
- ✅ **Unreachable jobs** due to conditions

## Example Output

When issues are found:

```
.github/workflows/ocir-push.yml:48:20: property "build" is not defined in object type {build-and-push: {outputs: {image_tags: string; version: string}}} [expression]
   |
48 |         value: ${{ jobs.build.outputs.version }}
   |                    ^~~~~~~~~~~~~~~~~~~~~~~~~~
```

This shows:
- **File and line number** where the error occurred
- **Column number** for precise location
- **Description** of the issue
- **Context** showing the problematic line
- **Error type** in brackets

## Pre-commit Framework (Recommended)

This repository uses [pre-commit](https://pre-commit.com/) to automatically run checks before commits.

### Installation

**If pre-commit is not installed:**

```bash
# Using pip
pip install pre-commit

# Using Homebrew (macOS)
brew install pre-commit

# Using apt (Ubuntu/Debian)
sudo apt install pre-commit
```

### Setup

Install the git hooks:

```bash
cd /path/to/github-workflows
pre-commit install
```

This creates a `.git/hooks/pre-commit` file that runs automatically on `git commit`.

### What Gets Checked

The pre-commit configuration (`.pre-commit-config.yaml`) runs:

1. **trailing-whitespace** - Removes trailing whitespace
2. **end-of-file-fixer** - Ensures files end with a newline
3. **check-yaml** - Validates YAML syntax
4. **check-added-large-files** - Prevents committing large files
5. **check-merge-conflict** - Detects merge conflict markers
6. **mixed-line-ending** - Prevents mixed line endings
7. **yamllint** - Lints YAML files for style and syntax
8. **actionlint** - Validates GitHub Actions workflows

### Running Manually

```bash
# Run on all files
pre-commit run --all-files

# Run on staged files only
pre-commit run

# Run a specific hook
pre-commit run actionlint --all-files

# Run on specific files
pre-commit run --files .github/workflows/ocir-push.yml
```

### Bypassing Hooks

When you need to commit without running hooks:

```bash
git commit --no-verify
```

### Updating Hooks

Keep pre-commit hooks up to date:

```bash
# Update to latest versions
pre-commit autoupdate

# Update and run on all files
pre-commit autoupdate && pre-commit run --all-files
```

### Uninstalling

To remove the hooks:

```bash
pre-commit uninstall
```

## Testing Workflows Locally with act

**act** allows you to run GitHub Actions workflows locally using Docker.

### Install act

**macOS:**
```bash
brew install act
```

**Linux:**
```bash
curl https://raw.githubusercontent.com/nektos/act/master/install.sh | sudo bash
```

### Run workflows locally

```bash
# List available workflows
act -l

# Run a specific workflow
act -W .github/workflows/auto-tag.yml

# Run with secrets
act -s OCI_REGISTRY=iad.ocir.io/namespace -s OCI_USERNAME=user
```

## Additional Resources

- [actionlint Documentation](https://github.com/rhysd/actionlint)
- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [Reusable Workflows Guide](https://docs.github.com/en/actions/using-workflows/reusing-workflows)
- [act Documentation](https://github.com/nektos/act)
