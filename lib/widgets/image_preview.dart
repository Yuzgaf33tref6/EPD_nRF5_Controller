import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../image/rgba_image.dart';

/// 把 [RgbaImage] 画到屏幕上。
///
/// 逐像素画 12 万个方块会非常慢，所以这里按「同一行里连续相同的颜色」合并成一个矩形，
/// 抖动后的图只有少数几种调色板颜色，合并后每行通常只有几十个矩形。
class RgbaImagePreview extends StatelessWidget {
  const RgbaImagePreview({super.key, required this.image});

  final RgbaImage image;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: image.width / image.height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).dividerColor),
        ),
        child: CustomPaint(
          painter: _RgbaImagePainter(image),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

class _RgbaImagePainter extends CustomPainter {
  _RgbaImagePainter(this.image);

  final RgbaImage image;

  @override
  void paint(Canvas canvas, Size size) {
    final int width = image.width;
    final int height = image.height;
    final double scaleX = size.width / width;
    final double scaleY = size.height / height;
    final Paint paint = Paint()..style = PaintingStyle.fill;
    final Uint8List data = image.data;

    for (int y = 0; y < height; y++) {
      int x = 0;
      while (x < width) {
        final int i = (y * width + x) * 4;
        final int r = data[i];
        final int g = data[i + 1];
        final int b = data[i + 2];
        int end = x + 1;
        while (end < width) {
          final int j = (y * width + end) * 4;
          if (data[j] != r || data[j + 1] != g || data[j + 2] != b) {
            break;
          }
          end++;
        }
        paint.color = Color.fromARGB(255, r, g, b);
        canvas.drawRect(
          Rect.fromLTWH(
            x * scaleX,
            y * scaleY,
            (end - x) * scaleX,
            scaleY,
          ),
          paint,
        );
        x = end;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _RgbaImagePainter oldDelegate) {
    return !identical(oldDelegate.image, image);
  }
}
