import 'dart:typed_data';

import 'package:epd_controller/image/image_transform.dart';
import 'package:epd_controller/image/rgba_image.dart';
import 'package:flutter_test/flutter_test.dart';

/// 造一张 [width] x [height] 的图，像素颜色由 [pixel] 决定。
RgbaImage buildImage(
  int width,
  int height,
  List<int> Function(int x, int y) pixel,
) {
  final Uint8List data = Uint8List(width * height * 4);
  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      final List<int> rgb = pixel(x, y);
      final int offset = (y * width + x) * 4;
      data[offset] = rgb[0];
      data[offset + 1] = rgb[1];
      data[offset + 2] = rgb[2];
      data[offset + 3] = 255;
    }
  }
  return RgbaImage(width, height, data);
}

List<int> pixelAt(RgbaImage image, int x, int y) {
  final int offset = (y * image.width + x) * 4;
  return <int>[
    image.data[offset],
    image.data[offset + 1],
    image.data[offset + 2],
  ];
}

void main() {
  group('resizeBilinear', () {
    test('纯色图缩放后仍是纯色，alpha 为 255', () {
      final RgbaImage source = buildImage(2, 2, (int x, int y) {
        return <int>[10, 20, 30];
      });
      final RgbaImage resized = resizeBilinear(source, 7, 5);
      expect(resized.width, 7);
      expect(resized.height, 5);
      expect(resized.data.length, 7 * 5 * 4);
      for (int y = 0; y < 5; y++) {
        for (int x = 0; x < 7; x++) {
          expect(pixelAt(resized, x, y), <int>[10, 20, 30]);
        }
      }
      for (int i = 3; i < resized.data.length; i += 4) {
        expect(resized.data[i], 255);
      }
    });

    test('2x1 黑白图放大到 3x1：左黑、中间过渡、右白', () {
      final RgbaImage source = buildImage(
        2,
        1,
        (int x, int y) => x == 0 ? <int>[0, 0, 0] : <int>[255, 255, 255],
      );
      final RgbaImage resized = resizeBilinear(source, 3, 1);
      expect(pixelAt(resized, 0, 0), <int>[0, 0, 0]);
      final List<int> middle = pixelAt(resized, 1, 0);
      expect(middle[0], closeTo(128, 2));
      expect(middle[0], middle[1]);
      expect(middle[1], middle[2]);
      expect(pixelAt(resized, 2, 0), <int>[255, 255, 255]);
    });

    test('尺寸相同返回拷贝，不是同一个对象', () {
      final RgbaImage source = buildImage(3, 2, (int x, int y) {
        return <int>[x * 10, y * 10, 0];
      });
      final RgbaImage resized = resizeBilinear(source, 3, 2);
      expect(identical(resized.data, source.data), isFalse);
      expect(resized.data, source.data);
    });

    test('目标尺寸非正抛参数错误', () {
      final RgbaImage source = buildImage(2, 2, (int x, int y) {
        return <int>[0, 0, 0];
      });
      expect(() => resizeBilinear(source, 0, 4), throwsArgumentError);
      expect(() => resizeBilinear(source, 4, 0), throwsArgumentError);
    });
  });

  group('cropScaled', () {
    test('取左半边得到纯黑，输出尺寸即画布尺寸', () {
      // 采样点落在 x∈[0,1] 区间内，两侧都是黑，所以不会混到白。
      // 注意 width=1 时步长 0.2，靠右的采样点 x 会逼近 1（仍 < 2，不跨列）。
      final RgbaImage source = buildImage(
        4,
        4,
        (int x, int y) => x < 2 ? <int>[0, 0, 0] : <int>[255, 255, 255],
      );
      final RgbaImage cropped = cropScaled(
        source: source,
        left: 0,
        top: 0,
        width: 1,
        height: 1,
        outWidth: 10,
        outHeight: 6,
      );
      expect(cropped.width, 10);
      expect(cropped.height, 6);
      for (int y = 0; y < 6; y++) {
        for (int x = 0; x < 10; x++) {
          expect(pixelAt(cropped, x, y), <int>[0, 0, 0]);
        }
      }
    });

    test('取右半边得到纯白', () {
      final RgbaImage source = buildImage(
        4,
        4,
        (int x, int y) => x < 2 ? <int>[0, 0, 0] : <int>[255, 255, 255],
      );
      final RgbaImage cropped = cropScaled(
        source: source,
        left: 3,
        top: 0,
        width: 1,
        height: 1,
        outWidth: 5,
        outHeight: 5,
      );
      expect(pixelAt(cropped, 0, 0), <int>[255, 255, 255]);
      expect(pixelAt(cropped, 4, 4), <int>[255, 255, 255]);
    });

    test('裁剪矩形超出源图时按填充色补齐（默认白）', () {
      // 源图 2x2：只有 (0,0) 是蓝色，其余灰色。
      // 裁剪矩形 -4..8 共 12 像素缩到 8，采样点 step = 1.5：
      // 输出 (0,0) → 源 (0.5,0.5)-0.5 = (-3.5,-3.5) 在图外 → 白；
      // 输出 (3,3) → 源 (-4 + 3.5*1.5) = 1.25 → 落在 (1,1) 灰-灰之间 → 灰。
      // 这里要验证的是「图外用填充色」，源图内的颜色另有断言。
      final RgbaImage source = buildImage(2, 2, (int x, int y) {
        return <int>[9, 9, 9];
      });
      final RgbaImage cropped = cropScaled(
        source: source,
        left: -4,
        top: -4,
        width: 12,
        height: 12,
        outWidth: 8,
        outHeight: 8,
      );
      expect(cropped.width, 8);
      expect(cropped.height, 8);
      // 四角都在源图之外，补白。
      expect(pixelAt(cropped, 0, 0), <int>[255, 255, 255]);
      expect(pixelAt(cropped, 7, 7), <int>[255, 255, 255]);
      // 中间落在源图内，是源图的颜色。
      expect(pixelAt(cropped, 3, 3), <int>[9, 9, 9]);
    });

    test('可以指定补黑', () {
      final RgbaImage source = buildImage(2, 2, (int x, int y) {
        return <int>[200, 200, 200];
      });
      final RgbaImage cropped = cropScaled(
        source: source,
        left: -4,
        top: -4,
        width: 12,
        height: 12,
        outWidth: 8,
        outHeight: 8,
        fill: CropFill.black,
      );
      expect(pixelAt(cropped, 0, 0), <int>[0, 0, 0]);
      expect(pixelAt(cropped, 7, 7), <int>[0, 0, 0]);
      expect(pixelAt(cropped, 3, 3), <int>[200, 200, 200]);
    });

    test('cropRectFitsInside 能分辨有没有留空', () {
      // 10x10 的源图，按采样点是否落在 [-0.5, 9.5] 判断。
      final RgbaImage source =
          buildImage(10, 10, (int x, int y) => <int>[0, 0, 0]);
      expect(
        cropRectFitsInside(
          source: source,
          left: 0,
          top: 0,
          width: 10,
          height: 10,
        ),
        isTrue,
      );
      expect(
        cropRectFitsInside(
          source: source,
          left: -1,
          top: 0,
          width: 10,
          height: 10,
        ),
        isFalse,
      );
      // 右边越界也算留空。
      expect(
        cropRectFitsInside(
          source: source,
          left: 0,
          top: 0,
          width: 12,
          height: 10,
        ),
        isFalse,
      );
    });

    test('参数非法抛参数错误', () {
      final RgbaImage source = buildImage(2, 2, (int x, int y) {
        return <int>[0, 0, 0];
      });
      expect(
        () => cropScaled(
          source: source,
          left: 0,
          top: 0,
          width: 0,
          height: 2,
          outWidth: 4,
          outHeight: 4,
        ),
        throwsArgumentError,
      );
      expect(
        () => cropScaled(
          source: source,
          left: 0,
          top: 0,
          width: 2,
          height: 2,
          outWidth: 0,
          outHeight: 4,
        ),
        throwsArgumentError,
      );
    });
  });
}
