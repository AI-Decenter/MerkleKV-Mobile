# Changelog

All notable changes to MerkleKV Mobile will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html) with strict Locked Specification v1.0 compliance.

## [Unreleased]

### Added
- Initial repository structure and development setup
- Comprehensive automation scripts for GitHub issue management
- Project board automation with milestone-based organization
- Complete repository hygiene and process documentation

### Changed
- Established Locked Specification v1.0 constraints for all development

### Deprecated
- None

### Removed
- None

### Fixed
- None

### Security
- Established security policy and vulnerability disclosure process
- Implemented secure MQTT connection requirements (TLS ≥1.2)
- Defined ACL and access control best practices

### 🔒 Locked Spec v1.0 Compliance
- ✅ MQTT-only transport established (QoS=1, retain=false)
- ✅ Topic structure defined: `{prefix}/{client_id}/cmd|res`
- ✅ Size limits established: key ≤256B, value ≤256KiB, command ≤512KiB
- ✅ Timeout constraints defined: 10/20/30 seconds
- ✅ Reconnect backoff specified: 1→32s ±20% jitter
- ✅ LWW conflict resolution with vector timestamps
- ✅ Operation idempotency and deterministic behavior requirements

---

## Template for Future Releases

<!-- 
## [X.Y.Z] - YYYY-MM-DD

### Added
- New features and functionality

### Changed
- Changes to existing functionality

### Deprecated
- Features that will be removed in future versions

### Removed
- Features removed in this version

### Fixed
- Bug fixes and corrections

### Security
- Security improvements and vulnerability fixes

### 🔒 Locked Spec v1.0 Compliance
- ✅ All changes maintain Locked Spec v1.0 compatibility
- ✅ No wire format changes
- ✅ MQTT-only transport preserved
- ✅ Size and timeout constraints maintained

### 📱 Mobile Platform Updates
- iOS-specific changes
- Android-specific changes
- React Native bridge updates

### ⚡ Performance Improvements
- Performance optimizations and improvements

### 🧪 Testing
- Testing improvements and new test coverage

### 📚 Documentation
- Documentation updates and improvements
-->

---

## Changelog Guidelines

### Categories

**Added** - New features, APIs, or capabilities
**Changed** - Changes to existing functionality
**Deprecated** - Features marked for removal in future versions
**Removed** - Features removed in this version
**Fixed** - Bug fixes and issue resolutions
**Security** - Security improvements and vulnerability fixes

### Mobile Platform Tracking

All changes should note their impact on:
- **iOS Compatibility** - iOS-specific changes and compatibility
- **Android Compatibility** - Android-specific changes and compatibility  
- **React Native Bridge** - Changes affecting the React Native integration
- **Performance Impact** - Battery, memory, and network implications

### Spec Compliance Tracking

Every release must confirm:
- **Wire Format Compatibility** - No breaking protocol changes
- **MQTT Constraints** - QoS=1, retain=false maintained
- **Size Limits** - Key/value/command size constraints respected
- **Timeout Behavior** - Proper timeout and backoff implementation
- **Idempotency** - All operations remain idempotent
- **Determinism** - Consistent behavior across implementations

### Version Links

All version entries should link to the corresponding GitHub release and comparison view:

```markdown
[X.Y.Z]: https://github.com/AI-Decenter/MerkleKV-Mobile/releases/tag/vX.Y.Z
[Unreleased]: https://github.com/AI-Decenter/MerkleKV-Mobile/compare/vX.Y.Z...HEAD
```

### Breaking Changes

Any breaking changes must be clearly marked and include:
- **Migration Guide** - Steps to upgrade existing implementations
- **Compatibility Matrix** - Version compatibility information
- **Deprecation Timeline** - When deprecated features will be removed

### Security Updates

Security-related changes should include:
- **CVE Numbers** - If applicable
- **Severity Assessment** - Impact and urgency level
- **Affected Versions** - Which versions are impacted
- **Mitigation Steps** - How to address the security issue

---

For questions about this changelog or to suggest improvements, please open an issue or discussion on GitHub.
