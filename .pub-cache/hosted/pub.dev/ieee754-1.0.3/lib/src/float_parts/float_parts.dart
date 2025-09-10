import 'dart:typed_data';

import 'package:meta/meta.dart';

import '../utils/utils.dart';
import '../utils/integer.dart';
import 'codec.dart';

/// Representation of the parts of a binary floating number.
@sealed
abstract class FloatParts {
  const FloatParts._();

  /// Create the parts for the number `M * 2^E`, where M is the [mantissa]
  /// and `E` is the [exponent].
  ///
  /// [forceNegative] overrides the sign for [FloatParts].
  factory FloatParts(
    int mantissa,
    int exponent, {
    bool forceNegative = false,
  }) {
    if (!mantissa.isNegative && mantissa != 0 && forceNegative) {
      mantissa = -mantissa;
    }

    return _FloatParts(
      Integer.from(mantissa),
      exponent,
      forceNegative || mantissa.isNegative,
    );
  }

  /// Create the parts for the number `M * 2^E`, where M is the [mantissa]
  /// and `E` is the [exponent].
  ///
  /// [forceNegative] overrides the sign for [FloatParts].
  factory FloatParts.withBigMantissa(
    BigInt mantissa,
    int exponent, {
    bool forceNegative = false,
  }) {
    if (!mantissa.isNegative && mantissa != BigInt.zero && forceNegative) {
      mantissa = -mantissa;
    }

    return _FloatParts(
      Integer(mantissa),
      exponent,
      forceNegative || mantissa.isNegative,
    );
  }

  /// Parse [FloatParts] from a single IEEE754 `float16` encoded as bytes.
  ///
  /// This function will throw [ArgumentError] if `bytes.length != 2`.
  factory FloatParts.fromFloat16Bytes(
    Uint8List bytes, [
    Endian e = Endian.big,
  ]) {
    if (bytes.length != 2) {
      throw ArgumentError(bytes.length, 'Length for Float16 must be 2.');
    }

    return Codec.float16.decode(bytes, e);
  }

  /// Parse [FloatParts] from a single IEEE754 `float32` encoded as bytes.
  ///
  /// This function will throw [ArgumentError] if `bytes.length != 4`.
  factory FloatParts.fromFloat32Bytes(
    Uint8List bytes, [
    Endian e = Endian.big,
  ]) {
    if (bytes.length != 4) {
      throw ArgumentError(bytes.length, 'Length for Float32 must be 4.');
    }

    return _Decoding(
      bytes,
      e,
      float64: ByteData.view(bytes.buffer).getFloat32(0, e),
      codec: Codec.float32,
      isFloat32Lossless: true,
    );
  }

  /// Parse [FloatParts] from a single IEEE754 `float64` encoded as bytes.
  ///
  /// This function will throw [ArgumentError] if `bytes.length != 8`.
  factory FloatParts.fromFloat64Bytes(
    Uint8List bytes, [
    Endian e = Endian.big,
  ]) {
    if (bytes.length != 8) {
      throw ArgumentError(bytes.length, 'Length for Float64 must be 8.');
    }

    return _Decoding(
      bytes,
      e,
      float64: ByteData.view(bytes.buffer).getFloat64(0, e),
      codec: Codec.float64,
      isFloat32Lossless: false,
    );
  }

  /// Parse [FloatParts] from a single IEEE754 `float128` encoded as bytes.
  ///
  /// This function will throw [ArgumentError] if `bytes.length != 16`.
  factory FloatParts.fromFloat128Bytes(
    Uint8List bytes, [
    Endian e = Endian.big,
  ]) {
    if (bytes.length != 16) {
      throw ArgumentError(bytes.length, 'Length for Float128 must be 16.');
    }

    return Codec.float128.decode(bytes, e);
  }

  /// Parse [FloatParts] from a double.
  factory FloatParts.fromDouble(double value) => _FromDouble(value);

  /// Representation for infinity.
  static const FloatParts infinity = _Infinity(false);

  /// Representation for negative infinity.
  static const FloatParts negativeInfinity = _Infinity(true);

  /// Representation for NaN.
  static const FloatParts nan = _Nan();

  /// <nodoc>
  @internal
  Integer get mantissaInteger;

