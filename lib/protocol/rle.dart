import 'dart:typed_data';

/// RLE 编码，逐字节复刻 web 版 `html/js/rle.js` 的 `rleCompress()`。
///
/// 编码规则（对应固件 `EPD/EPD_service.c` 里的 `rle_decompress_from()`）：
///
/// * 重复段：控制字节 `0x80 | (runLen - 3)`，后跟 1 字节重复值。
///   `runLen` 取值 [3, 130]。
/// * 字面段：控制字节 `litLen - 1`，后跟 `litLen` 个原始字节。
///   `litLen` 取值 [1, maxLiteralSize]，`maxLiteralSize` 不得大于 128
///   （否则控制字节会撞上 0x80 位）。
///
/// 注意 `maxLiteralSize == 0` 时行为与原版一致：永远走"单字节字面段"兜底分支，
/// 即每个字节编码成 `[0x00, byte]` 两字节。分块逻辑依赖这个兜底等价性。
Uint8List rleCompress(Uint8List data, {int maxLiteralSize = 128}) {
  if (maxLiteralSize < 0) {
    throw ArgumentError.value(maxLiteralSize, 'maxLiteralSize', '不能为负数');
  }
  if (maxLiteralSize > 128) {
    throw ArgumentError.value(
      maxLiteralSize,
      'maxLiteralSize',
      '不能大于 128（控制字节会被 0x80 位占用）',
    );
  }

  final result = <int>[];
  var i = 0;

  while (i < data.length) {
    var runLen = 1;
    while (i + runLen < data.length &&
        runLen < 130 &&
        data[i + runLen] == data[i]) {
      runLen++;
    }

    if (runLen >= 3) {
      result.add(0x80 | (runLen - 3));
      result.add(data[i]);
      i += runLen;
    } else {
      final literalStart = i;
      var literalLen = 0;
      while (i < data.length && literalLen < maxLiteralSize) {
        // 一旦接下来的三个字节构成一个可编码的重复段，就结束当前字面段。
        if (i + 2 < data.length &&
            data[i] == data[i + 1] &&
            data[i] == data[i + 2]) {
          break;
        }
        literalLen++;
        i++;
      }
      if (literalLen == 0) {
        // 兜底：单字节字面段。
        result.add(0x00);
        result.add(data[i]);
        i++;
      } else {
        result.add(literalLen - 1);
        for (var j = literalStart; j < literalStart + literalLen; j++) {
          result.add(data[j]);
        }
      }
    }
  }

  return Uint8List.fromList(result);
}

/// 整包 RLE 压缩后，按 RLE code 边界切块，使每块都是完整可解压的码流。
///
/// 复刻 web 版 `rleCompressMTU()`：不把一个 code 拆到两个块里；
/// 单个 code 本身就超过 [maxChunkSize] 时独占一块。
List<Uint8List> rleCompressMtu(Uint8List data, int maxChunkSize) {
  if (maxChunkSize < 1) {
    throw ArgumentError.value(maxChunkSize, 'maxChunkSize', '至少为 1');
  }

  // 控制字节占 1 字节，因此字面段的数据字节最多 maxChunkSize - 1 个。
  final int maxLit = maxChunkSize - 1 < 128 ? maxChunkSize - 1 : 128;
  final input = rleCompress(data, maxLiteralSize: maxLit);

  final chunks = <Uint8List>[];
  var i = 0;
  var start = 0;

  while (i < input.length) {
    final control = input[i];
    // 重复段 = 2 字节；字面段 = 1 + (control + 1) 字节。
    final codeLen = (control & 0x80) != 0 ? 2 : (control + 2);

    if (i - start + codeLen > maxChunkSize && i > start) {
      chunks.add(input.sublist(start, i));
      start = i;
    }
    i += codeLen;
  }

  if (i > start) {
    chunks.add(input.sublist(start, i));
  }
  return chunks;
}
