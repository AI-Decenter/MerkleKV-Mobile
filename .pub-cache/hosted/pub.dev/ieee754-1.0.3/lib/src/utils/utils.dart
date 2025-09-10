import 'dart:typed_data';

final Endian hostEndian =
    ByteData.view(Float32List.fromList([1.0]).buffer).getInt8(0) == 0
        ? Endian.little
        : Endian.big;
