import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import 'rgba_image.dart';

/// 把一段文字光栅化成 [RgbaImage]（透明底 + 指定颜色）。
///
/// 纯 Dart 画不了字，必须借 Flutter 的排版与光栅化：
/// TextPainter 排版 → PictureRecorder 录制 → `picture.toImage` → 取 rawRgba。
Future<RgbaImage> renderText({
  required String text,
  required double fontSize,
  required int r,
  required int g,
  required int b,
  bool bold = false,
  double maxWidth = 4096,
}) async {
  final TextPainter painter = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(
        fontSize: fontSize,
        height: 1.2,
        color: ui.Color.fromARGB(255, r, g, b),
        fontWeight: bold ? ui.FontWeight.bold : ui.FontWeight.normal,
      ),
    ),
    textDirection: ui.TextDirection.ltr,
  )..layout(maxWidth: maxWidth);

  final int width = math.max(1, painter.width.ceil());
  final int height = math.max(1, painter.height.ceil());

  final ui.PictureRecorder recorder = ui.PictureRecorder();
  final ui.Canvas canvas = ui.Canvas(
    recorder,
    ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
  );
  painter.paint(canvas, ui.Offset.zero);
  painter.dispose();

  final ui.Picture picture = recorder.endRecording();
  final ui.Image image = await picture.toImage(width, height);
  final ByteData? bytes = await image.toByteData(
    format: ui.ImageByteFormat.rawRgba,
  );
  picture.dispose();
  image.dispose();

  if (bytes == null) {
    throw StateError('文字光栅化失败：拿不到像素数据');
  }
  return RgbaImage(
    width,
    height,
    Uint8List.fromList(bytes.buffer.asUint8List()),
  );
}

/// 把 [overlay] 按左上角坐标贴到 [base] 上（就地修改 [base]）。
///
/// 墨水屏只有纯色，所以这里不做半透明混色：alpha 达到阈值的像素直接取原色，
/// 边缘抗锯齿产生的浅色像素视为背景丢弃。越界部分自动裁掉。
void compositeOver(
  RgbaImage base,
  RgbaImage overlay, {
  required int offsetX,
  required int offsetY,
  int alphaThreshold = 128,
}) {
  for (int y = 0; y < overlay.height; y++) {
    final int ty = offsetY + y;
    if (ty < 0 || ty >= base.height) {
      continue;
    }
    for (int x = 0; x < overlay.width; x++) {
      final int tx = offsetX + x;
      if (tx < 0 || tx >= base.width) {
        continue;
      }
      final int si = (y * overlay.width + x) * 4;
      if (overlay.data[si + 3] < alphaThreshold) {
        continue;
      }
      final int di = (ty * base.width + tx) * 4;
      base.data[di] = overlay.data[si];
      base.data[di + 1] = overlay.data[si + 1];
      base.data[di + 2] = overlay.data[si + 2];
      base.data[di + 3] = 255;
    }
  }
}
