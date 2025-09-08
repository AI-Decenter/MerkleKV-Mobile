# Pull Request Template

## 📋 Pull Request Checklist

**Before submitting this PR, please ensure:**

### 🎯 Basic Requirements
- [ ] I have read and followed the [CONTRIBUTING.md](../CONTRIBUTING.md) guidelines
- [ ] This PR addresses an existing issue (link: #issue_number)
- [ ] I have tested my changes locally
- [ ] All existing tests pass
- [ ] I have added tests for new functionality

### 📝 Description

**Summary of Changes:**
[Provide a clear description of what this PR does]

**Related Issue(s):**
Fixes #issue_number
Relates to #issue_number

**Type of Change:**
- [ ] 🐛 Bug fix (non-breaking change that fixes an issue)
- [ ] ✨ New feature (non-breaking change that adds functionality)
- [ ] 💥 Breaking change (fix or feature that causes existing functionality to not work as expected)
- [ ] 📚 Documentation update
- [ ] 🔧 Refactoring (no functional changes)
- [ ] ⚡ Performance improvement
- [ ] 🧪 Test improvements

## 🔒 Locked Spec v1.0 Compliance

**Specification Adherence:**
- [ ] ✅ Maintains MQTT-only transport (no alternative protocols)
- [ ] ✅ Uses QoS=1, retain=false for all MQTT operations
- [ ] ✅ Respects key size limit (≤256 bytes)
- [ ] ✅ Respects value size limit (≤256 KiB)
- [ ] ✅ Respects command payload limit (≤512 KiB)
- [ ] ✅ Uses proper topic structure: `{prefix}/{client_id}/cmd|res`
- [ ] ✅ Implements proper timeout handling (10/20/30s)
- [ ] ✅ Uses correct reconnect backoff (1→32s ±20% jitter)
- [ ] ✅ Maintains operation idempotency
- [ ] ✅ Ensures deterministic behavior
- [ ] ✅ Compatible with LWW conflict resolution

**Wire Format Impact:**
- [ ] 🔹 No wire format changes
- [ ] 🔹 Backward-compatible additions only
- [ ] 🚨 Breaking wire format changes (requires v2.0+)

## 📱 Mobile Platform Testing

**Platform Verification:**
- [ ] 📱 Tested on iOS (version: ___)
- [ ] 🤖 Tested on Android (version: ___)
- [ ] ⚛️ React Native bridge functionality verified
- [ ] 🔋 Battery usage impact assessed
- [ ] 💾 Memory usage impact assessed
- [ ] 📶 Network efficiency verified

**Device Testing:**
- [ ] Physical device testing completed
- [ ] Simulator/emulator testing completed
- [ ] Background/foreground behavior verified
- [ ] Network connectivity changes handled properly

## 🧪 Testing

**Test Coverage:**
- [ ] Unit tests added/updated
- [ ] Integration tests added/updated
- [ ] MQTT broker compatibility tests
- [ ] Mobile platform-specific tests
- [ ] Property-based tests for idempotency/determinism
- [ ] Performance/resource usage tests

**Test Results:**
```bash
# Paste test results showing all tests pass
npm test
```

**Coverage Report:**
- Current coverage: ___%
- Coverage change: +/-___%

## 🔐 Security Review

**Security Considerations:**
- [ ] No security implications
- [ ] Security team review completed
- [ ] No new attack vectors introduced
- [ ] Input validation implemented
- [ ] Secure coding practices followed
- [ ] TLS/encryption requirements maintained

**ACL/Permissions:**
- [ ] No permission changes required
- [ ] ACL compatibility maintained
- [ ] Topic access control respected

## 📊 Performance Impact

**Performance Testing:**
- [ ] No performance regression detected
- [ ] Performance improvements measured
- [ ] Mobile resource usage optimized
- [ ] MQTT broker load impact assessed

**Metrics:**
- Memory usage change: +/-___MB
- Battery usage change: +/-___%
- Network usage change: +/-___%
- Response time change: +/-___ms

## 🏗️ Architecture & Design

**Design Decisions:**
[Explain any significant architectural decisions or design choices]

**Dependencies:**
- [ ] No new dependencies added
- [ ] New dependencies reviewed and approved
- [ ] Dependency security audit completed

**Code Quality:**
- [ ] Code follows project style guidelines
- [ ] TypeScript types are properly defined
- [ ] Error handling is comprehensive
- [ ] Logging is appropriate and structured

## 📚 Documentation

**Documentation Updates:**
- [ ] API documentation updated
- [ ] User guides updated
- [ ] Examples updated
- [ ] CHANGELOG.md updated
- [ ] Migration guides created (if breaking changes)

**Code Documentation:**
- [ ] Public APIs have JSDoc comments
- [ ] Complex logic is commented
- [ ] README updates (if applicable)

## 🔄 Migration & Compatibility

**Backward Compatibility:**
- [ ] Fully backward compatible
- [ ] Requires migration (migration guide provided)
- [ ] Breaking changes documented

**Version Compatibility:**
- [ ] Compatible with all supported versions
- [ ] Minimum version requirements updated
- [ ] Deprecation notices added (if applicable)

## 🚀 Deployment

**Deployment Considerations:**
- [ ] No special deployment requirements
- [ ] Configuration changes required
- [ ] Database migrations needed
- [ ] Infrastructure changes needed

**Rollback Plan:**
[Describe how to rollback this change if issues arise]

## 🔍 Review Notes

**Areas Needing Special Attention:**
[Highlight specific areas where you want reviewer focus]

**Known Issues/Limitations:**
[List any known issues or limitations with this implementation]

**Follow-up Work:**
[Describe any follow-up work needed in future PRs]

## 📷 Screenshots/Demos

**Visual Changes:**
[Add screenshots for UI changes or demo videos for new features]

**Before/After:**
[Show before and after states if applicable]

---

## ✅ Final Verification

**I confirm that:**
- [ ] This PR follows the Locked Spec v1.0 constraints
- [ ] All tests pass and coverage is maintained
- [ ] Documentation is updated and complete
- [ ] Security implications have been considered
- [ ] Mobile platform compatibility is verified
- [ ] Performance impact is acceptable
- [ ] Code quality standards are met

**Additional Notes:**
[Any additional context, concerns, or information for reviewers]

---

**/cc @AI-Decenter/merkle-kv-core** for review
<!-- Auto-assign reviewers based on CODEOWNERS file -->
