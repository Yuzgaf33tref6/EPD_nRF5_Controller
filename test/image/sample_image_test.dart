import 'package:flutter_test/flutter_test.dart';

import 'package:epd_controller/image/rgba_image.dart';
import 'package:epd_controller/image/sample_image.dart';

void main() {
  group('sampleImage', () {
    test('尺寸正确，缓冲长度是 宽×高×4', () {
      final RgbaImage image = sampleImage(37, 19);
      expect(image.width, 37);
      expect(image.height, 19);
      expect(image.data.length, 37 * 19 * 4);
    });

    test('完全确定：同尺寸两次生成逐字节相同', () {
      final RgbaImage a = sampleImage(64, 48);
      final RgbaImage b = sampleImage(64, 48);
      expect(a.data, equals(b.data));
    });

    test('alpha 全部是不透明的 255', () {
      final RgbaImage image = sampleImage(23, 17);
      for (int i = 3; i < image.data.length; i += 4) {
        expect(image.data[i], 255);
      }
    });

    test('包含红色带、纯黑块与亮蓝块（供抖动算法有东西可量化）', () {
      final RgbaImage image = sampleImage(400, 300);
      int red = 0;
      int black = 0;
      int blue = 0;
      for (int i = 0; i < image.data.length; i += 4) {
        final int r = image.data[i];
        final int g = image.data[i + 1];
        final int b = image.data[i + 2];
        if (r > 200 && g < 60 && b < 60) {
          red++;
        } else if (r == 0 && g == 0 && b == 0) {
          black++;
        } else if (b > 200 && r < 60) {
          blue++;
        }
      }
      expect(red, greaterThan(0));
      expect(black, greaterThan(0));
      expect(blue, greaterThan(0));
    });

    test('1×1 这种极端尺寸也能生成（渐变不除零）', () {
      final RgbaImage image = sampleImage(1, 1);
      expect(image.width, 1);
      expect(image.height, 1);
      expect(image.data.length, 4);
    });

    test('尺寸非法时退回 1×1 而不是抛异常', () {
      final RgbaImage image = sampleImage(0, 0);
      expect(image.width, 1);
      expect(image.height, 1);
    });
  });
}
