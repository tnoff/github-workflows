.PHONY: help lint install-actionlint check-actionlint

help: ## Show this help message
	@echo 'Usage: make [target]'
	@echo ''
	@echo 'Available targets:'
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'

check-actionlint: ## Check if actionlint is installed
	@which actionlint > /dev/null || (echo "❌ actionlint is not installed. Run 'make install-actionlint' to install it." && exit 1)
	@echo "✅ actionlint is installed"

install-actionlint: ## Install actionlint
	@echo "Installing actionlint..."
	@bash <(curl https://raw.githubusercontent.com/rhysd/actionlint/main/scripts/download-actionlint.bash)
	@sudo mv ./actionlint /usr/local/bin/
	@echo "✅ actionlint installed successfully"
	@actionlint -version

lint: check-actionlint ## Lint all GitHub Actions workflows
	@echo "Linting GitHub Actions workflows..."
	@actionlint .github/workflows/*.yml

lint-verbose: check-actionlint ## Lint workflows with verbose output
	@echo "Linting GitHub Actions workflows (verbose)..."
	@actionlint -verbose .github/workflows/*.yml

lint-json: check-actionlint ## Lint workflows and output JSON
	@actionlint -format '{{json .}}' .github/workflows/*.yml
