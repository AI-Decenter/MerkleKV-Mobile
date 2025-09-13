import 'dart:async';
import 'package:test/test.dart';

// Simple test to verify test framework is working
void main() {
  test('basic test works', () {
    expect(1 + 1, equals(2));
  });
  
  test('async test works', () async {
    await Future.delayed(Duration(milliseconds: 10));
    expect(true, isTrue);
  });
}