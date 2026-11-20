/// 裁剪页的视口几何 —— 「取景框」在屏幕上的位置，以及处理竖图。
///
/// 背景：老版用的是 web 的 [cropSourceRect]，它只按**图片宽度**算比例
/// （`scale = 图片宽 / 视口宽 / zoom`，见 `html/js/crop.js:94-100`）。
/// 浏览器里那套"图片宽比画布宽"的前提，在竖图（例如手机拍的照片，宽 600 高 1200）
/// 上会算出一个比视口高得多的源矩形：画面顶部先显示源图、下方一大片从没被覆盖的
/// 区域，出来就是截图里那种「上半有图、下半整片空白」。
///
/// 于是这里改成符合直觉的取景框模型：
/// * **cover**：图片铺满整个视口，多出来的部分被裁掉，视口里永远看不到空白；
/// * `zoom = 1` 时刚好铺满，放大只会裁得更狠；
/// * 平移量是屏幕像素，整体限制在「图片刚好铺满」的范围内（不会再拖出空白）。
///
/// 这样裁剪框里看到什么，出图就是什么（[cropScaled] 只按这个源矩形取像素）。
library;

import 'dart:math' as math;

/// 缩放下限（沿用 web 版 `Math.max(0.1, ...)`）。
const double kCropViewMinZoom = 1.0;

/// 缩放上限（沿用 web 版 `Math.min(5, ...)`）。
const double kCropViewMaxZoom = 5.0;

/// 滚轮每格的缩放倍率（沿用 web 版 0.9 / 1.1）。
const double kCropViewWheelZoomIn = 1.1;
const double kCropViewWheelZoomOut = 0.9;

double _clampZoom(double zoom) =>
    zoom.clamp(kCropViewMinZoom, kCropViewMaxZoom).toDouble();

/// 滚轮缩放。[zoomIn] 为真表示放大。
double cropViewZoomByWheel(double zoom, {required bool zoomIn}) =>
    _clampZoom(zoom * (zoomIn ? kCropViewWheelZoomIn : kCropViewWheelZoomOut));

/// 双指捏合缩放。[factor] = 当前两指距离 / 上一次两指距离。
double cropViewZoomByPinch(double zoom, double factor) =>
    _clampZoom(zoom * factor);

