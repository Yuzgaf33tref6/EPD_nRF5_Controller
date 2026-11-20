import 'dart:typed_data';

import 'rgba_image.dart';

/// 纯 Dart 的双线性缩放与裁剪。
///
/// 这里不依赖 `package:image`：导入图片时只需要「按裁剪矩形取一块再缩到画布尺寸」，
/// 双线性足够，而且便于写确定性测试。
///
/// 说明：web 版用的是 canvas `drawImage`（浏览器默认插值），并不是双线性；
/// 所以这里的缩放结果不可能与 web 版逐字节相同，只要求几何和观感一致。

int _clampInt(int value, int min, int max) {
  if (value < min) {
    return min;
  }
  if (value > max) {
    return max;
  }
  return value;
}

/// 在源图 ([sw], [sh]) 的 ([fx], [fy]) 处做双线性采样，把 RGB 写进 [dst] 的 [offset]。
///
/// 调用方保证 ([fx], [fy]) 落在源图范围内（由 [cropScaled] 负责筛选）。
void _sampleBilinear(
  Uint8List src,
  int sw,
  int sh,
  double fx,
  double fy,
  Uint8List dst,
  int offset,
) {
  final double cx = fx.clamp(0, (sw - 1).toDouble()).toDouble();
  final double cy = fy.clamp(0, (sh - 1).toDouble()).toDouble();
  final int x0 = cx.floor();
  final int y0 = cy.floor();
  final int x1 = _clampInt(x0 + 1, 0, sw - 1);
  final int y1 = _clampInt(y0 + 1, 0, sh - 1);
  final double wx = cx - x0;
  final double wy = cy - y0;

  final int i00 = (y0 * sw + x0) * 4;
  final int i10 = (y0 * sw + x1) * 4;
  final int i01 = (y1 * sw + x0) * 4;
  final int i11 = (y1 * sw + x1) * 4;

  for (int c = 0; c < 3; c++) {
    final double top = src[i00 + c] * (1 - wx) + src[i10 + c] * wx;
    final double bottom = src[i01 + c] * (1 - wx) + src[i11 + c] * wx;
    dst[offset + c] = _clampInt((top * (1 - wy) + bottom * wy).round(), 0, 255);
  }
  dst[offset + 3] = 255;
}

/// 双线性缩放到指定尺寸。
RgbaImage resizeBilinear(RgbaImage source, int dstWidth, int dstHeight) {
  if (dstWidth < 1 || dstHeight < 1) {
    throw ArgumentError.value(
      '$dstWidth x $dstHeight',
      'dstWidth/dstHeight',
      '目标尺寸必须为正',
    );
  }
  if (source.width < 1 || source.height < 1) {
    throw ArgumentError('源图尺寸必须为正');
  }
  if (source.width == dstWidth && source.height == dstHeight) {
    return source.clone();
  }

  final int sw = source.width;
  final int sh = source.height;
  final Uint8List src = source.data;
  final Uint8List dst = Uint8List(dstWidth * dstHeight * 4);

  // 用像素中心对齐，缩放时不会整体偏移半个像素。
  final double sx = sw / dstWidth;
  final double sy = sh / dstHeight;

  for (int y = 0; y < dstHeight; y++) {
    final double fy = (y + 0.5) * sy - 0.5;
    for (int x = 0; x < dstWidth; x++) {
      final double fx = (x + 0.5) * sx - 0.5;
      _sampleBilinear(src, sw, sh, fx, fy, dst, (y * dstWidth + x) * 4);
    }
  }

  return RgbaImage(dstWidth, dstHeight, dst);
}

/// 裁剪留空区域的填充色。
///
/// 墨水屏只有黑白红三色，留空只允许填纯白或纯黑，避免抖出灰色噪点。
enum CropFill {
  white(255, 255, 255),
  black(0, 0, 0);

  const CropFill(this.r, this.g, this.b);

  final int r;
  final int g;
  final int b;

  /// 中文标签，直接用于界面。
  String get label => switch (this) {
        CropFill.white => '白',
        CropFill.black => '黑',
      };
}

/// 从 [source] 里取一块矩形（单位：源图像素）再缩放到 [outWidth] x [outHeight]。
///
/// 矩形允许超出源图边界（裁剪页允许把图拖到露出空白的位置）。超出源图的部分
/// **按 [fill] 填纯色**，而不是取边缘像素——否则用户看到的「留白」会被画成
/// 边缘那条色带，跟裁剪框里所见不符。
///
/// 采样点只要落在源图内就正常双线性；落在外面就填 [fill]。为了不让源图边缘
/// 出现一条硬边，这里按采样点是否在源图矩形内判定，不做抗锯齿过渡（墨水屏
/// 本身只有三色，抖动会吃掉这点过渡）。
RgbaImage cropScaled({
  required RgbaImage source,
  required double left,
  required double top,
  required double width,
  required double height,
  required int outWidth,
  required int outHeight,
  CropFill fill = CropFill.white,
}) {
  if (outWidth < 1 || outHeight < 1) {
    throw ArgumentError.value(
      '$outWidth x $outHeight',
      'outWidth/outHeight',
      '输出尺寸必须为正',
    );
  }
  if (width <= 0 || height <= 0) {
    throw ArgumentError.value('$width x $height', 'width/height', '裁剪矩形必须为正');
  }

  final int sw = source.width;
  final int sh = source.height;
  final Uint8List src = source.data;
  final Uint8List dst = Uint8List(outWidth * outHeight * 4);

  // 先把整张图填成填充色，落在源图内的像素再覆盖上去。
  for (int i = 0; i < dst.length; i += 4) {
    dst[i] = fill.r;
    dst[i + 1] = fill.g;
    dst[i + 2] = fill.b;
    dst[i + 3] = 255;
  }

  final double stepX = width / outWidth;
  final double stepY = height / outHeight;

  for (int y = 0; y < outHeight; y++) {
    final double fy = top + (y + 0.5) * stepY - 0.5;
    final bool rowInside = fy >= 0 && fy <= sh - 1;
    for (int x = 0; x < outWidth; x++) {
      final double fx = left + (x + 0.5) * stepX - 0.5;
      if (!rowInside || fx < 0 || fx > sw - 1) {
        // 留在填充色上。
        continue;
      }
      _sampleBilinear(src, sw, sh, fx, fy, dst, (y * outWidth + x) * 4);
    }
  }

  return RgbaImage(outWidth, outHeight, dst);
}

/// 判断裁剪矩形是否完全落在源图内（没有任何留空）。
///
/// 裁剪页用它在「完成」按钮旁提示「有留空，会补白/补黑」。
bool cropRectFitsInside({
  required RgbaImage source,
  required double left,
  required double top,
  required double width,
  required double height,
}) {
  return left >= -0.5 &&
      top >= -0.5 &&
      left + width <= source.width - 0.5 &&
      top + height <= source.height - 0.5;
}
