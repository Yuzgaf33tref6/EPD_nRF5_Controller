/// 对比度调整与 web 版的对拍测试。
library;

import 'package:epd_controller/image/dither.dart';
import 'package:epd_controller/image/rgba_image.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/golden.dart';

void main() {
  group('对比度调整（web 版对拍）', () {
    final Map<String, dynamic> golden = loadGoldenJson('adjust_contrast.json');
    final Map<String, dynamic> images =
        golden['images'] as Map<String, dynamic>;
    final List<Map<String, dynamic>> cases =
        (golden['cases'] as List<dynamic>).cast<Map<String, dynamic>>();

    for (final Map<String, dynamic> item in cases) {
      final String imageName = item['image'] as String;
      final double factor = (item['factor'] as num).toDouble();

      test('$imageName / factor=$factor', () {
        final RgbaImage image =
            imageFromGolden(images[imageName] as Map<String, dynamic>);
        final RgbaImage result = adjustContrast(image, factor);
        expectBytesMatchGolden(item['expected'] as String, result.data);
      });
    }
  });
}
