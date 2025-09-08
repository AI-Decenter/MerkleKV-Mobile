# Security Policy

## 🔒 Reporting Security Vulnerabilities

The MerkleKV Mobile team takes security seriously. We appreciate your efforts to responsibly disclose your findings.

### How to Report

**Do NOT create public GitHub issues for security vulnerabilities.**

Instead, please report security vulnerabilities by emailing:
- **Primary Contact**: security@ai-decenter.org
- **Backup Contact**: merkle-kv-security@ai-decenter.org

### What to Include

Please include the following information in your report:

1. **Description**: Clear description of the vulnerability
2. **Steps to Reproduce**: Detailed steps to reproduce the issue
3. **Impact Assessment**: Your assessment of the potential impact
4. **Proof of Concept**: Any relevant code, screenshots, or logs
5. **Environment**: Version, platform, configuration details
6. **Suggested Fix**: If you have ideas for remediation

### Response Timeline

- **Initial Response**: Within 24 hours
- **Confirmation**: Within 72 hours
- **Status Updates**: Weekly until resolution
- **Resolution**: Target 30 days for critical issues, 90 days for others

### Responsible Disclosure

We follow responsible disclosure practices:

1. **Initial Report**: Submit vulnerability privately
2. **Investigation**: We investigate and develop a fix
3. **Coordination**: We coordinate disclosure timeline with you
4. **Public Disclosure**: After fix is deployed and users can update
5. **Credit**: We provide appropriate credit in release notes

## 🛡️ Security Scope

### In Scope

**MerkleKV Mobile Core**:
- MQTT transport security vulnerabilities
- Authentication and authorization bypasses
- Data integrity and consistency issues
- Encryption and TLS implementation flaws
- Input validation and injection vulnerabilities
- Access control violations
- Denial of Service vulnerabilities
- Information disclosure issues

**Mobile Platform Integration**:
- React Native bridge security issues
- iOS/Android platform-specific vulnerabilities
- Storage security on mobile devices
- Inter-process communication security

**Replication System**:
- Merkle tree manipulation vulnerabilities
- Vector clock manipulation attacks
- Consensus algorithm exploitation
- Conflict resolution bypass

### Out of Scope

**Infrastructure & Deployment**:
- Vulnerabilities in third-party MQTT brokers
- Infrastructure misconfigurations
- Network security beyond TLS
- Operating system vulnerabilities
- Hardware security issues

**Development Tools**:
- Vulnerabilities in development dependencies
- Build system security issues (unless affecting production)
- IDE security issues
- Testing framework vulnerabilities

**Denial of Service**:
- Rate limiting bypasses (handled at broker level)
- Resource exhaustion through legitimate usage
- Network flooding attacks

## 🎯 Security Best Practices

### For Users

**MQTT Broker Security**:
- Always use TLS 1.2 or higher for MQTT connections
- Implement proper authentication (username/password or certificates)
- Configure ACLs to restrict topic access by client ID
- Use VPN or private networks when possible
- Regular broker security updates

**Client Configuration**:
```javascript
const config = {
  // Always use secure connections
  protocol: 'mqtts',
  port: 8883,
  
  // Enforce TLS 1.2+
  secureProtocol: 'TLSv1_2_method',
  
  // Certificate validation
  rejectUnauthorized: true,
  
  // Connection security
  username: process.env.MQTT_USERNAME,
  password: process.env.MQTT_PASSWORD,
  
  // Client certificate (if using mutual TLS)
  cert: fs.readFileSync('client-cert.pem'),
  key: fs.readFileSync('client-key.pem'),
  ca: fs.readFileSync('ca-cert.pem')
};
```

**Access Control Lists (ACLs)**:
```
# Example Mosquitto ACL configuration
# Allow client to publish commands to their topic
user client123
topic write merkle/client123/cmd

# Allow client to subscribe to their responses
user client123
topic read merkle/client123/res

# Allow replication participants to access replication topics
user replication-node-1
topic readwrite merkle/replication/events
```

**Mobile Security**:
- Store credentials securely using Keychain (iOS) or Keystore (Android)
- Enable app transport security (ATS) on iOS
- Use certificate pinning for critical connections
- Implement proper session management
- Clear sensitive data on app backgrounding

### For Developers

