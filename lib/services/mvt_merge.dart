import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

const maxCompressedTileBytes = 8 * 1024 * 1024;
const maxDecodedTileBytes = 16 * 1024 * 1024;
const maxMergedTileBytes = 32 * 1024 * 1024;

class _BoundedTileSink implements Sink<List<int>> {
  final bytes = BytesBuilder(copy: false);
  var length = 0;
  @override
  void add(List<int> chunk) {
    length += chunk.length;
    if (length > maxDecodedTileBytes) {
      throw const FormatException('Decoded tile exceeds bound');
    }
    bytes.add(chunk);
  }

  @override
  void close() {}
}

Uint8List _decodeTile(Uint8List archive) {
  if (archive.length > maxCompressedTileBytes) {
    throw const FormatException('Tile archive exceeds bound');
  }
  if (archive.length < 2 || archive[0] != 31 || archive[1] != 139) {
    return archive;
  }
  final output = _BoundedTileSink();
  final decoder = gzip.decoder.startChunkedConversion(output);
  try {
    for (var offset = 0; offset < archive.length; offset += 8192) {
      decoder.add(
        Uint8List.sublistView(
          archive,
          offset,
          (offset + 8192).clamp(0, archive.length),
        ),
      );
    }
    decoder.close();
  } catch (_) {
    try {
      decoder.close();
    } catch (_) {
      /* Release codec resources after rejection. */
    }
    rethrow;
  }
  return output.bytes.takeBytes();
}

/// Merge clipped regional MVT layers, preserving each feature's tag dictionary.
/// Concatenating tiles would hide every region after the first named layer.
Uint8List mergeRegionalTiles(List<Uint8List> archives) {
  if (archives.length > 21) {
    throw const FormatException('Too many regional fragments');
  }
  if (archives.length == 1) return _decodeTile(archives.single);
  var decodedBytes = 0;
  final layers = <String, List<List<_Field>>>{};
  final budget = _MvtBudget();
  for (final archive in archives) {
    final raw = _decodeTile(archive);
    decodedBytes += raw.length;
    if (decodedBytes > maxMergedTileBytes) {
      throw const FormatException('Regional tiles exceed bound');
    }
    for (final field in _fields(raw, budget)) {
      if (field.number != 3 || field.wire != 2) continue;
      final layer = _fields(field.bytes, budget);
      final names = layer.where((f) => f.number == 1 && f.wire == 2).toList();
      if (names.length != 1) {
        throw const FormatException('Missing or ambiguous MVT layer name');
      }
      final name = utf8.decode(names.single.bytes);
      if (name.isEmpty || name.length > 200) {
        throw const FormatException('Invalid MVT layer name');
      }
      layers.putIfAbsent(name, () => []).add(layer);
    }
  }
  final tile = BytesBuilder(copy: false);
  for (final group in layers.values) {
    final first = group.first;
    final output = BytesBuilder(copy: false);
    for (final f in first.where(
      (f) => f.number != 2 && f.number != 3 && f.number != 4,
    )) {
      _write(output, f);
    }
    var keyOffset = 0, valueOffset = 0;
    final dictionaries = <_Field>[];
    final extent = first.where((f) => f.number == 5).firstOrNull?.value ?? 4096;
    for (final layer in group) {
      if ((layer.where((f) => f.number == 5).firstOrNull?.value ?? 4096) !=
          extent) {
        throw const FormatException('Incompatible regional tile extent');
      }
      for (final feature in layer.where((f) => f.number == 2)) {
        final encoded = BytesBuilder(copy: false);
        for (final f in _fields(feature.bytes, budget)) {
          if (f.number == 2 && f.wire == 2) {
            final tags = _varints(f.bytes, budget);
            if (tags.length.isOdd) {
              throw const FormatException('Incomplete tags');
            }
            final packed = BytesBuilder(copy: false);
            for (var i = 0; i < tags.length; i++) {
              _varint(packed, tags[i] + (i.isEven ? keyOffset : valueOffset));
            }
            _write(encoded, _Field(2, 2, packed.takeBytes()));
          } else {
            _write(encoded, f);
          }
        }
        _write(output, _Field(2, 2, encoded.takeBytes()));
      }
      dictionaries.addAll(layer.where((f) => f.number == 3 || f.number == 4));
      keyOffset += layer.where((f) => f.number == 3).length;
      valueOffset += layer.where((f) => f.number == 4).length;
    }
    for (final d in dictionaries) {
      _write(output, d);
    }
    if (output.length + tile.length > maxMergedTileBytes) {
      throw const FormatException('Merged tile exceeds bound');
    }
    _write(tile, _Field(3, 2, output.takeBytes()));
  }
  return tile.takeBytes();
}

class _Field {
  final int number, wire;
  final Object value;
  _Field(this.number, this.wire, this.value);
  Uint8List get bytes => value is Uint8List
      ? value as Uint8List
      : Uint8List.fromList(value as List<int>);
}

class _MvtBudget {
  var remaining = 200000;
  void take() {
    if (--remaining < 0) throw const FormatException('Too many MVT fields');
  }
}

List<int> _varints(List<int> bytes, _MvtBudget budget) {
  final values = <int>[];
  var value = 0, shift = 0;
  for (final b in bytes) {
    value |= (b & 127) << shift;
    if (b < 128) {
      budget.take();
      values.add(value);
      value = 0;
      shift = 0;
    } else {
      shift += 7;
      if (shift > 63) throw const FormatException('Varint too long');
    }
  }
  if (shift != 0) throw const FormatException('Truncated varint');
  return values;
}

List<_Field> _fields(List<int> bytes, _MvtBudget budget) {
  var offset = 0;
  int read() {
    var value = 0, shift = 0;
    while (offset < bytes.length && shift <= 63) {
      final b = bytes[offset++];
      value |= (b & 127) << shift;
      if (b < 128) {
        if (value < 0) {
          throw const FormatException('Unsupported unsigned value');
        }
        return value;
      }
      shift += 7;
    }
    throw const FormatException('Invalid protobuf');
  }

  final result = <_Field>[];
  while (offset < bytes.length) {
    budget.take();
    final tag = read(), wire = tag & 7;
    if (tag <= 0 || tag >> 3 == 0) {
      throw const FormatException('Invalid field number');
    }
    if (wire == 0) {
      result.add(_Field(tag >> 3, wire, read()));
      continue;
    }
    final length = switch (wire) {
      1 => 8,
      2 => read(),
      5 => 4,
      _ => throw const FormatException('Invalid wire type'),
    };
    if (length < 0 || offset + length > bytes.length) {
      throw const FormatException('Truncated field');
    }
    result.add(
      _Field(
        tag >> 3,
        wire,
        bytes is Uint8List
            ? Uint8List.sublistView(bytes, offset, offset + length)
            : bytes.sublist(offset, offset + length),
      ),
    );
    offset += length;
  }
  return result;
}

void _varint(BytesBuilder output, int value) {
  while (value >= 128) {
    output.addByte((value & 127) | 128);
    value >>= 7;
  }
  output.addByte(value);
}

void _write(BytesBuilder output, _Field field) {
  _varint(output, (field.number << 3) | field.wire);
  if (field.wire == 0) {
    _varint(output, field.value as int);
  } else {
    final data = field.bytes;
    if (output.length + data.length + 10 > maxMergedTileBytes) {
      throw const FormatException('Encoded tile exceeds bound');
    }
    if (field.wire == 2) _varint(output, data.length);
    output.add(data);
  }
}
