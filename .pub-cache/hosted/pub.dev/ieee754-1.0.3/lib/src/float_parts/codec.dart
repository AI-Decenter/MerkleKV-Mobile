import 'dart:typed_data';

import '../utils/integer.dart';
import 'float_parts.dart';

abstract class Codec {
  const Codec(this.exponentBitLength, this.mantissaBitLength);

  final int mantissaBitLength;
  final int exponentBitLength;

  int get exponentBias => (1 << (exponentBitLength - 1)) - 1;

  Integer _read(ByteBuffer data, Endian e);
  Uint8List _write(Integer x, Endian e);

  FloatParts decode(Uint8List bytes, Endian e) {
    final bits = _read(bytes.buffer, e);
    final mantissaBits = bits.mask(mantissaBitLength);
    final exponentBits =
        (bits >> mantissaBitLength).mask(exponentBitLength).toInt();
    final sign = !(bits >> (exponentBitLength + mantissaBitLength)).isZero;

    if (exponentBits == (1 << exponentBitLength) - 1) {
      if (!mantissaBits.isZero) {
        return FloatParts.nan;
      } else if (!sign) {
        return FloatParts.infinity;
      } else {
        return FloatParts.negativeInfinity;
      }
    }

    Integer mantissa;
    final int exponent;
    if (exponentBits == 0) {
      exponent = 1 - exponentBias - mantissaBitLength;
      mantissa = mantissaBits;
    } else {
      exponent = exponentBits - exponentBias - mantissaBitLength;
      mantissa = mantissaBits.withBit(mantissaBitLength);
    }

    if (sign) {
      mantissa = -mantissa;
    }

    if (mantissa.isIntLossless) {
      return FloatParts(mantissa.toInt(), exponent, forceNegative: sign)
          .minimize();
    } else {
      return FloatParts.withBigMantissa(mantissa.toBigInt(), exponent,
              forceNegative: sign)
          .minimize();
    }
  }

  bool isLossless(FloatParts float) {
    if (float.isNaN || float.isInfinite || float.mantissaInteger.isZero) {
      return true;
    }

    float = float.abs().minimize();
    if (mantissaBitLength + 1 < float.mantissaInteger.bitLength) {
      return false;
    }

    final exponent = float.exponent +
        mantissaBitLength +
        exponentBias +
        (float.mantissa.bitLength - (mantissaBitLength + 1));

    // Exponent too large
    if (exponent >= ((1 << exponentBitLength) - 1)) {
      return false;
    }
    // Normal
    if (exponent >= 1) {
      return true;
    }

    final subnormalExp = -(exponentBias - 1 + mantissaBitLength);
    final subnormalMantissaLength =
        float.mantissaInteger.bitLength + float.exponent - subnormalExp;

    return subnormalMantissaLength > 0 &&
        subnormalMantissaLength <= mantissaBitLength;
  }

  Uint8List encode(FloatParts float, Endian e) {
    // Special
    if (float.isNaN) {
      return _encode(
        float.isNegative,
        Integer.allOnes(mantissaBitLength - 1),
        (1 << exponentBitLength) - 1,
        e,
      );
    }

    if (float.isInfinite) {
      return _encode(
          float.isNegative, Integer.zero, (1 << exponentBitLength) - 1, e);
    }

    final sign = float.isNegative;
    float = float.abs();
    if (float.mantissaInteger.isZero) {
      return _encode(sign, Integer.zero, 0, e);
    }

    // Try to encode in normalized form
    final normal = float.roundToMantissa(mantissaBitLength + 1);
    final exponent = normal.exponent + mantissaBitLength + exponentBias;
    // Exponent too large
    if (exponent >= ((1 << exponentBitLength) - 1)) {
      return _encode(sign, Integer.zero, (1 << exponentBitLength) - 1, e);
    }
    // Normal
    if (exponent >= 1) {
      return _encode(
          sign, normal.mantissaInteger.mask(mantissaBitLength), exponent, e);
    }

    final subnormal =
        float.roundToExponent(-(exponentBias - 1 + mantissaBitLength));
    if (subnormal.mantissaInteger.bitLength > mantissaBitLength) {
      return _encode(sign, Integer.zero, 0, e);
    }

    return _encode(sign, subnormal.mantissaInteger, 0, e);
  }

  Uint8List _encode(bool isNegative, Integer mantissa, int exponent, Endian e) {
    Integer bits = Integer.zero;
    bits |= mantissa;
    bits |= Integer.from(exponent) << mantissaBitLength;
    if (isNegative) {
      bits |= Integer.zero.withBit(exponentBitLength + mantissaBitLength);
    }

    return _write(bits, e);
  }

  static const Codec float16 = _Codec16();

  static const Codec float32 = _Codec32();

  static const Codec float64 = _Codec64();

  static const Codec float128 = _Codec128();
}

class _Codec16 extends Codec {
  const _Codec16() : super(5, 10);

  @override
  Integer _read(ByteBuffer data, Endian e) =>
      Integer.from(ByteData.view(data).getInt16(0, e));

  @override
  Uint8List _write(Integer x, Endian e) {
    final r = Uint8List(2);
    ByteData.view(r.buffer).setInt16(0, x.toInt(), e);
    return r;
  }
}

class _Codec32 extends Codec {
  const _Codec32() : super(8, 23);

  @override
  Integer _read(ByteBuffer data, Endian e) =>
      Integer.from(ByteData.view(data).getInt32(0, e));

  @override
  Uint8List _write(Integer x, Endian e) {
    final r = Uint8List(4);
    ByteData.view(r.buffer).setInt32(0, x.toInt(), e);
    return r;
  }
}

Integer _readBytes(ByteBuffer data, Endian e) {
  final Iterable<int> by;
  if (e == Endian.little) {
    by = data.asUint8List().reversed;
  } else {
    by = data.asUint8List();
  }

  Integer x = Integer.zero;
  for (final b in by) {
    x <<= 8;
    x |= Integer.from(b);
  }

  return x;
}

Uint8List _writeBytes(Integer x, int size, Endian e) {
  final list = Uint8List(size);

  if (e == Endian.little) {
    for (var i = 0; i < size; i++) {
      list[i] = x.mask(8).toInt();
      x >>= 8;
    }
  } else {
    for (var i = 0; i < size; i++) {
      list[size - 1 - i] = x.mask(8).toInt();
      x >>= 8;
    }
  }

  return list;
}

class _Codec64 extends Codec {
  const _Codec64() : super(11, 52);

  @override
  Integer _read(ByteBuffer data, Endian e) {
    return _readBytes(data, e);
  }

  @override
  Uint8List _write(Integer x, Endian e) {
    return _writeBytes(x, 8, e);
  }
}

class _Codec128 extends Codec {
  const _Codec128() : super(15, 112);

  @override
  Integer _read(ByteBuffer data, Endian e) {
    return _readBytes(data, e);
  }

  @override
  Uint8List _write(Integer x, Endian e) {
    return _writeBytes(x, 16, e);
  }
}