**Input Validation**:
```typescript
// Validate key size (Locked Spec: ≤256 bytes)
function validateKey(key: string): boolean {
  const keyBytes = Buffer.from(key, 'utf8');
  if (keyBytes.length > 256) {
    throw new Error('Key exceeds maximum size of 256 bytes');
  }
  return true;
}

// Validate value size (Locked Spec: ≤256 KiB)
function validateValue(value: any): boolean {
  const valueBytes = Buffer.from(JSON.stringify(value), 'utf8');
  if (valueBytes.length > 262144) { // 256 * 1024
    throw new Error('Value exceeds maximum size of 256 KiB');
  }
  return true;
}
```

**Secure Message Handling**:
```typescript
// Always validate message structure
function validateMQTTMessage(topic: string, payload: Buffer): boolean {
  // Check topic pattern matches expected format
  const topicPattern = /^[a-zA-Z0-9_-]+\/[a-zA-Z0-9_-]+\/(cmd|res)$/;
  if (!topicPattern.test(topic)) {
    throw new Error('Invalid topic format');
  }
  
  // Validate payload size (Locked Spec: ≤512 KiB for commands)
  if (payload.length > 524288) { // 512 * 1024
    throw new Error('Command payload exceeds maximum size');
  }
  
  return true;
}
```

**Timeout Handling**:
```typescript
// Implement proper timeout handling (Locked Spec timeouts)
const TIMEOUTS = {
  COMMAND: 10000,      // 10 seconds
  REPLICATION: 20000,  // 20 seconds
  CONNECTION: 30000    // 30 seconds
};

async function executeWithTimeout<T>(
  operation: Promise<T>,
  timeout: number
): Promise<T> {
  return Promise.race([
    operation,
    new Promise<never>((_, reject) =>
      setTimeout(() => reject(new Error('Operation timeout')), timeout)
    )
  ]);
}
```

## 🚨 Common Vulnerabilities to Avoid

### MQTT-Specific Issues

**Topic Injection**:
```typescript
// ❌ VULNERABLE: Direct topic construction
const topic = `merkle/${userInput}/cmd`;

// ✅ SECURE: Validate and sanitize input
function buildTopic(clientId: string, suffix: 'cmd' | 'res'): string {
  // Validate client ID format
  if (!/^[a-zA-Z0-9_-]+$/.test(clientId)) {
    throw new Error('Invalid client ID format');
  }
  return `merkle/${clientId}/${suffix}`;
}
```

**ACL Bypasses**:
```typescript
// ❌ VULNERABLE: No access control validation
function publishCommand(topic: string, payload: any) {
  mqtt.publish(topic, payload);
}

// ✅ SECURE: Validate topic permissions
function publishCommand(clientId: string, topic: string, payload: any) {
  if (!topic.startsWith(`merkle/${clientId}/cmd`)) {
    throw new Error('Access denied: cannot publish to unauthorized topic');
  }
  mqtt.publish(topic, payload);
}
```

### Data Integrity Issues

**Vector Clock Manipulation**:
```typescript
// ❌ VULNERABLE: Accept any vector clock
function mergeVectorClock(remote: VectorClock) {
  this.vectorClock = remote;
}

// ✅ SECURE: Validate vector clock consistency
function mergeVectorClock(remote: VectorClock) {
  if (!this.validateVectorClock(remote)) {
    throw new Error('Invalid vector clock: consistency violation');
  }
  this.vectorClock = this.vectorClock.merge(remote);
}
```

### Mobile Platform Issues

**Insecure Storage**:
```typescript
// ❌ VULNERABLE: Plain text storage
localStorage.setItem('mqtt_password', password);

// ✅ SECURE: Use secure storage
import * as Keychain from 'react-native-keychain';

await Keychain.setInternetCredentials(
  'mqtt_server',
  username,
  password
);
```

## 📞 Contact Information

- **Security Team**: security@ai-decenter.org
- **General Inquiries**: contact@ai-decenter.org
- **Documentation**: [Security Guidelines](https://docs.ai-decenter.org/merkle-kv/security)

## 🏆 Security Hall of Fame

We recognize security researchers who help improve MerkleKV Mobile security:

<!-- Security researchers will be listed here after responsible disclosure -->

---

**Thank you for helping keep MerkleKV Mobile secure!**
