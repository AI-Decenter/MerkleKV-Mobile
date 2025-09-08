# GitHub Project Board Setup Guide

This guide explains how to set up and manage the "MerkleKV Mobile Roadmap" GitHub Project board for tracking all 39 issues across development phases.

## Quick Start

1. **Create the project board:**
   ```bash
   ./create_project.sh AI-Decenter/MerkleKV-Mobile
   ```

2. **Complete manual setup steps** (see output from script)

3. **Verify setup:**
   ```bash
   gh project list --owner AI-Decenter
   ```

## Project Structure

### Custom Fields

| Field | Type | Purpose | Values |
|-------|------|---------|---------|
| **Status** | Single-select | Workflow tracking | Backlog, In Progress, Review, Done |
| **Milestone** | Text | Phase organization | Auto-filled from GitHub milestones |
| **Labels** | Text | Category tracking | Comma-separated label list |
| **Effort Estimate** | Number | Planning | Engineer-days (S=1-2, M=3-5, L=8-12) |

### Saved Views (Milestone Filters)

Create these saved views for milestone-based project management:

- **Phase 1 — Core** (Issues #1-7): Foundation components
- **Phase 2 — Advanced** (Issues #8-11, #20): Advanced operations
- **Phase 3 — Replication** (Issues #12-19): Replication system  
- **Phase 4 — API & Testing** (Issues #21-25): Public API and testing
- **Security** (Issues #28-30): Security implementation
- **Documentation** (Issues #31-32): Documentation and migration
- **Mobile Optimization** (Issues #26, #33-34): Mobile-specific features
- **Platform Extension** (Issue #39): React Native bridge
- **Advanced Features** (Issue #38): Future complex data types

### Workflow States

```
Backlog → In Progress → Review → Done
```

- **Backlog**: Issues ready for development
- **In Progress**: Currently being worked on
- **Review**: Under code review or testing
- **Done**: Completed and merged

## Setup Instructions

### 1. Run Automation Script

```bash
# Make executable
chmod +x create_project.sh

# Create project board
./create_project.sh AI-Decenter/MerkleKV-Mobile
```

### 2. Manual Configuration

After running the script, complete these steps in the GitHub UI:

#### Enable Automations

1. Go to your project board settings
2. Navigate to **Workflows** 
3. Enable these automations:
   - **Auto-add items**: New issues from `AI-Decenter/MerkleKV-Mobile` → Status: `Backlog`
   - **Auto-archive items**: When issue closes → Status: `Done`

#### Create Saved Views

1. In the project board, click **+ New view**
2. Create views for each milestone:

**Phase 1 — Core View:**
- Filter: `Milestone:contains:"Phase 1"`
- Sort: Issue number ascending

**Phase 2 — Advanced View:**
- Filter: `Milestone:contains:"Phase 2"`
- Sort: Issue number ascending

**Phase 3 — Replication View:**
- Filter: `Milestone:contains:"Phase 3"`
- Sort: Issue number ascending

Continue for all milestones...

#### Set Initial Status

1. Select all items in the project board (Ctrl/Cmd+A)
2. Set **Status** field to `Backlog` for all items
3. Adjust individual items as needed

### 3. Verify Setup

```bash
# List your projects
gh project list --owner AI-Decenter

# View project details (use PROJECT_ID from script output)
gh project view <PROJECT_ID>

# List project items
gh project item-list <PROJECT_ID>
```

## Daily Usage

### For Developers

```bash
# Move issue to In Progress
gh project item-edit --project-id <PROJECT_ID> --url https://github.com/AI-Decenter/MerkleKV-Mobile/issues/5 --field-id Status --text "In Progress"

# Add effort estimate
gh project item-edit --project-id <PROJECT_ID> --url https://github.com/AI-Decenter/MerkleKV-Mobile/issues/5 --field-id "Effort Estimate" --number 3
```

### For Project Management

1. **Sprint Planning**: Use milestone views to see all issues in a phase
2. **Status Tracking**: Monitor Kanban board for workflow bottlenecks
3. **Effort Planning**: Use Effort Estimate field for capacity planning
4. **Progress Reporting**: Use Done column and closed issues for progress metrics

## Troubleshooting

### Project Creation Issues

If `create_project.sh` fails:

1. **Check permissions**: Ensure you have admin access to the repository/organization
2. **Manual creation**: Create project manually in GitHub UI, then use script to add issues
3. **Get project ID**: 
   ```bash
   gh project list --owner AI-Decenter
   # Use the ID in manual gh project commands
   ```

### Missing Issues

If issues aren't added automatically:

```bash
# Add specific issue manually
gh project item-add <PROJECT_ID> --url https://github.com/AI-Decenter/MerkleKV-Mobile/issues/1

# Add range of issues (modify script as needed)
for i in {1..39}; do
  gh project item-add <PROJECT_ID> --url https://github.com/AI-Decenter/MerkleKV-Mobile/issues/$i
done
```

### Field Configuration

If custom fields aren't working:

1. Check field names match exactly (case-sensitive)
2. Recreate fields manually in project settings
3. Use `gh project field-list <PROJECT_ID>` to see existing fields

## Best Practices

### Issue Management

- **Always assign milestones** to new issues for proper filtering
- **Use consistent labels** for better categorization
- **Update status regularly** to reflect actual progress
- **Add effort estimates** during planning sessions

### Sprint Organization

- Use milestone views for sprint planning
- Focus on one phase at a time for cohesive development
- Track blockers and dependencies in issue descriptions
- Regular status updates in team meetings

### Reporting

- Weekly review of kanban board progress
- Milestone completion tracking
- Effort estimate vs actual time analysis
- Blocker identification and resolution

## Advanced Configuration

### Custom Automations

Create GitHub Actions workflows for:
- Auto-assignment based on labels
- Slack notifications for status changes
- Automated effort estimate suggestions
- Milestone progress reporting

### Integration with Tools

- **Slack**: Project board updates in team channels
- **Jira**: Sync for enterprise project management
- **Time tracking**: Integration with development tools
- **Reporting**: Custom dashboards and metrics

## Support

If you encounter issues:

1. Check GitHub's Projects v2 documentation
2. Verify GitHub CLI version: `gh --version`
3. Check repository permissions
4. Review project board settings in GitHub UI

For questions about the MerkleKV Mobile project structure, refer to the main README.md and individual issue descriptions.
