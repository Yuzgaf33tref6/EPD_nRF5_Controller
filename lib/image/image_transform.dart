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

/// 从 [source] 里取一块矩形（单位：源图像素）再缩放到 [outWidth] x [outHeight]。
///
/// 矩形允许超出源图边界（超出的部分按边缘像素延展），因为裁剪页允许把图片拖到
/// 露出空白的位置；这里把它当作「超出部分取边缘色」，避免出现黑边。
RgbaImage cropScaled({
  required RgbaImage source,
  required double left,
  required double top,
  required double width,
  required double height,
  required int outWidth,
  required int outHeight,
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

  final double stepX = width / outWidth;
  final double stepY = height / outHeight;

  for (int y = 0; y < outHeight; y++) {
    final double fy = top + (y + 0.5) * stepY - 0.5;
    for (int x = 0; x < outWidth; x++) {
      final double fx = left + (x + 0.5) * stepX - 0.5;
      _sampleBilinear(src, sw, sh, fx, fy, dst, (y * outWidth + x) * 4);
    }
  }

  return RgbaImage(outWidth, outHeight, dst);
}
