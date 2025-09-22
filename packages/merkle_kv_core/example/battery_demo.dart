#!/usr/bin/env dart

/// Demonstration script for battery-aware reconnection policies.
/// 
/// This script shows how the battery-aware reconnection policy adapts
/// to different battery conditions while maintaining Locked Spec compliance.

import '../lib/src/battery/battery_state.dart';
import '../lib/src/battery/battery_aware_reconnect_policy.dart';

void main() {
  print('🔋 MerkleKV Mobile - Battery-Aware Reconnection Policy Demo\n');
  
  // Create different policy configurations
  final defaultPolicy = const BatteryAwareReconnectPolicy();
  final conservativePolicy = const BatteryAwareReconnectPolicy.conservative();
  final disabledPolicy = const BatteryAwareReconnectPolicy.disabled();
  
  print('📱 Policy Configurations:');
  print('  Default: $defaultPolicy');
  print('  Conservative: $conservativePolicy');
  print('  Disabled: $disabledPolicy\n');
  
  // Demonstrate different battery scenarios
  print('🔋 Battery Scenario Testing:\n');
  
  _testScenario('Normal Operation', BatteryState.test(
    level: 80,
    isCharging: false,
    isPowerSaveMode: false,
    isBackgrounded: false,
  ), [defaultPolicy, conservativePolicy, disabledPolicy]);
  
  _testScenario('Power Save Mode', BatteryState.test(
    level: 50,
    isCharging: false,
    isPowerSaveMode: true,
    isBackgrounded: false,
  ), [defaultPolicy, conservativePolicy, disabledPolicy]);
  
  _testScenario('Critical Battery', BatteryState.test(
    level: 5,
    isCharging: false,
    isPowerSaveMode: false,
    isBackgrounded: false,
  ), [defaultPolicy, conservativePolicy, disabledPolicy]);
  
  _testScenario('App Backgrounded', BatteryState.test(
    level: 60,
    isCharging: true,
    isPowerSaveMode: false,
    isBackgrounded: true,
  ), [defaultPolicy, conservativePolicy, disabledPolicy]);
  
  _testScenario('Worst Case Scenario', BatteryState.test(
    level: 3,
    isCharging: false,
    isPowerSaveMode: true,
    isBackgrounded: true,
  ), [defaultPolicy, conservativePolicy, disabledPolicy]);
  
  print('\n📊 Locked Spec Timing Compliance Demo:');
  print('Demonstrating that backoff timing is ALWAYS Spec-compliant regardless of battery state:\n');
  
  for (int attempt = 0; attempt < 6; attempt++) {
    final backoff = defaultPolicy.calculateBackoff(attempt);
    final expected = attempt < 5 ? (1 << attempt) : 32;
    print('  Attempt $attempt: ${backoff.inSeconds}s (expected ~${expected}s ±20%)');
  }
  
  print('\n✅ Demo completed! Battery state affects GATING, not TIMING.');
  print('   Reconnection timing always follows Locked Spec requirements.');
}

void _testScenario(String name, BatteryState state, List<BatteryAwareReconnectPolicy> policies) {
  print('🔋 Scenario: $name');
  print('   Battery: $state');
  
  for (int i = 0; i < policies.length; i++) {
    final policy = policies[i];
    final policyName = i == 0 ? 'Default' : i == 1 ? 'Conservative' : 'Disabled';
    
    print('   $policyName Policy:');
    
    // Test attempts 1-10
    final gatedAttempts = <int>[];
    for (int attempt = 1; attempt <= 10; attempt++) {
      final shouldAttempt = policy.shouldAttemptReconnection(state, attempt);
      if (!shouldAttempt) {
        gatedAttempts.add(attempt);
      }
    }
    
    if (gatedAttempts.isEmpty) {
      print('     ✅ All attempts allowed (1-10)');
    } else {
      final firstGated = gatedAttempts.first;
      final reason = policy.getGatingReason(state, firstGated);
      print('     🚫 Gated starting at attempt $firstGated');
      print('     📝 Reason: $reason');
    }
  }
  print('');
}