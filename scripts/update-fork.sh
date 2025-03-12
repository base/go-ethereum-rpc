#!/bin/bash
set -e

# Configuration
CURRENT_GETH_VERSION="v1.15.5"
GETH_REPO="https://github.com/ethereum/go-ethereum.git"
TEMP_DIR=$(mktemp -d)
PACKAGE_PATH="rpc"
FAILED_PATCHES_DIR="failed_patches"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${GREEN}Starting update process for go-ethereum fork...${NC}"

# Check if we're in the root of the repository
if [ ! -f "go.mod" ]; then
    echo -e "${RED}Error: This script must be run from the root of your repository.${NC}"
    exit 1
fi

# Get the latest version of go-ethereum
echo -e "${YELLOW}Fetching latest go-ethereum version...${NC}"
git clone $GETH_REPO $TEMP_DIR
cd $TEMP_DIR
git fetch --tags
LATEST_GETH_VERSION=$(git describe --tags $(git rev-list --tags --max-count=1))
cd - > /dev/null

echo -e "${GREEN}Current go-ethereum version: ${CURRENT_GETH_VERSION}${NC}"
echo -e "${GREEN}Latest go-ethereum version: ${LATEST_GETH_VERSION}${NC}"

if [ "$CURRENT_GETH_VERSION" == "$LATEST_GETH_VERSION" ]; then
    echo -e "${GREEN}Already at the latest version. No update needed.${NC}"
    rm -rf $TEMP_DIR
    exit 0
fi

# Update go.mod with the latest version
echo -e "${YELLOW}Updating go.mod with the latest version...${NC}"
go get github.com/ethereum/go-ethereum@$LATEST_GETH_VERSION
go mod tidy

# Clone the full repository to get the complete history
echo -e "${YELLOW}Cloning the full go-ethereum repository...${NC}"
rm -rf $TEMP_DIR
git clone $GETH_REPO $TEMP_DIR

# Find commits that modified the RPC package between the current and latest versions
echo -e "${YELLOW}Finding commits that modified the RPC package...${NC}"
cd $TEMP_DIR
git fetch --tags
git log --pretty=format:"%H %s" $CURRENT_GETH_VERSION..$LATEST_GETH_VERSION -- $PACKAGE_PATH > /tmp/rpc_commits.txt
COMMIT_COUNT=$(wc -l < /tmp/rpc_commits.txt)
cd - > /dev/null

if [ "$COMMIT_COUNT" -eq 0 ]; then
    echo -e "${GREEN}No changes to the RPC package between ${CURRENT_GETH_VERSION} and ${LATEST_GETH_VERSION}.${NC}"
    echo -e "${GREEN}Only the go.mod file has been updated.${NC}"

    # Update the version in the update-fork.sh script
    # Fix for macOS sed which requires a different syntax
    if [[ "$OSTYPE" == "darwin"* ]]; then
        sed -i '' "s/CURRENT_GETH_VERSION=\".*\"/CURRENT_GETH_VERSION=\"${LATEST_GETH_VERSION}\"/" scripts/update-fork.sh
    else
        sed -i "s/CURRENT_GETH_VERSION=\".*\"/CURRENT_GETH_VERSION=\"${LATEST_GETH_VERSION}\"/" scripts/update-fork.sh
    fi

    rm -rf $TEMP_DIR
    exit 0
fi

echo -e "${GREEN}Found ${COMMIT_COUNT} commits that modified the RPC package.${NC}"

# Create a new branch for the update
BRANCH_NAME="update-geth-${LATEST_GETH_VERSION}"
git checkout -b $BRANCH_NAME

# Create directory for failed patches if it doesn't exist
mkdir -p $FAILED_PATCHES_DIR

# Try to cherry-pick each commit
echo -e "${YELLOW}Attempting to cherry-pick commits...${NC}"
SUCCESSFUL_PICKS=0
FAILED_PICKS=0

while read -r COMMIT_HASH COMMIT_MSG; do
    echo -e "${YELLOW}Cherry-picking commit: ${COMMIT_HASH} - ${COMMIT_MSG}${NC}"

    # Get the patch for just the RPC package changes
    cd $TEMP_DIR
    git show ${COMMIT_HASH} -- $PACKAGE_PATH > /tmp/commit.patch
    cd - > /dev/null

    # Apply the patch
    if git apply --check /tmp/commit.patch 2>/dev/null; then
        git apply /tmp/commit.patch
        git add $PACKAGE_PATH
        git commit -m "Cherry-pick: ${COMMIT_MSG}" -m "Original commit: ${COMMIT_HASH}"
        echo -e "${GREEN}Successfully applied changes from commit ${COMMIT_HASH}${NC}"
        SUCCESSFUL_PICKS=$((SUCCESSFUL_PICKS + 1))
    else
        echo -e "${RED}Failed to apply changes from commit ${COMMIT_HASH}${NC}"

        # Save the failed patch for later inspection
        PATCH_FILE="${FAILED_PATCHES_DIR}/failed_patch_${COMMIT_HASH}.patch"
        cp /tmp/commit.patch "$PATCH_FILE"

        # Show detailed error information
        echo -e "${RED}=== Detailed error information ===${NC}"
        echo -e "${RED}Commit: ${COMMIT_HASH}${NC}"
        echo -e "${RED}Message: ${COMMIT_MSG}${NC}"
        echo -e "${RED}Patch file saved to: ${PATCH_FILE}${NC}"
        echo -e "${RED}Error details:${NC}"
        git apply --check /tmp/commit.patch 2>&1 | sed 's/^/    /'

        # Show the patch content for context
        echo -e "${YELLOW}=== Patch content (first 10 lines) ===${NC}"
        head -n 10 /tmp/commit.patch | sed 's/^/    /'
        echo -e "${YELLOW}=== End of patch preview ===${NC}"

        echo -e "${RED}You may need to apply these changes manually.${NC}"
        FAILED_PICKS=$((FAILED_PICKS + 1))
    fi
done < /tmp/rpc_commits.txt

# Update the version in the update-fork.sh script
# Fix for macOS sed which requires a different syntax
if [[ "$OSTYPE" == "darwin"* ]]; then
    sed -i '' "s/CURRENT_GETH_VERSION=\".*\"/CURRENT_GETH_VERSION=\"${LATEST_GETH_VERSION}\"/" scripts/update-fork.sh
else
    sed -i "s/CURRENT_GETH_VERSION=\".*\"/CURRENT_GETH_VERSION=\"${LATEST_GETH_VERSION}\"/" scripts/update-fork.sh
fi

git add scripts/update-fork.sh
git commit -m "Update CURRENT_GETH_VERSION to ${LATEST_GETH_VERSION}"

# Clean up
rm -rf $TEMP_DIR
rm /tmp/rpc_commits.txt
rm -f /tmp/commit.patch

echo -e "${GREEN}Update process completed.${NC}"
echo -e "${GREEN}Successfully cherry-picked ${SUCCESSFUL_PICKS} commits.${NC}"
if [ "$FAILED_PICKS" -gt 0 ]; then
    echo -e "${RED}Failed to cherry-pick ${FAILED_PICKS} commits.${NC}"
    echo -e "${RED}Failed patches have been saved to the ${FAILED_PATCHES_DIR}/ directory for manual inspection.${NC}"
    echo -e "${RED}You may need to apply these changes manually.${NC}"
fi
echo -e "${YELLOW}Please review the changes, run tests, and push the branch if everything looks good.${NC}"
echo -e "${YELLOW}git push origin ${BRANCH_NAME}${NC}"

exit 0
