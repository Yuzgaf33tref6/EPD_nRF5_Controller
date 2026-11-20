import 'package:epd_controller/image/crop_view_geometry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('fitCanvasRect', () {
    test('宽区域放 4:3 画布，按高度或宽度取较小者并居中', () {
      final CropViewRect rect = fitCanvasRect(
        availableWidth: 1000,
        availableHeight: 400,
        canvasWidth: 400,
        canvasHeight: 300,
      );
      // 高度吃满 400，宽度 = 400 * 4/3 ≈ 533.3，水平居中。
      expect(rect.height, closeTo(400, 1e-9));
      expect(rect.width, closeTo(400 * 4 / 3, 1e-9));
      expect(rect.left, closeTo((1000 - 400 * 4 / 3) / 2, 1e-9));
      expect(rect.top, closeTo(0, 1e-9));
    });

    test('尺寸非法时退回 1x1，不会崩', () {
      final CropViewRect rect = fitCanvasRect(
        availableWidth: 0,
        availableHeight: 100,
        canvasWidth: 400,
        canvasHeight: 300,
      );
      expect(rect.width, 1);
      expect(rect.height, 1);
    });
  });

  group('缩放', () {
    test('滚轮放大/缩小并夹在 1~5 之间', () {
      expect(cropViewZoomByWheel(1, zoomIn: true), closeTo(1.1, 1e-9));
      expect(cropViewZoomByWheel(1.1, zoomIn: false), closeTo(0.99, 1e-9));
      // 下限是 1，不会缩到比铺满更小（否则会露出空白）。
      expect(cropViewZoomByWheel(1, zoomIn: false), 1);
      expect(cropViewZoomByWheel(4.9, zoomIn: true), 5);
    });

    test('双指缩放同样夹紧', () {
      expect(cropViewZoomByPinch(2, 1.5), 3);
      expect(cropViewZoomByPinch(2, 0.1), 1);
      expect(cropViewZoomByPinch(2, 100), 5);
    });

    test('平移被限制在图片铺满视口的范围内', () {
      // 400x300 的图画在 400x300 视口里，zoom=1 时没有任何可平移余量。
      const CropViewState state =
          CropViewState(zoom: 1, panX: 999, panY: -999);
      final CropViewState clamped = state.clamped(
        imageWidth: 400,
        imageHeight: 300,
        viewWidth: 400,
        viewHeight: 300,
      );
      expect(clamped.panX, 0);
      expect(clamped.panY, 0);
      expect(clamped.zoom, 1);
    });
  });

  group('sourceRectForView', () {
    test('zoom=1 且同比例时正好取整张图', () {
      final CropViewRect rect = sourceRectForView(
        imageWidth: 400,
        imageHeight: 300,
        viewWidth: 400,
        viewHeight: 300,
        state: const CropViewState(),
      );
      expect(rect.left, closeTo(0, 1e-9));
      expect(rect.top, closeTo(0, 1e-9));
      expect(rect.width, closeTo(400, 1e-9));
      expect(rect.height, closeTo(300, 1e-9));
    });

    test('放大 2 倍后只取中间四分之一', () {
      final CropViewRect rect = sourceRectForView(
        imageWidth: 400,
        imageHeight: 300,
        viewWidth: 400,
        viewHeight: 300,
        state: const CropViewState(zoom: 2),
      );
      expect(rect.left, closeTo(100, 1e-9));
      expect(rect.top, closeTo(75, 1e-9));
      expect(rect.width, closeTo(200, 1e-9));
      expect(rect.height, closeTo(150, 1e-9));
    });

    test('竖图铺横屏视口：源矩形完整覆盖全部高度，不留空', () {
      // 600x1200 的竖图画进 400x300 的横屏视口。
      // cover 比例 = max(400/600, 300/1200) = 2/3 → 显示 400x800，上下各溢出 250。
      final CropViewRect rect = sourceRectForView(
        imageWidth: 600,
        imageHeight: 1200,
        viewWidth: 400,
        viewHeight: 300,
        state: const CropViewState(),
      );
      // 源矩形高 = 300 * (600/400) = 450，落在 1200 里，居中：375..825。
      expect(rect.width, closeTo(600, 1e-9));
      expect(rect.height, closeTo(450, 1e-9));
      expect(rect.top, closeTo(375, 1e-9));
      expect(rect.top + rect.height, lessThanOrEqualTo(1200));
      expect(rect.top, greaterThanOrEqualTo(0));
    });
  });

  group('imageDisplayRect', () {
    test('cover 保证图片始终不小于视口', () {
      final CropViewRect display = imageDisplayRect(
        imageWidth: 600,
        imageHeight: 1200,
        viewWidth: 400,
        viewHeight: 300,
        state: const CropViewState(),
      );
      expect(display.width, greaterThanOrEqualTo(400));
      expect(display.height, greaterThanOrEqualTo(300));
    });
  });

  group('shouldSuggestRotate', () {
    test('竖图 + 横屏画布才提示', () {
      expect(
        shouldSuggestRotate(
          imageWidth: 600,
          imageHeight: 1200,
          canvasWidth: 400,
          canvasHeight: 300,
        ),
        isTrue,
      );
      expect(
        shouldSuggestRotate(
          imageWidth: 1200,
          imageHeight: 600,
          canvasWidth: 400,
          canvasHeight: 300,
        ),
        isFalse,
      );
      expect(
        shouldSuggestRotate(
          imageWidth: 600,
          imageHeight: 1200,
          canvasWidth: 300,
          canvasHeight: 400,
        ),
        isFalse,
      );
    });
  });
}
