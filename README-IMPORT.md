# GitHub Issues Import Automation Kit

This automation kit updates existing GitHub issues #1-37 in the AI-Decenter/MerkleKV-Mobile repository using corrected issue content.

## Prerequisites

1. **GitHub CLI**: Install and authenticate with `gh auth login`
2. **Python 3**: Required for the update script
3. **POSIX shell**: bash, zsh, or sh (Windows users: use WSL or Git Bash)
4. **Repository access**: Write permissions to AI-Decenter/MerkleKV-Mobile

## Quick Start

1. Ensure you have the corrected issues file: `ISSUES_CORRECTED.md`
2. Run the scripts in order:

```bash
# 1. Create labels (idempotent)
./labels.sh AI-Decenter/MerkleKV-Mobile

# 2. Create milestones (idempotent)  
./milestones.sh AI-Decenter/MerkleKV-Mobile

# 3. Split issues into individual files
./split_issues.sh ISSUES_CORRECTED.md out_issues

# 4. Update issues (dry-run first)
python3 update_issues.py --repo AI-Decenter/MerkleKV-Mobile --dir out_issues --dry-run

# 5. Update issues (live run)
python3 update_issues.py --repo AI-Decenter/MerkleKV-Mobile --dir out_issues
```

## Alternative: Batch Files

If you have four separate batch files instead of one combined file:

```bash
# The split_issues.sh script will automatically detect and concatenate them
./split_issues.sh batch1.md out_issues batch2.md batch3.md batch4.md
```

## Verification Checklist

After running all scripts:

- [ ] Labels exist: `gh label list --repo AI-Decenter/MerkleKV-Mobile`
- [ ] Milestones exist: `gh milestone list --repo AI-Decenter/MerkleKV-Mobile`
- [ ] Issue #1 updated: `gh issue view 1 --repo AI-Decenter/MerkleKV-Mobile`
- [ ] Issue #37 updated: `gh issue view 37 --repo AI-Decenter/MerkleKV-Mobile`
- [ ] Check random issues have correct titles, labels, and milestones

## Troubleshooting

**Authentication issues**: Run `gh auth login` and follow prompts

**Permission denied**: Ensure you have write access to the repository

**Missing issues**: This kit assumes issues #1-37 already exist. If numbering differs, create a mapping CSV and modify the Python script accordingly.

**Dry-run shows errors**: Fix the underlying issues before running live updates

**Script failures**: All scripts exit with clear error messages. Check the specific error and requirements.

## Rollback

To rollback changes:

1. **Labels**: Delete manually via GitHub UI or `gh label delete <name>`
2. **Milestones**: Delete via GitHub UI or `gh milestone delete <title>`
3. **Issues**: No automatic rollback - you'll need to restore from backup or previous state

## Safety Features

- All scripts are idempotent (safe to re-run)
- Dry-run mode shows planned changes before execution
- Labels and milestones are added, not replaced (preserves existing)
- Issue numbers are preserved (no renumbering)
- Proper error handling and validation
