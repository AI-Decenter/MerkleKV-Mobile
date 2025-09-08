#!/bin/sh
# create_project.sh - Create GitHub Project board for MerkleKV Mobile Roadmap
# Usage: ./create_project.sh <owner/repo>

set -e

if [ $# -ne 1 ]; then
    echo "Usage: $0 <owner/repo>"
    echo "Example: $0 AI-Decenter/MerkleKV-Mobile"
    exit 1
fi

REPO="$1"
PROJECT_TITLE="MerkleKV Mobile Roadmap"
PROJECT_DESC="Project management board for MerkleKV Mobile development across all milestones and phases"

# Extract owner from repo
OWNER=$(echo "$REPO" | cut -d'/' -f1)

echo "Creating GitHub Project board for repository: $REPO"
echo "Project: $PROJECT_TITLE"

# Step 1: Create the project (try org-level first, fall back to user-level)
echo "Creating project..."
PROJECT_ID=""
if gh project create --owner "$OWNER" --title "$PROJECT_TITLE" --body "$PROJECT_DESC" >/dev/null 2>&1; then
    echo "✓ Created org-level project: $PROJECT_TITLE"
    # Get the project ID - this is a bit tricky with gh CLI
    PROJECT_ID=$(gh project list --owner "$OWNER" --format json | jq -r ".[] | select(.title == \"$PROJECT_TITLE\") | .id" | head -1)
else
    echo "⚠ Org-level project creation failed, trying user-level..."
    if gh project create --title "$PROJECT_TITLE" --body "$PROJECT_DESC" >/dev/null 2>&1; then
        echo "✓ Created user-level project: $PROJECT_TITLE"
        PROJECT_ID=$(gh project list --format json | jq -r ".[] | select(.title == \"$PROJECT_TITLE\") | .id" | head -1)
    else
        echo "❌ Failed to create project. Check permissions and try manually."
        exit 1
    fi
fi

if [ -z "$PROJECT_ID" ]; then
    echo "❌ Could not determine project ID. Please check 'gh project list' and update script manually."
    echo "   Run: gh project list --owner $OWNER"
    echo "   Then update PROJECT_ID variable in this script."
    exit 1
fi

echo "✓ Project ID: $PROJECT_ID"

# Step 2: Create custom fields
echo "Creating custom fields..."

# Status field (single-select)
echo "  Creating Status field..."
gh project field-create "$PROJECT_ID" --name "Status" --data-type "SINGLE_SELECT" \
    --single-select-option "Backlog" \
    --single-select-option "In Progress" \
    --single-select-option "Review" \
    --single-select-option "Done" 2>/dev/null || echo "    Status field may already exist"

# Milestone field (text)
echo "  Creating Milestone field..."
gh project field-create "$PROJECT_ID" --name "Milestone" --data-type "TEXT" 2>/dev/null || echo "    Milestone field may already exist"

# Labels field (text - unfortunately gh CLI doesn't support multi-select yet)
echo "  Creating Labels field..."
gh project field-create "$PROJECT_ID" --name "Labels" --data-type "TEXT" 2>/dev/null || echo "    Labels field may already exist"

# Effort Estimate field (number)
echo "  Creating Effort Estimate field..."
gh project field-create "$PROJECT_ID" --name "Effort Estimate" --data-type "NUMBER" 2>/dev/null || echo "    Effort Estimate field may already exist"

# Step 3: Add all issues to the project
echo "Adding issues to project..."
for issue_num in $(seq 1 39); do
    echo "  Adding issue #$issue_num..."
    gh project item-add "$PROJECT_ID" --url "https://github.com/$REPO/issues/$issue_num" 2>/dev/null || echo "    Issue #$issue_num may already be in project"
done

# Step 4: Configure automation (this requires manual setup in GitHub UI)
echo ""
echo "✓ Project board created successfully!"
echo ""
echo "🔧 MANUAL SETUP REQUIRED:"
echo "   1. Visit: https://github.com/orgs/$OWNER/projects or https://github.com/users/$OWNER/projects"
echo "   2. Open the '$PROJECT_TITLE' project"
echo "   3. Go to Settings (⚙️) > Workflows"
echo "   4. Enable these automations:"
echo "      - Auto-add new issues from $REPO to project (Status: Backlog)"
echo "      - When issue closes, set Status to Done"
echo "   5. Create saved views for milestones:"
echo "      - Phase 1 — Core (filter: Milestone contains 'Phase 1')"
echo "      - Phase 2 — Advanced (filter: Milestone contains 'Phase 2')"
echo "      - Phase 3 — Replication (filter: Milestone contains 'Phase 3')"
echo "      - Phase 4 — Anti-Entropy (filter: Milestone contains 'Phase 4')"
echo "      - Security (filter: Milestone contains 'Security')"
echo "      - Documentation (filter: Milestone contains 'Documentation')"
echo "      - Platform Extension (filter: Milestone contains 'Platform Extension')"
echo "      - Advanced Features (filter: Milestone contains 'Advanced Features')"
echo ""
echo "📋 PROJECT DETAILS:"
echo "   Title: $PROJECT_TITLE"
echo "   ID: $PROJECT_ID"
echo "   Issues added: #1-#39"
echo "   Custom fields: Status, Milestone, Labels, Effort Estimate"
echo ""
echo "🔗 ACCESS PROJECT:"
echo "   gh project view $PROJECT_ID"
echo "   Or visit GitHub and search for '$PROJECT_TITLE'"

# Step 5: Try to set initial Status for all items to "Backlog"
echo ""
echo "Setting initial status to 'Backlog' for all items..."
# Note: This is complex with gh CLI as we need item IDs, which are hard to get
# For now, we'll just inform the user to do this manually
echo "⚠ Please manually set Status to 'Backlog' for all items in the project board"
echo "  This can be done by:"
echo "  1. Opening the project board"
echo "  2. Selecting all items (Ctrl/Cmd+A)"
echo "  3. Setting Status field to 'Backlog' in bulk"

echo ""
echo "✅ Project setup complete! Check the manual setup steps above."
