/// 显存位打包与 UC8159 转换的 web 版对拍测试。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:epd_controller/image/epd_color.dart';
import 'package:epd_controller/image/packing.dart';
import 'package:epd_controller/image/rgba_image.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/golden.dart';

void main() {
  final Map<String, dynamic> golden = loadGoldenJson('pack.json');
  final Map<String, dynamic> images =
      golden['images'] as Map<String, dynamic>;

  group('processImageData（web 版对拍）', () {
    for (final Map<String, dynamic> item
        in (golden['process'] as List<dynamic>).cast<Map<String, dynamic>>()) {
      final String imageName = item['image'] as String;
      final String modeName = item['mode'] as String;

      test('$imageName / $modeName', () {
        final RgbaImage image =
            imageFromGolden(images[imageName] as Map<String, dynamic>);
        final Uint8List result =
            processImageData(image, EpdColorMode.fromJsName(modeName));
        expectBytesMatchGolden(item['expected_base64'] as String, result);
      });
    }
  });

  group('decodeProcessedData（web 版对拍）', () {
    for (final Map<String, dynamic> item
        in (golden['decode'] as List<dynamic>).cast<Map<String, dynamic>>()) {
      final String imageName = item['image'] as String;
      final String modeName = item['mode'] as String;

      test('$imageName / $modeName', () {
        final Map<String, dynamic> meta =
            images[imageName] as Map<String, dynamic>;
        final int width = meta['width'] as int;
        final int height = meta['height'] as int;
        final Uint8List processed =
            base64Decode(item['processed_base64'] as String);
        final RgbaImage result = decodeProcessedData(
          processed,
          width,
          height,
          EpdColorMode.fromJsName(modeName),
        );
        expectBytesMatchGolden(
          item['expected_rgba_base64'] as String,
          result.data,
        );
      });
    }
  });

  group('convertUC8159（web 版对拍）', () {
    for (final Map<String, dynamic> item
        in (golden['uc8159'] as List<dynamic>).cast<Map<String, dynamic>>()) {
      final String imageName = item['image'] as String;
      final String kind = item['kind'] as String;

      test('$imageName / $kind', () {
        final Uint8List blackWhite =
            base64Decode(item['black_white_base64'] as String);
        final Uint8List redWhite =
            base64Decode(item['red_white_base64'] as String);
        final Uint8List result = convertUC8159(blackWhite, redWhite);
        expectBytesMatchGolden(item['expected_base64'] as String, result);
      });
    }
  });

  test('convertUC8159 两平面长度不一致时抛错', () {
    expect(
      () => convertUC8159(Uint8List(2), Uint8List(3)),
      throwsArgumentError,
    );
  });
}