/// 画布（取景框）在屏幕上的矩形。
class CropViewRect {
  const CropViewRect({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  final double left;
  final double top;
  final double width;
  final double height;

  double get right => left + width;
  double get bottom => top + height;

  @override
  String toString() =>
      'CropViewRect($left, $top, ${width}x$height)';
}

/// 在可用区域里按画布的宽高比取出最大的居中矩形。
CropViewRect fitCanvasRect({
  required double availableWidth,
  required double availableHeight,
  required int canvasWidth,
  required int canvasHeight,
}) {
  if (availableWidth <= 0 ||
      availableHeight <= 0 ||
      canvasWidth <= 0 ||
      canvasHeight <= 0) {
    return const CropViewRect(left: 0, top: 0, width: 1, height: 1);
  }
  final double targetAspect = canvasWidth / canvasHeight;
  double width = availableWidth;
  double height = width / targetAspect;
  if (height > availableHeight) {
    height = availableHeight;
    width = height * targetAspect;
  }
  if (width < 1 || height < 1) {
    return const CropViewRect(left: 0, top: 0, width: 1, height: 1);
  }
  return CropViewRect(
    left: (availableWidth - width) / 2,
    top: (availableHeight - height) / 2,
    width: width,
    height: height,
  );
}

/// 裁剪页当前的缩放 / 平移状态。
class CropViewState {
  const CropViewState({this.zoom = 1, this.panX = 0, this.panY = 0});

  /// 缩放倍率，1 = 图片刚好铺满视口。
  final double zoom;

  /// 平移量（屏幕像素，右/下为正）。
  final double panX;
  final double panY;

  CropViewState copyWith({double? zoom, double? panX, double? panY}) {
    return CropViewState(
      zoom: zoom ?? this.zoom,
      panX: panX ?? this.panX,
      panY: panY ?? this.panY,
    );
  }

  CropViewState clamped({
    required double imageWidth,
    required double imageHeight,
    required double viewWidth,
    required double viewHeight,
  }) {
    final double z = _clampZoom(zoom);
    final double cover =
        math.max(viewWidth / imageWidth, viewHeight / imageHeight) * z;
    final double displayWidth = imageWidth * cover;
    final double displayHeight = imageHeight * cover;
    final double maxPanX = math.max(0, (displayWidth - viewWidth) / 2);
    final double maxPanY = math.max(0, (displayHeight - viewHeight) / 2);
    return CropViewState(
      zoom: z,
      panX: panX.clamp(-maxPanX, maxPanX).toDouble(),
      panY: panY.clamp(-maxPanY, maxPanY).toDouble(),
    );
  }

  @override
  String toString() => 'CropViewState(zoom: $zoom, pan: $panX, $panY)';
}

/// 图片在屏幕上的绘制矩形：以视口中心为基准，按 cover 比例铺开再加上平移。
CropViewRect imageDisplayRect({
  required double imageWidth,
  required double imageHeight,
  required double viewWidth,
  required double viewHeight,
  required CropViewState state,
}) {
  final double cover =
      math.max(viewWidth / imageWidth, viewHeight / imageHeight) * state.zoom;
  final double displayWidth = imageWidth * cover;
  final double displayHeight = imageHeight * cover;
  return CropViewRect(
    left: (viewWidth - displayWidth) / 2 + state.panX,
    top: (viewHeight - displayHeight) / 2 + state.panY,
    width: displayWidth,
    height: displayHeight,
  );
}

/// 把屏幕矩形 [rect]（相对视口左上角）换算成源图像素矩形。
CropViewRect sourceRectForView({
  required double imageWidth,
  required double imageHeight,
  required double viewWidth,
  required double viewHeight,
  required CropViewState state,
}) {
  final CropViewRect display = imageDisplayRect(
    imageWidth: imageWidth,
    imageHeight: imageHeight,
    viewWidth: viewWidth,
    viewHeight: viewHeight,
    state: state,
  );
  final double scale = imageWidth / display.width;
  return CropViewRect(
    left: (0 - display.left) * scale,
    top: (0 - display.top) * scale,
    width: viewWidth * scale,
    height: viewHeight * scale,
  );
}

/// 裁剪页预览贴图的尺寸信息。
///
/// 存在的意义：裁剪页同时持有两份像素 —— 工作图（原分辨率，用来真正裁剪）
/// 和预览贴图（缩小到 [maxEdge]，只用来画到屏幕上）。**两者尺寸不同**，
/// 画图和裁剪各自要用自己那份。曾经把工作图尺寸当成预览贴图尺寸去
/// `drawImageRect`，画面就缩到左上角、只剩三分之一大。
class CropPreviewSize {
  const CropPreviewSize({
    required this.width,
    required this.height,
    required this.scale,
  });

  /// 预览贴图的像素宽高。
  final int width;
  final int height;

  /// 预览 / 原图 的比例（≤ 1）。
  final double scale;

  @override
  String toString() => 'CropPreviewSize(${width}x$height, scale: $scale)';
}

/// 算出预览贴图应该缩到多大：长边不超过 [maxEdge]，不放大，非法输入退回 1×1。
CropPreviewSize previewSizeForSource({
  required int width,
  required int height,
  required int maxEdge,
}) {
  if (width <= 0 || height <= 0 || maxEdge <= 0) {
    return const CropPreviewSize(width: 1, height: 1, scale: 1);
  }
  final int longest = math.max(width, height);
  if (longest <= maxEdge) {
    return CropPreviewSize(width: width, height: height, scale: 1);
  }
  final double ratio = maxEdge / longest;
  final int previewWidth =
      math.max(1, (width * ratio).round().clamp(1, maxEdge).toInt());
  final int previewHeight =
      math.max(1, (height * ratio).round().clamp(1, maxEdge).toInt());
  return CropPreviewSize(
    width: previewWidth,
    height: previewHeight,
    scale: previewWidth / width,
  );
}

/// 裁完之后要不要让用户「转一下」。
///
/// 竖图（高大于宽）铺到横屏画布上，取景框只能取到中间窄窄一条，几乎必然要把
/// 大片内容丢掉——而这正是截图里出现「下半屏空白」的根源。此时提示用户旋转。
bool shouldSuggestRotate({
  required double imageWidth,
  required double imageHeight,
  required int canvasWidth,
  required int canvasHeight,
}) {
  if (imageWidth <= 0 || imageHeight <= 0) {
    return false;
  }
  final bool imagePortrait = imageHeight > imageWidth;
  final bool canvasLandscape = canvasWidth > canvasHeight;
  return imagePortrait && canvasLandscape;
}
