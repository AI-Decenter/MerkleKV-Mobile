import 'dart:typed_data';

import 'package:convert/convert.dart';
import 'package:ieee754/ieee754.dart';
import 'package:test/test.dart';

class TestCase {
  TestCase(
    this.name, {
    required this.parts,
    this.isFloat16Lossless = false,
    required String float16Bytes,
    bool? isFloat32Lossless,
    required String float32Bytes,
    bool? isFloat64Lossless,
    required String float64Bytes,
    bool? isFloat128Lossless,
    required String float128Bytes,
  })  : float16Bytes = Uint8List.fromList(hex.decode(float16Bytes)),
        float32Bytes = Uint8List.fromList(hex.decode(float32Bytes)),
        float64Bytes = Uint8List.fromList(hex.decode(float64Bytes)),
        float128Bytes = Uint8List.fromList(hex.decode(float128Bytes)),
        isFloat32Lossless = isFloat32Lossless ?? isFloat16Lossless,
        isFloat64Lossless =
            isFloat64Lossless ?? isFloat32Lossless ?? isFloat16Lossless,
        isFloat128Lossless = isFloat128Lossless ??
            isFloat64Lossless ??
            isFloat32Lossless ??
            isFloat16Lossless;

  final String name;
  final FloatParts parts;
  final bool isFloat16Lossless;
  final Uint8List float16Bytes;
  final bool isFloat32Lossless;
  final Uint8List float32Bytes;
  final bool isFloat64Lossless;
  final Uint8List float64Bytes;
  final bool isFloat128Lossless;
  final Uint8List float128Bytes;
}

