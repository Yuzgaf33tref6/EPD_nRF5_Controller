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
      // 1 / 1.1 ≈ 0.909 < 下限 1，所以夹回 1 —— 这正是「不会缩到比铺满更小」。
      expect(cropViewZoomByWheel(1, zoomIn: false), 1);
      // 从 2 缩小一次才看得出倍率生效：2 * 0.9 = 1.8。
      expect(cropViewZoomByWheel(2, zoomIn: false), closeTo(1.8, 1e-9));
      expect(cropViewZoomByWheel(1.2, zoomIn: false), closeTo(1.08, 1e-9));
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

  group('previewBoxSize（回归：预览贴图尺寸不能被当成原图尺寸）', () {
    test('大图缩到 1080 后，预览框按预览像素算', () {
      final CropPreviewSize size = previewSizeForSource(
        width: 4000,
        height: 3000,
        maxEdge: 1080,
      );
      expect(size.width, 1080);
      expect(size.height, 810);
      expect(size.scale, closeTo(1080 / 4000, 1e-9));
    });

    test('小图不放大', () {
      final CropPreviewSize size = previewSizeForSource(
        width: 800,
        height: 600,
        maxEdge: 1080,
      );
      expect(size.width, 800);
      expect(size.height, 600);
      expect(size.scale, 1);
    });

    test('竖图按长边缩放', () {
      final CropPreviewSize size = previewSizeForSource(
        width: 600,
        height: 2400,
        maxEdge: 1080,
      );
      expect(size.height, 1080);
      expect(size.width, 270);
    });

    test('源图尺寸非法时退回 1x1，不会除零', () {
      final CropPreviewSize size = previewSizeForSource(
        width: 0,
        height: 0,
        maxEdge: 1080,
      );
      expect(size.width, 1);
      expect(size.height, 1);
      expect(size.scale, 1);
    });
  });

  group('预览与出图一致（回归）', () {
    // 这个 bug 的表现：裁剪页把「预览贴图的像素尺寸」错存成了「工作图尺寸」，
    // 于是画面上图片缩在左上角、偏小三分之二，而真正裁出来的图却是对的
    // —— 用户看到「预览」和「出图」两个样子。
    test('zoom=1 时源矩形覆盖整张图且比例等于画布', () {
      const double imageWidth = 4000;
      const double imageHeight = 3000;
      const double viewWidth = 800;
      const double viewHeight = 600;
      final CropViewRect source = sourceRectForView(
        imageWidth: imageWidth,
        imageHeight: imageHeight,
        viewWidth: viewWidth,
        viewHeight: viewHeight,
        state: const CropViewState(),
      );
      expect(source.left, closeTo(0, 1e-9));
      expect(source.top, closeTo(0, 1e-9));
      expect(source.width, closeTo(imageWidth, 1e-9));
      expect(source.height, closeTo(imageHeight, 1e-9));
      expect(
        source.width / source.height,
        closeTo(viewWidth / viewHeight, 1e-9),
      );
    });

    test('放大 2 倍时源矩形正好是视口对应区域的一半', () {
      final CropViewRect source = sourceRectForView(
        imageWidth: 400,
        imageHeight: 300,
        viewWidth: 400,
        viewHeight: 300,
        state: const CropViewState(zoom: 2),
      );
      expect(source.width, closeTo(200, 1e-9));
      expect(source.height, closeTo(150, 1e-9));
      expect(source.left, closeTo(100, 1e-9));
      expect(source.top, closeTo(75, 1e-9));
    });

    test('源矩形永远落在图内（哪怕平移被夹到边上）', () {
      final CropViewState state = const CropViewState(panX: 99999, panY: -99999)
          .clamped(
        imageWidth: 4000,
        imageHeight: 3000,
        viewWidth: 800,
        viewHeight: 600,
      );
      final CropViewRect source = sourceRectForView(
        imageWidth: 4000,
        imageHeight: 3000,
        viewWidth: 800,
        viewHeight: 600,
        state: state,
      );
      expect(source.left, greaterThanOrEqualTo(-1e-9));
      expect(source.top, greaterThanOrEqualTo(-1e-9));
      expect(source.left + source.width, lessThanOrEqualTo(4000 + 1e-9));
      expect(source.top + source.height, lessThanOrEqualTo(3000 + 1e-9));
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
