/// 读取 `test/golden/` 下的对拍向量。
///
/// golden 由 `tools/gen-dither-golden.mjs` 直接 eval web 版 `dithering.js` 生成，
/// 是本项目"逐字节复刻 web 上位机行为"的唯一可信基准。
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:epd_controller/image/rgba_image.dart';
import 'package:flutter_test/flutter_test.dart';

/// 读取指定 golden 文件并解析为 JSON 对象。
Map<String, dynamic> loadGoldenJson(String fileName) {
  final File file = File('test/golden/$fileName');
  if (!file.existsSync()) {
    throw StateError(
      '缺少 golden 文件 ${file.path}：请先用 tools/gen-dither-golden.mjs 生成',
    );
  }
  return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
}

/// 把 golden 里的 `{width, height, rgba_base64}` 还原成 [RgbaImage]。
RgbaImage imageFromGolden(Map<String, dynamic> entry) {
  final int width = entry['width'] as int;
  final int height = entry['height'] as int;
  return RgbaImage(width, height, base64Decode(entry['rgba_base64'] as String));
}

/// 逐字节比较任意字节序列（不假设是 RGBA），失败时报告下标与前几个字节。
void expectBytesMatchGoldenPayload(
  String expectedBase64,
  List<int> actual,
  String label,
) {
  final Uint8List expected = base64Decode(expectedBase64);
  if (expected.length != actual.length) {
    fail('$label 长度不一致：期望 ${expected.length}，实际 ${actual.length}');
  }
  for (int i = 0; i < expected.length; i++) {
    if (expected[i] != actual[i]) {
      final int from = i - 4 < 0 ? 0 : i - 4;
      final int to = i + 5 > expected.length ? expected.length : i + 5;
      fail(
        '$label 第 $i 字节不一致：期望 ${expected[i]}，实际 ${actual[i]}\n'
        '期望片段 ${expected.sublist(from, to)}\n'
        '实际片段 ${actual.sublist(from, to)}',
      );
    }
  }
}

/// 逐字节比较，失败时报告第一个不一致的字节和它所在的像素/通道，避免只看到两串长 base64。
void expectBytesMatchGolden(String expectedBase64, Uint8List actual) {
  final Uint8List expected = base64Decode(expectedBase64);
  if (expected.length != actual.length) {
    fail('字节长度不一致：期望 ${expected.length}，实际 ${actual.length}');
  }
  for (int i = 0; i < expected.length; i++) {
    if (expected[i] != actual[i]) {
      final int pixel = i ~/ 4;
      const List<String> channels = <String>['R', 'G', 'B', 'A'];
      fail(
        '第 $i 字节不一致（像素 $pixel，通道 ${channels[i % 4]}）：'
        '期望 ${expected[i]}，实际 ${actual[i]}',
      );
    }
  }
}