void main() {
  final cases = [
    TestCase(
      '1.0',
      parts: FloatParts(1, 0),
      isFloat16Lossless: true,
      float16Bytes: '3c00',
      float32Bytes: '3f800000',
      float64Bytes: '3ff0000000000000',
      float128Bytes: '3fff0000000000000000000000000000',
    ),
    TestCase(
      '-1.0',
      parts: FloatParts(-1, 0),
      isFloat16Lossless: true,
      float16Bytes: 'bc00',
      float32Bytes: 'bf800000',
      float64Bytes: 'bff0000000000000',
      float128Bytes: 'BFFF0000000000000000000000000000',
    ),
    TestCase(
      '0.0',
      parts: FloatParts(0, 0),
      isFloat16Lossless: true,
      float16Bytes: '0000',
      float32Bytes: '00000000',
      float64Bytes: '0000000000000000',
      float128Bytes: '00000000000000000000000000000000',
    ),
    TestCase(
      '-0.0',
      parts: FloatParts(0, 0, forceNegative: true),
      isFloat16Lossless: true,
      float16Bytes: '8000',
      float32Bytes: '80000000',
      float64Bytes: '8000000000000000',
      float128Bytes: '80000000000000000000000000000000',
    ),
    TestCase(
      'infinite',
      parts: FloatParts.infinity,
      isFloat16Lossless: true,
      float16Bytes: '7C00',
      float32Bytes: '7F800000',
      float64Bytes: '7FF0000000000000',
      float128Bytes: '7FFF0000000000000000000000000000',
    ),
    TestCase(
      '-infinite',
      parts: FloatParts.negativeInfinity,
      isFloat16Lossless: true,
      float16Bytes: 'FC00',
      float32Bytes: 'FF800000',
      float64Bytes: 'FFF0000000000000',
      float128Bytes: 'FFFF0000000000000000000000000000',
    ),
    TestCase(
      'nan',
      parts: FloatParts.nan,
      isFloat16Lossless: true,
      float16Bytes: '7FFF',
      float32Bytes: '7FFFFFFF',
      float64Bytes: '7FFFFFFFFFFFFFFF',
      float128Bytes: '7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF',
    ),
    TestCase(
      '1.9990234375',
      parts: FloatParts(2047, -10),
      isFloat16Lossless: true,
      float16Bytes: '3FFF',
      float32Bytes: '3FFFE000',
      float64Bytes: '3FFFFC0000000000',
      float128Bytes: '3FFFFFC0000000000000000000000000',
    ),
    TestCase(
      '1.99951171875',
      parts: FloatParts(4095, -11),
      isFloat32Lossless: true,
      float16Bytes: '4000',
      float32Bytes: '3FFFF000',
      float64Bytes: '3FFFFE0000000000',
      float128Bytes: '3FFFFFE0000000000000000000000000',
    ),
    TestCase(
      '65504',
      parts: FloatParts(2047, 5),
      isFloat16Lossless: true,
      float16Bytes: '7BFF',
      float32Bytes: '477FE000',
      float64Bytes: '40EFFC0000000000',
      float128Bytes: '400EFFC0000000000000000000000000',
    ),
    TestCase(
      '65505',
      parts: FloatParts(65505, 0),
      isFloat32Lossless: true,
      float16Bytes: '7BFF',
      float32Bytes: '477FE100',
      float64Bytes: '40EFFC2000000000',
      float128Bytes: '400EFFC2000000000000000000000000',
    ),
    TestCase(
      'FLOAT32_MAX',
      parts: FloatParts(16777215, 104),
      isFloat32Lossless: true,
      float16Bytes: '7C00',
      float32Bytes: '7F7FFFFF',
      float64Bytes: '47EFFFFFE0000000',
      float128Bytes: '407EFFFFFE0000000000000000000000',
    ),
  ];

  group('FloatParts', () {
    test('minimize', () {
      var parts = FloatParts(10, 1).minimize();
      expect(parts.exponent, 2);
      expect(parts.mantissa.toInt(), 5);
    });
  });

  group('FloatParts test suite', () {
    for (final testCase in cases) {
      test(testCase.name, () {
        expect(testCase.parts.isFloat16Lossless, testCase.isFloat16Lossless);
        expect(testCase.parts.isFloat32Lossless, testCase.isFloat32Lossless);
        expect(testCase.parts.isFloat64Lossless, testCase.isFloat64Lossless);
        expect(testCase.parts.isFloat128Lossless, testCase.isFloat128Lossless);
        expect(testCase.parts.toFloat16Bytes(), testCase.float16Bytes);
        expect(testCase.parts.toFloat32Bytes(), testCase.float32Bytes);
        expect(testCase.parts.toFloat64Bytes(), testCase.float64Bytes);
        expect(testCase.parts.toFloat128Bytes(), testCase.float128Bytes);

        if (testCase.isFloat16Lossless) {
          final parts = FloatParts.fromFloat16Bytes(testCase.float16Bytes);

          if (testCase.parts.isInfinite) {
            expect(parts.isInfinite, true);
          } else if (testCase.parts.isNaN) {
            expect(parts.isNaN, true);
          } else {
            expect(parts.mantissa, testCase.parts.mantissa);
            if (testCase.parts.mantissa != BigInt.zero) {
              expect(parts.exponent, testCase.parts.exponent);
            }
          }
        }
        if (testCase.isFloat32Lossless) {
          final parts = FloatParts.fromFloat32Bytes(testCase.float32Bytes);

          if (testCase.parts.isInfinite) {
            expect(parts.isInfinite, true);
          } else if (testCase.parts.isNaN) {
            expect(parts.isNaN, true);
          } else {
            expect(parts.mantissa, testCase.parts.mantissa);
            if (testCase.parts.mantissa != BigInt.zero) {
              expect(parts.exponent, testCase.parts.exponent);
            }
          }
        }
        if (testCase.isFloat64Lossless) {
          final parts = FloatParts.fromFloat64Bytes(testCase.float64Bytes);

          if (testCase.parts.isInfinite) {
            expect(parts.isInfinite, true);
          } else if (testCase.parts.isNaN) {
            expect(parts.isNaN, true);
          } else {
            expect(parts.mantissa, testCase.parts.mantissa);
            if (testCase.parts.mantissa != BigInt.zero) {
              expect(parts.exponent, testCase.parts.exponent);
            }
          }
        }
        if (testCase.isFloat128Lossless) {
          final parts = FloatParts.fromFloat128Bytes(testCase.float128Bytes);

          if (testCase.parts.isInfinite) {
            expect(parts.isInfinite, true);
          } else if (testCase.parts.isNaN) {
            expect(parts.isNaN, true);
          } else {
            expect(parts.mantissa, testCase.parts.mantissa);
            if (testCase.parts.mantissa != BigInt.zero) {
              expect(parts.exponent, testCase.parts.exponent);
            }
          }
        }
      });
    }
  });
}
