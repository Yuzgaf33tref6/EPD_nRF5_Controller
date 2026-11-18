import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:epd_controller/protocol/rle.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/hex.dart';

Map<String, dynamic> _loadGolden(String name) =>
    jsonDecode(File('test/golden/$name').readAsStringSync()) as Map<String, dynamic>;

/// 按固件 `rle_decompress_from()` 的规则解压，用来做往返校验
/// （Dart 侧不需要实现解压，这里只是测试脚手架）。
Uint8List _rleDecode(Uint8List input) {
  final out = <int>[];
  var i = 0;
  while (i < input.length) {
    final control = input[i++];
    if ((control & 0x80) != 0) {
      final runLen = (control & 0x7f) + 3;
      final value = input[i++];
      for (var k = 0; k < runLen; k++) {
        out.add(value);
      }
    } else {
      final litLen = control + 1;
      for (var k = 0; k < litLen; k++) {
        out.add(input[i++]);
      }
    }
  }
  return Uint8List.fromList(out);
}

void main() {
  group('rleCompress 与 web 版 rle.js 逐字节一致', () {
    final golden = _loadGolden('rle_compress.json');
    final cases = golden['cases'] as List<dynamic>;

    test('golden 向量非空', () {
      expect(cases, isNotEmpty);
    });

    for (final raw in cases) {
      final testCase = raw as Map<String, dynamic>;
      final inputHex = testCase['input'] as String;
      final maxLiteralSize = testCase['maxLiteralSize'] as int;
      final expected = testCase['expected'] as String;

      test('input=$inputHex maxLiteralSize=$maxLiteralSize', () {
        final actual = rleCompress(
          hexToBytes(inputHex),
          maxLiteralSize: maxLiteralSize,
        );
        expect(bytesToHex(actual), expected);
      });

      test('往返还原 input=$inputHex maxLiteralSize=$maxLiteralSize', () {
        final input = hexToBytes(inputHex);
        final compressed = rleCompress(input, maxLiteralSize: maxLiteralSize);
        expect(bytesToHex(_rleDecode(compressed)), inputHex);
      });
    }
  });

  group('rleCompressMtu 与 web 版 rle.js 逐字节一致', () {
    final golden = _loadGolden('rle_compress_mtu.json');
    final cases = golden['cases'] as List<dynamic>;

    test('golden 向量非空', () {
      expect(cases, isNotEmpty);
    });

    for (final raw in cases) {
      final testCase = raw as Map<String, dynamic>;
      final inputHex = testCase['input'] as String;
      final chunkSize = testCase['chunkSize'] as int;
      final expected = (testCase['expected'] as List<dynamic>).cast<String>();

      test('input=$inputHex chunkSize=$chunkSize', () {
        final actual = rleCompressMtu(hexToBytes(inputHex), chunkSize);
        expect(actual.map(bytesToHex).toList(), expected);
      });

      test('按块拼回去能还原 input=$inputHex chunkSize=$chunkSize', () {
        final input = hexToBytes(inputHex);
        final chunks = rleCompressMtu(input, chunkSize);
        final joined = <int>[];
        for (final chunk in chunks) {
          joined.addAll(_rleDecode(chunk));
        }
        expect(bytesToHex(joined), inputHex);
      });
    }
  });

  test('超出范围的字面段长度会明确报错', () {
    expect(() => rleCompress(Uint8List(0), maxLiteralSize: 129), throwsArgumentError);
    expect(() => rleCompress(Uint8List(0), maxLiteralSize: -1), throwsArgumentError);
    expect(() => rleCompressMtu(Uint8List(0), 0), throwsArgumentError);
  });
}