  /// Whether the value is inifinite.
  ///
  /// Only true for positive and negative infinity.
  ///
  /// If `true`, [exponent] and [mantissa] values have no meaning.
  bool get isInfinite;

  /// Whether the value is NaN.
  ///
  /// If `true`, [exponent] and [mantissa] values have no meaning.
  bool get isNaN;

  /// The mantissa for the `M * 2^E` number.
  BigInt get mantissa => mantissaInteger.toBigInt();

  /// The exponent for the `M * 2^E` number.
  int get exponent;

  /// Whether the number is negative.
  ///
  /// Will be equal to `matissa.isNegative` unless `forceNegative` is used.
  bool get isNegative;

  /// Minimize the representation.
  ///
  /// This will divide the mantissa by two and increase the exponent until
  /// the mantissa is odd.
  ///
  /// When building from a double or from bytes, this is already done,
  /// so it's redundant to call again.
  FloatParts minimize() {
    Integer mant = mantissaInteger;
    int exp = exponent;
    while (mant.isEven && !mant.isZero) {
      mant >>= 1;
      exp += 1;
    }

    return _FloatParts(mant, exp, isNegative);
  }

  /// Returns the absolute value of this number.
  FloatParts abs() {
    if (isNaN) {
      return FloatParts.nan;
    } else if (isInfinite) {
      return FloatParts.infinity;
    } else {
      return _FloatParts(mantissaInteger.abs(), exponent);
    }
  }

  /// Rounds (or extends) the number such that
  /// `mantissa.abs().bitLength == bits`.
  ///
  /// The exponent may increase or decrease.
  ///
  /// No-op if the number is zero, inifinity or NaN.
  FloatParts roundToMantissa(int bits) {
    if (isNaN || isInfinite || mantissaInteger.isZero) {
      return this;
    }

    Integer mant = mantissaInteger.abs();
    int exp = exponent;
    if (mant.bitLength < bits) {
      exp -= bits - mant.bitLength;
      mant <<= bits - mant.bitLength;
    } else {
      while (mant.bitLength > bits) {
        exp += mant.bitLength - bits;
        mant >>= mant.bitLength - bits - 1;
        final c = mant.isOdd;
        mant >>= 1;
        if (c) {
          mant += Integer.one;
        }
      }
    }

    if (isNegative) {
      mant = -mant;
    }

    return _FloatParts(mant, exp, isNegative);
  }

  /// Rounds (or extends) the number such that `exponent == val`.
  ///
  /// No-op if the number is zero, inifinity or NaN.
  FloatParts roundToExponent(int val) {
    if (isNaN || isInfinite || mantissaInteger.isZero) {
      return this;
    }

    Integer mant = mantissaInteger.abs();
    if (exponent > val) {
      mant <<= exponent - val;
    } else if (exponent < val) {
      mant >>= val - exponent - 1;
      final c = mant.isOdd;
      mant >>= 1;
      if (c) {
        mant += Integer.one;
      }
    }

    if (isNegative) {
      mant = -mant;
    }

    return _FloatParts(mant, val, isNegative);
  }

  /// Transform the number into a double.
  double toDouble() => toFloat32Bytes(hostEndian).buffer.asFloat32List()[0];

  /// Encode as IEEE754 float16.
  Uint8List toFloat16Bytes([Endian e = Endian.big]) =>
      Codec.float16.encode(this, e);

  /// Encode as IEEE754 float32.
  Uint8List toFloat32Bytes([Endian e = Endian.big]) =>
      Codec.float32.encode(this, e);

  /// Encode as IEEE754 float64.
  Uint8List toFloat64Bytes([Endian e = Endian.big]) =>
      Codec.float64.encode(this, e);

  /// Encode as IEEE754 float128.
  Uint8List toFloat128Bytes([Endian e = Endian.big]) =>
      Codec.float128.encode(this, e);

  /// Returns `true` if [toFloat16Bytes] is lossless.
  bool get isFloat16Lossless => Codec.float16.isLossless(this);

  /// Returns `true` if [toFloat32Bytes] is lossless.
  bool get isFloat32Lossless => Codec.float32.isLossless(this);

  /// Returns `true` if [toFloat64Bytes] is lossless.
  bool get isFloat64Lossless => Codec.float64.isLossless(this);

