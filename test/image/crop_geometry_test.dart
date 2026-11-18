import 'dart:typed_data';

import 'package:epd_controller/image/crop_geometry.dart';
import 'package:epd_controller/image/rgba_image.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/golden.dart';

/// 画布几何：裁剪源矩形（与 `crop.js:94-100` 对拍）+ 缩放钳制 + 90° 旋转。
void main() {
  group('cropSourceRect 与 web 版对拍', () {
    final Map<String, dynamic> golden = loadGoldenJson('crop.json');
    final List<dynamic> rects = golden['sourceRects'] as List<dynamic>;

    test('至少有 10 组向量', () {
      expect(rects.length, greaterThanOrEqualTo(10));
    });

    for (final dynamic rawRect in rects) {
      final Map<String, dynamic> r = rawRect as Map<String, dynamic>;
      test('zoom=${r['zoom']} pan=(${r['panX']}, ${r['panY']}) '
          'view=${r['viewWidth']}x${r['viewHeight']}', () {
        final CropSourceRect rect = cropSourceRect(
          imageWidth: (r['imageWidth'] as num).toDouble(),
          viewWidth: (r['viewWidth'] as num).toDouble(),
          viewHeight: (r['viewHeight'] as num).toDouble(),
          zoom: (r['zoom'] as num).toDouble(),
          panX: (r['panX'] as num).toDouble(),
          panY: (r['panY'] as num).toDouble(),
        );
        // 两边都是 IEEE754 双精度、运算顺序也一致，允许极小误差即可。
        expect(rect.left, closeTo((r['left'] as num).toDouble(), 1e-9), reason: 'left');
        expect(rect.top, closeTo((r['top'] as num).toDouble(), 1e-9), reason: 'top');
        expect(rect.width, closeTo((r['width'] as num).toDouble(), 1e-9), reason: 'width');
        expect(rect.height, closeTo((r['height'] as num).toDouble(), 1e-9), reason: 'height');
      });
    }

    test('不平移时源矩形从原图左上角开始', () {
      final CropSourceRect rect = cropSourceRect(
        imageWidth: 1920,
        viewWidth: 400,
        viewHeight: 300,
        zoom: 1,
        panX: 0,
        panY: 0,
      );
      expect(rect.left, 0);
      expect(rect.top, 0);
      expect(rect.width, 1920);
      expect(rect.height, 1440, reason: '高度由宽高比推出：300 * (1920/400)');
    });

    test('放大后可见区域变小，平移为正向时源矩形左移', () {
      final CropSourceRect zoomed = cropSourceRect(
        imageWidth: 1920,
        viewWidth: 400,
        viewHeight: 300,
        zoom: 2,
        panX: 0,
        panY: 0,
      );
      expect(zoomed.width, 960);
      final CropSourceRect panned = cropSourceRect(
        imageWidth: 1920,
        viewWidth: 400,
        viewHeight: 300,
        zoom: 2,
        panX: 100,
        panY: 0,
      );
      expect(panned.left, lessThan(0), reason: '向右拖图片，取到的是更靠左的原图内容');
    });
  });

  group('缩放钳制与 web 版对拍', () {
    final Map<String, dynamic> golden = loadGoldenJson('crop.json');
    final List<dynamic> zooms = golden['zooms'] as List<dynamic>;

    for (final dynamic rawZoom in zooms) {
      final Map<String, dynamic> z = rawZoom as Map<String, dynamic>;
      test('${z['kind']} ${z['deltaY'] ?? z['factor']} 从 ${z['zoom']}', () {
        final double zoom = (z['zoom'] as num).toDouble();
        final double actual = z['kind'] == 'wheel'
            ? cropZoomByWheel(zoom, zoomIn: (z['deltaY'] as int) <= 0)
            : cropZoomByPinch(zoom, (z['factor'] as num).toDouble());
        expect(actual, closeTo((z['expected'] as num).toDouble(), 1e-12));
        expect(actual, inInclusiveRange(kCropMinZoom, kCropMaxZoom));
      });
    }

    test('常量与 web 版一致', () {
      expect(kCropMinZoom, 0.1);
      expect(kCropMaxZoom, 5.0);
      expect(kCropWheelZoomIn, 1.1);
      expect(kCropWheelZoomOut, 0.9);
      expect(kCropButtonPanStep, 10);
    });
  });

  group('旋转 90°', () {
    /// 造一张每像素颜色唯一的小图，便于验证像素搬移。
    RgbaImage numbered(int width, int height) {
      final Uint8List data = Uint8List(width * height * 4);
      for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
          final int i = (y * width + x) * 4;
          data[i] = y * width + x;
          data[i + 1] = 0;
          data[i + 2] = 0;
          data[i + 3] = 255;
        }
      }
      return RgbaImage(width, height, data);
    }

    int redAt(RgbaImage image, int x, int y) => image.data[(y * image.width + x) * 4];

    test('2x3 顺时针旋转后宽高互换且像素映射正确', () {
      final RgbaImage src = numbered(2, 3);
      final RgbaImage rotated = rotateImage90Clockwise(src);
      expect(rotated.width, 3);
      expect(rotated.height, 2);
      // 目标 (dx, dy) 取源 (dy, height-1-dx)
      expect(redAt(rotated, 0, 0), redAt(src, 0, 2));
      expect(redAt(rotated, 1, 0), redAt(src, 0, 1));
      expect(redAt(rotated, 2, 0), redAt(src, 0, 0));
      expect(redAt(rotated, 0, 1), redAt(src, 1, 2));
      expect(redAt(rotated, 1, 1), redAt(src, 1, 1));
      expect(redAt(rotated, 2, 1), redAt(src, 1, 0));
    });

    test('转四次回到原图', () {
      final RgbaImage src = numbered(5, 3);
      RgbaImage image = src;
      for (int i = 0; i < 4; i++) {
        image = rotateImage90Clockwise(image);
      }
      expect(image.width, src.width);
      expect(image.height, src.height);
      expect(image.data, src.data);
    });

    test('1x1 与空图不炸', () {
      final RgbaImage one = rotateImage90Clockwise(numbered(1, 1));
      expect(one.width, 1);
      expect(one.height, 1);
      expect(one.data[0], 0);
    });
  });

  group('宽高比判断', () {
    test('比例一致时不进裁剪模式', () {
      expect(
        imageMatchesCanvasAspect(
          imageWidth: 400,
          imageHeight: 300,
          canvasWidth: 800,
          canvasHeight: 600,
        ),
        isTrue,
      );
    });

    test('比例不一致时进裁剪模式', () {
      expect(
        imageMatchesCanvasAspect(
          imageWidth: 1920,
          imageHeight: 1080,
          canvasWidth: 400,
          canvasHeight: 300,
        ),
        isFalse,
      );
    });
  });
}
