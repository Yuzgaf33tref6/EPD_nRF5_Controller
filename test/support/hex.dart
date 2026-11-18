import 'dart:typed_data';

/// 把 `"0a0b0c"` 这样的十六进制串解成字节。
Uint8List hexToBytes(String hex) {
  if (hex.isEmpty) {
    return Uint8List(0);
  }
  if (hex.length.isOdd) {
    throw ArgumentError.value(hex, 'hex', '长度必须是偶数');
  }
  final out = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

/// 字节转小写十六进制串，用于和 golden 向量比对。
String bytesToHex(List<int> bytes) =>
    bytes.map((b) => (b & 0xff).toRadixString(16).padLeft(2, '0')).join();
