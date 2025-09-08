---
name: Bug Report
about: Report a bug in MerkleKV Mobile
title: '[BUG] '
labels: ['bug', 'needs-triage']
assignees: []
---

## 🐛 Bug Description

**Clear and concise description of the bug:**

## 🔄 Steps to Reproduce

1. Set up MerkleKV Mobile with...
2. Configure MQTT broker...
3. Execute command...
4. Observe error...

## ✅ Expected Behavior

**What you expected to happen:**

## ❌ Actual Behavior

**What actually happened:**

## 📱 Environment

**Platform Information:**
- OS: [e.g., iOS 17.0, Android 14]
- Device: [e.g., iPhone 15, Samsung Galaxy S24]
- React Native Version: [e.g., 0.72.0]
- MerkleKV Mobile Version: [e.g., 1.2.3]

**MQTT Broker:**
- Broker: [e.g., Mosquitto 2.0.18, HiveMQ Cloud]
- TLS Version: [e.g., TLS 1.2, TLS 1.3]
- Authentication: [e.g., username/password, certificates]

**Configuration:**
- QoS Setting: [should be 1 per Locked Spec]
- Retain Setting: [should be false per Locked Spec]
- Topic Prefix: [e.g., "merkle"]
- Timeout Settings: [command/replication/connection timeouts]

## 📋 Locked Spec v1.0 Compliance Check

**Please verify the issue occurs with spec-compliant settings:**
- [ ] MQTT QoS = 1 (not 0 or 2)
- [ ] MQTT retain = false
- [ ] Key size ≤ 256 bytes
- [ ] Value size ≤ 256 KiB
- [ ] Command payload ≤ 512 KiB
- [ ] Using proper topic structure: `{prefix}/{client_id}/cmd|res`
- [ ] Command timeout = 10 seconds
- [ ] Replication timeout = 20 seconds
- [ ] Connection timeout = 30 seconds

## 📊 Logs and Data

**MQTT Connection Logs:**
```
[Paste relevant MQTT connection/disconnection logs]
```

**Error Messages:**
```
[Paste error messages, stack traces, or console output]
```

**Network Trace (if relevant):**
```
[Paste relevant network traffic or MQTT message traces]
```

## 📎 Additional Context

**Screenshots (if applicable):**
[Add screenshots to help explain the problem]

**Related Issues:**
[Reference any related issues with #issue_number]

**Workarounds:**
[Describe any temporary workarounds you've found]

## 🔍 Debugging Information

**Have you tried:**
- [ ] Restarting the MQTT connection
- [ ] Checking broker connectivity with another MQTT client
- [ ] Validating ACL permissions
- [ ] Testing with minimal configuration
- [ ] Reviewing MQTT broker logs

**Device-Specific Testing:**
- [ ] Issue occurs on multiple devices
- [ ] Issue occurs on different network connections
- [ ] Issue occurs with different MQTT brokers
- [ ] Issue reproduces in development/production environments

## 📝 Spec Violation Assessment

**If this might be a spec violation:**
- [ ] This could affect wire format compatibility
- [ ] This could affect deterministic behavior
- [ ] This could affect idempotency guarantees
- [ ] This could affect conflict resolution (LWW)
- [ ] This could affect timeout/backoff behavior

---

**Before submitting:**
- [ ] I have searched existing issues for duplicates
- [ ] I have tested with the latest version
- [ ] I have verified this follows Locked Spec v1.0 constraints
- [ ] I have included sufficient information to reproduce the issue