  /// Returns `true` if [toFloat128Bytes] is lossless.
  bool get isFloat128Lossless => Codec.float128.isLossless(this);
}

class _FloatParts extends FloatParts {
  _FloatParts(this.mantissaInteger, this.exponent, [this.isNegative = false])
      : super._();

  @override
  final Integer mantissaInteger;

  @override
  FloatParts abs() {
    if (isNaN) {
      return FloatParts.nan;
    } else if (isInfinite) {
      return FloatParts.infinity;
    } else {
      return _FloatParts(mantissaInteger.abs(), exponent);
    }
  }

  @override
  final bool isInfinite = false;
  @override
  final bool isNaN = false;
  @override
  final int exponent;
  @override
  final bool isNegative;
}

class _Decoding extends FloatParts {
  _Decoding(
    this._bytes,
    this._endian, {
    required this.float64,
    required this.isFloat32Lossless,
    required this.codec,
  }) : super._();

  final Codec codec;
  final double float64;
  final Uint8List _bytes;
  final Endian _endian;
  late final FloatParts _parts = codec.decode(_bytes, _endian);

  @override
  Integer get mantissaInteger => _parts.mantissaInteger;

  @override
  bool get isInfinite => float64.isInfinite;
  @override
  bool get isNaN => float64.isNaN;
  @override
  int get exponent => _parts.exponent;
  @override
  bool get isNegative => float64.isNegative;
  @override
  double toDouble() => float64;
  @override
  Uint8List toFloat32Bytes([Endian e = Endian.big]) {
    final bytes = Float32List.fromList([float64]);
    if (hostEndian == e) {
      return bytes.buffer.asUint8List();
    } else {
      return Uint8List.fromList(bytes.buffer.asUint8List().reversed.toList());
    }
  }

  @override
  Uint8List toFloat64Bytes([Endian e = Endian.big]) {
    final bytes = Float64List.fromList([float64]);
    if (hostEndian == e) {
      return bytes.buffer.asUint8List();
    } else {
      return Uint8List.fromList(bytes.buffer.asUint8List().reversed.toList());
    }
  }

  @override
  final bool isFloat128Lossless = true;
  @override
  final bool isFloat64Lossless = true;
  @override
  final bool isFloat32Lossless;
}

class _FromDouble extends FloatParts {
  _FromDouble(this.value) : super._();

  final double value;
  late final FloatParts _parts = FloatParts.fromFloat64Bytes(
    Float64List.fromList([value]).buffer.asUint8List(),
    hostEndian,
  );

  @override
  bool get isInfinite => value.isInfinite;
  @override
  bool get isNaN => value.isNaN;
  @override
  Integer get mantissaInteger => _parts.mantissaInteger;
  @override
  int get exponent => _parts.exponent;
  @override
  bool get isNegative => _parts.isNegative;

  @override
  Uint8List toFloat64Bytes([Endian e = Endian.big]) {
    final bytes = Float64List.fromList([value]);
    if (hostEndian == e) {
      return bytes.buffer.asUint8List();
    } else {
      return Uint8List.fromList(bytes.buffer.asUint8List().reversed.toList());
    }
  }

  @override
  Uint8List toFloat32Bytes([Endian e = Endian.big]) {
    final bytes = Float32List.fromList([value]);
    if (hostEndian == e) {
      return bytes.buffer.asUint8List();
    } else {
      return Uint8List.fromList(bytes.buffer.asUint8List().reversed.toList());
    }
  }

  @override
  double toDouble() => value;

  @override
  final bool isFloat128Lossless = true;

  @override
  final bool isFloat64Lossless = true;
}

class _Nan extends FloatParts {
  const _Nan() : super._();

  @override
  Integer get mantissaInteger => Integer.zero;
  @override
  final int exponent = 0;
  @override
  final bool isInfinite = false;
  @override
  final bool isNaN = true;
  @override
  final bool isNegative = false;
  @override
  double toDouble() => double.nan;
}

class _Infinity extends FloatParts {
  const _Infinity(this.isNegative) : super._();

  @override
  Integer get mantissaInteger => Integer.zero;
  @override
  final int exponent = 0;
  @override
  final bool isInfinite = true;
  @override
  final bool isNaN = false;
  @override
  final bool isNegative;
  @override
  double toDouble() => !isNegative ? double.infinity : double.negativeInfinity;
}
