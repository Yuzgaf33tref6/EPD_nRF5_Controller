/// 抖动算法与 web 版的对拍测试。
///
/// 每条向量都来自 `tools/gen-dither-golden.mjs` 直接运行 `html/js/dithering.js`
/// 得到的真实结果，因此这里比较的是**逐字节相同**，不是"看起来差不多"。
library;

import 'dart:convert';

import 'package:epd_controller/image/dither.dart';
import 'package:epd_controller/image/epd_color.dart';
import 'package:epd_controller/image/rgba_image.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/golden.dart';

void runDitherGolden(String fileName) {
  final Map<String, dynamic> golden = loadGoldenJson(fileName);
  final Map<String, dynamic> images =
      golden['images'] as Map<String, dynamic>;
  final List<Map<String, dynamic>> cases = (golden['cases'] as List<dynamic>)
      .cast<Map<String, dynamic>>();

  for (final Map<String, dynamic> item in cases) {
    final String imageName = item['image'] as String;
    final String algName = item['alg'] as String;
    final String modeName = item['mode'] as String;
    final double strength = (item['strength'] as num).toDouble();

    test('$imageName / $algName / $modeName / strength=$strength', () {
      final RgbaImage image =
          imageFromGolden(images[imageName] as Map<String, dynamic>);
      final RgbaImage result = ditherImage(
        image,
        DitherAlgorithm.fromJsName(algName),
        strength,
        EpdColorMode.fromJsName(modeName),
      );
      expectBytesMatchGolden(item['expected'] as String, result.data);
    });
  }
}

void main() {
  group('抖动：小图全算法全模式（web 版对拍）', () {
    runDitherGolden('dither_small.json');
  });

  group('抖动：400x300 真实尺寸（web 版对拍）', () {
    runDitherGolden('dither_real.json');
  });

  test('none 算法不改动任何字节', () {
    final RgbaImage image = RgbaImage(4, 3);
    for (int i = 0; i < image.data.length; i++) {
      image.data[i] = (i * 7 + 3) & 0xff;
    }
    final RgbaImage snapshot = image.clone();
    final RgbaImage result =
        ditherImage(image, DitherAlgorithm.none, 1.0, EpdColorMode.sixColor);
    expect(base64Encode(result.data), base64Encode(snapshot.data));
  });

  test('未知算法名抛错', () {
    expect(
      () => DitherAlgorithm.fromJsName('notAnAlgorithm'),
      throwsArgumentError,
    );
  });
}
