/// 画布几何 —— 裁剪模式与旋转。
///
/// 对应 web 版 `html/js/crop.js` 的缩放/平移状态与 `finishCrop()`（第 86-109 行），
/// 以及 `html/js/main.js` 的 `rotateCanvas()`（565-592）。
///
/// web 版把图片当作 CSS 背景贴在 canvas 上，靠 `background-size` / `background-position`
/// 实现缩放平移，最后用 `drawImage` 把"看得见的那块"画进画布。这里把那段几何抽成
/// 纯函数，Flutter 侧用 `InteractiveViewer` 或手势自己维护 zoom/pan，出图时调
/// [cropSourceRect] 拿源矩形即可。
library;

import 'dart:typed_data';

import 'rgba_image.dart';

/// 缩放下限（web 版 `Math.max(0.1, ...)`）。
const double kCropMinZoom = 0.1;

/// 缩放上限（web 版 `Math.min(5, ...)`）。
const double kCropMaxZoom = 5.0;

/// 滚轮每格的缩放倍率（web 版 `deltaY > 0 ? 0.9 : 1.1`）。
const double kCropWheelZoomIn = 1.1;
const double kCropWheelZoomOut = 0.9;

/// 裁剪工具按钮每次平移的像素数（web 版 `±10`）。
const double kCropButtonPanStep = 10;

double _clampZoom(double zoom) =>
    zoom.clamp(kCropMinZoom, kCropMaxZoom).toDouble();

/// 滚轮缩放。[zoomIn] 为真表示放大（web 版 `deltaY <= 0`）。
double cropZoomByWheel(double zoom, {required bool zoomIn}) =>
    _clampZoom(zoom * (zoomIn ? kCropWheelZoomIn : kCropWheelZoomOut));

/// 双指捏合缩放。[factor] = 当前两指距离 / 上一次两指距离。
double cropZoomByPinch(double zoom, double factor) => _clampZoom(zoom * factor);

/// 裁剪模式下"可见区域"映射回原图的源矩形。
class CropSourceRect {
  const CropSourceRect({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  /// 原图坐标（可为小数，绘制时由调用方取整）。
  final double left;
  final double top;
  final double width;
  final double height;

  double get right => left + width;
  double get bottom => top + height;

  @override
  String toString() =>
      'CropSourceRect(left: $left, top: $top, $width x $height)';
}

/// 计算"画布上看到的那块图片"在原图中的位置。
///
/// 逐行对应 `crop.js:94-100`：
/// ```js
/// const scale = (image.width / fieldsetRect.width) / this.backgroundZoom;
/// const sx = -this.backgroundPanX * scale;
/// const sy = -this.backgroundPanY * scale;
/// const sWidth = fieldsetRect.width * scale;
/// const sHeight = fieldsetRect.height * scale;
/// ```
/// 注意 `scale` 只由图片宽度与可见宽度决定，高度不参与 —— 原样保留。
///
/// * [imageWidth] 原图宽度（像素）
/// * [viewWidth] / [viewHeight] 画布在屏幕上的实际尺寸（`getBoundingClientRect()`）
/// * [zoom] 缩放倍率，见 [kCropMinZoom] / [kCropMaxZoom]
/// * [panX] / [panY] 平移量（CSS 像素，右/下为正）
CropSourceRect cropSourceRect({
  required double imageWidth,
  required double viewWidth,
  required double viewHeight,
  required double zoom,
  required double panX,
  required double panY,
}) {
  final double scale = (imageWidth / viewWidth) / zoom;
  return CropSourceRect(
    left: -panX * scale,
    top: -panY * scale,
    width: viewWidth * scale,
    height: viewHeight * scale,
  );
}

/// 把画布旋转 90°（顺时针），宽高互换。
///
/// 对应 `rotateCanvas()`：canvas 宽高互换后绕中心转 90° 重绘。用像素映射写死，
/// 不做插值：目标像素 `(dx, dy)` 取源像素 `(dy, height - 1 - dx)`。
RgbaImage rotateImage90Clockwise(RgbaImage image) {
  final int srcWidth = image.width;
  final int srcHeight = image.height;
  final Uint8List src = image.data;
  final Uint8List dst = Uint8List(src.length);

  for (int dy = 0; dy < srcWidth; dy++) {
    for (int dx = 0; dx < srcHeight; dx++) {
      final int srcX = dy;
      final int srcY = srcHeight - 1 - dx;
      final int srcIndex = (srcY * srcWidth + srcX) * 4;
      // 目标图宽 = 原图高，所以行主序下标用 srcHeight 做行宽。
      final int dstIndex = (dy * srcHeight + dx) * 4;
      dst[dstIndex] = src[srcIndex];
      dst[dstIndex + 1] = src[srcIndex + 1];
      dst[dstIndex + 2] = src[srcIndex + 2];
      dst[dstIndex + 3] = src[srcIndex + 3];
    }
  }

  // 旋转后宽 = 原高，高 = 原宽。
  return RgbaImage(srcHeight, srcWidth, dst);
}

/// 图片宽高比与画布是否一致（web 版 `updateImage()` 用它决定要不要进裁剪模式，
/// 用的是浮点相等比较，这里保持一致）。
bool imageMatchesCanvasAspect({
  required int imageWidth,
  required int imageHeight,
  required int canvasWidth,
  required int canvasHeight,
}) {
  return imageWidth / imageHeight == canvasWidth / canvasHeight;
}
