# Dart IEEE754 library

[![pub](https://img.shields.io/pub/v/ieee754.svg)](https://pub.dev/packages/ieee754)


This library provides decoding and transforming IEEE754 floating point numbers
in binary format, `double` format, or as exponent and mantissa.

Examples of use cases are serializing and deserializing formats which use the
half or quad format, or encoding and converting numbers from arbitary exponents
and mantissas.

## Usage

[API reference](https://pub.dev/documentation/ieee754/latest/)

### Example: Serializing to least precision

```dart
void serializeDouble(double value) {
    final floatParts = FloatParts.fromDouble(value);
    if (floatParts.isFloat16Lossless) {
        _writeFloat16(floatParts.toFloat16Bytes());
    } else if (floatParts.isFloat32Lossless) {
        _writeFloat32(floatParts.toFloat32Bytes());
    } else if (floatParts.isFloat64Lossless) {
        _writeFloat64(floatParts.toFloat64Bytes());
    }
}
```
