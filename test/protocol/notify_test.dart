import 'dart:convert';
import 'dart:io';

import 'package:epd_controller/protocol/epd_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/hex.dart';

Map<String, dynamic> _loadGolden(String name) =>
    jsonDecode(File('test/golden/$name').readAsStringSync()) as Map<String, dynamic>;

void main() {
  final golden = _loadGolden('notify.json');
  final cases = (golden['cases'] as List<dynamic>).cast<Map<String, dynamic>>();

  group('配置通知（连接后第一条）', () {
    final configCases = cases.where((c) => c['isConfig'] as bool).toList();

    test('golden 向量非空', () {
      expect(configCases, isNotEmpty);
    });

    for (final testCase in configCases) {
      test(testCase['name'] as String, () {
        final config = parseConfigNotification(hexToBytes(testCase['input'] as String));
        expect(bytesToHex(config.pins), testCase['pins']);
        expect(bytesToHex(<int>[config.driver]), testCase['driver']);
      });
    }

    test('不足 8 字节会报错', () {
      expect(
        () => parseConfigNotification(hexToBytes('06070809')),
        throwsArgumentError,
      );
    });
  });

  group('文本通知', () {
    final textCases = cases.where((c) => !(c['isConfig'] as bool)).toList();

    test('golden 向量非空', () {
      expect(textCases, isNotEmpty);
    });

    for (final testCase in textCases) {
      test(testCase['name'] as String, () {
        final msg = parseTextNotification(hexToBytes(testCase['input'] as String));
        expect(msg.text, testCase['rawText']);
        expect(msg.mtu, testCase['mtu']);
        expect(msg.rleSupported, testCase['rle']);
        expect(msg.remoteUnixSeconds, testCase['remoteSeconds']);
      });
    }

    test('rle=1 只在带 mtu= 前缀时才被识别（与 web 版一致）', () {
      final msg = parseTextNotification(
        hexToBytes(bytesToHex(utf8.encode('rle=1'))),
      );
      expect(msg.rleSupported, isFalse);
      expect(msg.mtu, isNull);
    });

    test('无法识别的文本原样保留', () {
      final msg = parseTextNotification(
        hexToBytes(bytesToHex(utf8.encode('hello'))),
      );
      expect(msg.text, 'hello');
      expect(msg.mtu, isNull);
      expect(msg.remoteUnixSeconds, isNull);
    });
  });
}
