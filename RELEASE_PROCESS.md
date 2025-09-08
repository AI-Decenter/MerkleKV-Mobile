# Release Process

This document outlines the release process for MerkleKV Mobile, ensuring consistent, reliable releases that maintain compatibility with the Locked Specification v1.0.

## 📋 Version Strategy

### Semantic Versioning

MerkleKV Mobile follows [Semantic Versioning (SemVer)](https://semver.org/) with strict adherence to Locked Spec v1.0 constraints:

**MAJOR.MINOR.PATCH** (e.g., 1.2.3)

- **MAJOR** (X.0.0): Breaking changes, spec violations, or wire format changes
- **MINOR** (1.X.0): New features, backward-compatible additions
- **PATCH** (1.2.X): Bug fixes, security patches, performance improvements

### 🔒 Locked Spec v1.0 Constraints

**For v1.x releases, the following are IMMUTABLE:**

- MQTT-only transport (QoS=1, retain=false)
- Topic structure: `{prefix}/{client_id}/cmd|res` and `{prefix}/replication/events`
- Size limits: key ≤256B, value ≤256KiB, command ≤512KiB
- Timeouts: 10/20/30 seconds for command/replication/connection
- Reconnect backoff: 1→32 seconds with ±20% jitter
- LWW conflict resolution with vector timestamps
- Operation idempotency and deterministic behavior

**Any changes to these constraints require a MAJOR version bump (v2.0.0+).**

## 🚀 Release Types

### 🔧 Patch Releases (1.2.X)

**Frequency:** As needed for critical fixes
**Timeline:** 1-3 days from fix to release

**Criteria:**
- Bug fixes that don't change APIs
- Security patches
- Performance improvements
- Documentation fixes
- Dependency updates (non-breaking)

**Process:**
1. Create hotfix branch from latest release tag
2. Apply minimal fix with tests
3. Fast-track review and merge
4. Tag and release immediately

### ✨ Minor Releases (1.X.0)

**Frequency:** Monthly or bi-monthly
**Timeline:** 1-2 weeks from feature complete to release

**Criteria:**
- New features (backward compatible)
- API additions (no breaking changes)
- Significant performance improvements
- New mobile platform features
- Enhanced MQTT integration

**Process:**
1. Feature freeze announcement
2. Release candidate (RC) builds
3. Community testing period
4. Final release after validation

### 💥 Major Releases (X.0.0)

**Frequency:** Rare, only for spec changes
**Timeline:** 3-6 months planning and development

**Criteria:**
- Locked Spec changes (v2.0+ only)
- Breaking API changes
- Wire format modifications
- Architectural overhauls

**Process:**
1. RFC process for breaking changes
2. Extended alpha/beta testing
3. Migration guide development
4. Coordinated ecosystem updates

## 📅 Release Schedule

### Regular Release Cycle

**Week 1-2:** Development and feature work
**Week 3:** Feature freeze, testing, and stabilization
**Week 4:** Release candidate, final testing, and release

### Emergency Releases

**Critical security issues:** Immediate hotfix release
**Critical bugs affecting spec compliance:** Priority patch release
**Mobile platform compatibility issues:** Expedited minor release

## ✅ Release Checklist

### 🏁 Pre-Release Phase

**Code Quality:**
- [ ] All CI/CD checks pass
- [ ] Test coverage ≥80%
- [ ] No known critical bugs
- [ ] Performance regression tests pass
- [ ] Mobile platform compatibility verified

**Locked Spec Compliance:**
- [ ] Spec compliance tests pass
- [ ] Wire format compatibility verified
- [ ] Timeout/backoff behavior validated
- [ ] Idempotency tests pass
- [ ] Determinism tests pass
- [ ] MQTT-only constraint validated

**Documentation:**
- [ ] CHANGELOG.md updated
- [ ] API documentation current
- [ ] Migration guides (if breaking changes)
- [ ] Security advisories (if applicable)
- [ ] Examples and tutorials updated

**Testing:**
- [ ] Unit tests pass (all platforms)
- [ ] Integration tests pass
- [ ] MQTT broker compatibility tests
- [ ] Mobile platform tests (iOS/Android)
- [ ] Performance benchmark tests
- [ ] Security audit completed

### 🏷️ Release Tagging

**Tag Format:** `v{MAJOR}.{MINOR}.{PATCH}` (e.g., `v1.2.3`)

**Tag Creation:**
```bash
# Create annotated tag
git tag -a v1.2.3 -m "Release v1.2.3"

# Push tag to trigger release
git push origin v1.2.3
```

**Release Notes Format:**
```markdown
# MerkleKV Mobile v1.2.3

## 🎯 Highlights
- Major feature or fix summary

## ✨ New Features
- Feature 1 description
- Feature 2 description

## 🐛 Bug Fixes
- Bug fix 1 description
- Bug fix 2 description

## ⚡ Performance Improvements
- Performance improvement 1
- Performance improvement 2

## 🔒 Security Updates
- Security fix 1 (if applicable)

## 🏗️ Technical Changes
- Technical change 1
- Technical change 2

## 📱 Mobile Platform Updates
- iOS-specific changes
- Android-specific changes
- React Native bridge updates

## 🔧 Dependencies
- Updated dependency 1 to vX.Y.Z
- Added dependency 2 for feature X

## 📋 Locked Spec v1.0 Compliance
✅ All changes maintain Locked Spec v1.0 compatibility
✅ No wire format changes
✅ MQTT-only transport preserved
✅ Size and timeout constraints maintained

## 🚀 Upgrade Instructions
[Upgrade steps if needed]

## 🗂️ Assets
- Source code (zip)
- Source code (tar.gz)
- [Platform-specific binaries if applicable]

**Full Changelog**: https://github.com/AI-Decenter/MerkleKV-Mobile/compare/v1.2.2...v1.2.3
```

### 📦 Release Artifacts

**Source Code:**
- [ ] Source code archive (zip/tar.gz)
- [ ] Source code verification (checksums)

**Mobile Packages:**
- [ ] npm package published
- [ ] React Native package validated
- [ ] iOS CocoaPods compatibility
- [ ] Android Maven compatibility

**Documentation:**
- [ ] Release notes published
- [ ] Documentation site updated
- [ ] API reference updated
- [ ] Examples repository updated

### 🔍 Post-Release Validation

**Immediate Verification:**
- [ ] Package installation works
- [ ] Basic functionality tests
- [ ] Mobile platform deployment
- [ ] MQTT broker connectivity

**Community Monitoring:**
- [ ] Monitor issue reports
- [ ] Check community feedback
- [ ] Track adoption metrics
- [ ] Respond to questions promptly

## 🛠️ Release Automation

### CI/CD Pipeline

**Automated Checks:**
```yaml
# .github/workflows/release.yml
name: Release
on:
  push:
    tags: ['v*']
jobs:
  release:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4
      
      - name: Setup Node.js
        uses: actions/setup-node@v4
        with:
          node-version: '18'
          registry-url: 'https://registry.npmjs.org'
      
      - name: Install dependencies
        run: npm ci
      
      - name: Run tests
        run: npm test
      
      - name: Run spec compliance tests
        run: npm run test:spec
      
      - name: Build package
        run: npm run build
      
      - name: Publish to npm
        run: npm publish
        env:
          NODE_AUTH_TOKEN: ${{ secrets.NPM_TOKEN }}
      
      - name: Create GitHub Release
        uses: actions/create-release@v1
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

**Automated Publishing:**
- [ ] npm package publishing
- [ ] GitHub release creation
- [ ] Documentation deployment
- [ ] Notification dispatch

### Quality Gates

**Merge Requirements:**
- All CI checks pass
- Code review approval (≥2 reviewers)
- Security review (for security-related changes)
- Spec compliance verification

**Release Approval:**
- [ ] Maintainer approval
- [ ] Security team approval (if applicable)
- [ ] Community notification sent

## 🚨 Emergency Procedures

### Critical Security Issues

1. **Immediate Response** (within 24 hours):
   - Assess impact and scope
   - Develop minimal fix
   - Create security advisory

2. **Hotfix Release** (within 48 hours):
   - Fast-track review process
   - Emergency testing protocol
   - Coordinated disclosure

3. **Post-Release** (within 72 hours):
   - Monitor for regressions
   - Community communication
   - Security audit follow-up

### Critical Bug Fixes

1. **Assessment** (within 8 hours):
   - Impact analysis
   - Spec compliance check
   - Mobile platform verification

2. **Hotfix Development** (within 24 hours):
   - Minimal reproducible fix
   - Regression test addition
   - Expedited review

3. **Emergency Release** (within 48 hours):
   - Tag and publish immediately
   - Community notification
   - Monitor for issues

## 📞 Release Team Contacts

**Release Manager:** releases@ai-decenter.org
**Security Team:** security@ai-decenter.org
**Technical Lead:** tech-lead@ai-decenter.org
**Community Manager:** community@ai-decenter.org

## 📚 References

- [Semantic Versioning](https://semver.org/)
- [Keep a Changelog](https://keepachangelog.com/)
- [GitHub Releases Guide](https://docs.github.com/en/repositories/releasing-projects-on-github)
- [npm Publishing Guide](https://docs.npmjs.com/creating-and-publishing-unscoped-public-packages)

---

**For questions about the release process, create an issue or contact the release team at releases@ai-decenter.org**
