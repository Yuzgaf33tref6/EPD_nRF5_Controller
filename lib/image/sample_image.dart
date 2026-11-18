/// 不含第三方依赖的示例图像生成器。
///
/// UI 骨架阶段需要一张图来演示抖动与传图流程，但项目暂时不引入 `image` / `image_picker`
/// 这类包（用户要求先把纯 Dart 部分做完）。所以这里用纯 Dart 画一张确定性的测试图：
/// 灰阶渐变底 + 几块纯色区域，既能看到抖动的网点，也能看到色相差异。
library;

import 'dart:typed_data';

import 'rgba_image.dart';

/// 生成一张 [width]×[height] 的示例图。
///
/// 结果完全确定（不含随机数），同一尺寸每次调用得到的像素一致，便于对照。
RgbaImage sampleImage(int width, int height) {
  final int w = width < 1 ? 1 : width;
  final int h = height < 1 ? 1 : height;
  final Uint8List data = Uint8List(w * h * 4);

  final double lastX = (w - 1).toDouble();
  final double lastY = (h - 1).toDouble();

  // 底：左上到右下的灰阶渐变。
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      final double tx = lastX == 0 ? 0 : x / lastX;
      final double ty = lastY == 0 ? 0 : y / lastY;
      int gray = ((tx * 0.65 + ty * 0.35) * 255).round();
      gray = gray < 0 ? 0 : (gray > 255 ? 255 : gray);
      final int i = (y * w + x) * 4;
      data[i] = gray;
      data[i + 1] = gray;
      data[i + 2] = gray;
      data[i + 3] = 255;
    }
  }

  // 上：一条红色横带（三色屏的红通道）。
  _fillRect(
    data,
    w,
    h,
    left: (w * 0.08).round(),
    top: (h * 0.08).round(),
    right: (w * 0.92).round(),
    bottom: (h * 0.26).round(),
    r: 220,
    g: 30,
    b: 40,
  );

  // 左下：纯黑方块（检查黑白平面的边缘与阈值）。
  _fillRect(
    data,
    w,
    h,
    left: (w * 0.08).round(),
    top: (h * 0.60).round(),
    right: (w * 0.42).round(),
    bottom: (h * 0.92).round(),
    r: 0,
    g: 0,
    b: 0,
  );

  // 右下：亮蓝方块（六色/四色模式下会被量化到别的颜色）。
  _fillRect(
    data,
    w,
    h,
    left: (w * 0.50).round(),
    top: (h * 0.60).round(),
    right: (w * 0.92).round(),
    bottom: (h * 0.92).round(),
    r: 30,
    g: 90,
    b: 220,
  );

  // 中间：一列白色竖条，用于观察 1bpp 打包时的边界。
  _fillRect(
    data,
    w,
    h,
    left: (w * 0.45).round(),
    top: (h * 0.34).round(),
    right: (w * 0.55).round(),
    bottom: (h * 0.56).round(),
    r: 255,
    g: 255,
    b: 255,
  );

  return RgbaImage(w, h, data);
}

/// 就地填充一个矩形（坐标会被裁剪到图像范围内，右下边界不含）。
void _fillRect(
  Uint8List data,
  int width,
  int height, {
  required int left,
  required int top,
  required int right,
  required int bottom,
  required int r,
  required int g,
  required int b,
}) {
  final int cx0 = _clampInt(left, 0, width);
  final int cx1 = _clampInt(right, 0, width);
  final int cy0 = _clampInt(top, 0, height);
  final int cy1 = _clampInt(bottom, 0, height);
  for (int y = cy0; y < cy1; y++) {
    for (int x = cx0; x < cx1; x++) {
      final int i = (y * width + x) * 4;
      data[i] = r;
      data[i + 1] = g;
      data[i + 2] = b;
      data[i + 3] = 255;
    }
  }
}

/// 把 [value] 夹到 `[min, max]`，返回 int（`int.clamp` 返回的是 num，不能直接当 int 用）。
int _clampInt(int value, int min, int max) {
  if (value < min) {
    return min;
  }
  if (value > max) {
    return max;
  }
  return value;
}
