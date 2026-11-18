import 'dart:typed_data';

import 'package:epd_controller/image/rgba_image.dart';
import 'package:epd_controller/image/text_stamp.dart';
import 'package:flutter_test/flutter_test.dart';

RgbaImage solidImage(int width, int height, List<int> rgba) {
  final Uint8List data = Uint8List(width * height * 4);
  for (int i = 0; i < data.length; i += 4) {
    data[i] = rgba[0];
    data[i + 1] = rgba[1];
    data[i + 2] = rgba[2];
    data[i + 3] = rgba[3];
  }
  return RgbaImage(width, height, data);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('文字贴图', () {
    test('alpha 足够大的像素才会盖住底图', () {
      final RgbaImage base = solidImage(4, 4, <int>[255, 255, 255, 255]);
      final RgbaImage overlay = solidImage(2, 2, <int>[0, 0, 0, 255]);
      overlay.data[4 + 3] = 100; // 第二个像素（右上）alpha 低于阈值

      compositeOver(base, overlay, offsetX: 1, offsetY: 1);

      int pixelAt(int x, int y) => (y * 4 + x) * 4;
      expect(base.data[pixelAt(1, 1)], 0);
      expect(base.data[pixelAt(1, 1) + 3], 255);
      // 低 alpha 的像素保持原样
      expect(base.data[pixelAt(2, 1)], 255);
      // 区域外保持原样
      expect(base.data[pixelAt(0, 0)], 255);
    });

    test('越界部分被裁掉，不会写坏内存', () {
      final RgbaImage base = solidImage(3, 3, <int>[255, 255, 255, 255]);
      final RgbaImage overlay = solidImage(3, 3, <int>[0, 0, 0, 255]);
      compositeOver(base, overlay, offsetX: -1, offsetY: -1);
      expect(base.data[0], 0); // (0,0) 对应 overlay 的 (1,1)
      compositeOver(base, overlay, offsetX: 10, offsetY: 10); // 全越界
      expect(base.data.length, 3 * 3 * 4);
    });

    test('贴上去的像素 alpha 会被强制成不透明', () {
      final RgbaImage base = solidImage(2, 2, <int>[255, 255, 255, 0]);
      final RgbaImage overlay = solidImage(2, 2, <int>[10, 20, 30, 200]);
      compositeOver(base, overlay, offsetX: 0, offsetY: 0);
      expect(base.data[0], 10);
      expect(base.data[1], 20);
      expect(base.data[2], 30);
      expect(base.data[3], 255);
    });
  });

  testWidgets('renderText 能把字光栅化成有墨迹的位图', (WidgetTester tester) async {
    await tester.runAsync(() async {
      final RgbaImage image = await renderText(
        text: 'EPD',
        fontSize: 48,
        r: 0,
        g: 0,
        b: 0,
      );
      expect(image.width, greaterThan(10));
      expect(image.height, greaterThan(10));
      expect(image.data.length, image.width * image.height * 4);

      int inked = 0;
      for (int i = 3; i < image.data.length; i += 4) {
        if (image.data[i] >= 128) {
          inked++;
        }
      }
      expect(inked, greaterThan(0), reason: '应该画出一些文字像素');
    });
  });
}
