#!/bin/bash
# Lint GitHub Actions workflows using actionlint

set -e

# Check if actionlint is installed
if ! command -v actionlint &> /dev/null; then
    echo "❌ actionlint is not installed"
    echo ""
    echo "To install actionlint, run one of the following:"
    echo ""
    echo "  # Using the install script:"
    echo "  bash <(curl https://raw.githubusercontent.com/rhysd/actionlint/main/scripts/download-actionlint.bash)"
    echo "  sudo mv ./actionlint /usr/local/bin/"
    echo ""
    echo "  # Or using make:"
    echo "  make install-actionlint"
    echo ""
    echo "  # Or using go:"
    echo "  go install github.com/rhysd/actionlint/cmd/actionlint@latest"
    echo ""
    exit 1
fi

echo "🔍 Linting GitHub Actions workflows..."
echo ""

# Run actionlint on all workflow files
actionlint .github/workflows/*.yml

if [ $? -eq 0 ]; then
    echo ""
    echo "✅ All workflows passed linting!"
else
    echo ""
    echo "❌ Linting found issues"
    exit 1
fi
