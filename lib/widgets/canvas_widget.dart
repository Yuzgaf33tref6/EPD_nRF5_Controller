import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../models/screen_type.dart';

class CanvasWidget extends StatefulWidget {
  final ui.Image image;
  final int width;
  final int height;
  final EpdColorMode colorMode;
  final DitherAlgorithm ditherAlgorithm;
  final double ditherStrength;
  final double contrast;
  final Color selectedColor;

  const CanvasWidget({
    super.key,
    required this.image,
    required this.width,
    required this.height,
    required this.colorMode,
    required this.ditherAlgorithm,
    required this.ditherStrength,
    required this.contrast,
    required this.selectedColor,
  });

  @override
  State<CanvasWidget> createState() => _CanvasWidgetState();
}

class _CanvasWidgetState extends State<CanvasWidget> {
  final List<Offset> _points = [];
  final List<Color> _pointColors = [];
  bool _isDrawing = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanStart: _startDrawing,
      onPanUpdate: _whileDrawing,
      onPanEnd: _stopDrawing,
      child: Container(
        margin: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey),
          borderRadius: BorderRadius.circular(8),
        ),
        child: CustomPaint(
          size: Size(widget.width.toDouble(), widget.height.toDouble()),
          painter: _CanvasPainter(
            image: widget.image,
            points: _points,
            pointColors: _pointColors,
            width: widget.width,
            height: widget.height,
            selectedColor: widget.selectedColor,
          ),
        ),
      ),
    );
  }

  void _startDrawing(DragStartDetails details) {
    setState(() {
      _isDrawing = true;
      _points.add(details.localPosition);
      _pointColors.add(widget.selectedColor);
    });
  }

  void _whileDrawing(DragUpdateDetails details) {
    if (!_isDrawing) return;
    
    setState(() {
      _points.add(details.localPosition);
      _pointColors.add(widget.selectedColor);
    });
  }

  void _stopDrawing(DragEndDetails details) {
    setState(() {
      _isDrawing = false;
    });
  }
}

class _CanvasPainter extends CustomPainter {
  final ui.Image image;
  final List<Offset> points;
  final List<Color> pointColors;
  final int width;
  final int height;
  final Color selectedColor;

  _CanvasPainter({
    required this.image,
    required this.points,
    required this.pointColors,
    required this.width,
    required this.height,
    required this.selectedColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 绘制背景
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);

    // 绘制原始图片
    if (image.width > 0 && image.height > 0) {
      final src = Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());
      final dst = Rect.fromLTWH(0, 0, size.width, size.height);
      canvas.drawImageRect(image, src, dst, Paint());
    }

    // 绘制用户绘制的点
    for (int i = 0; i < points.length; i++) {
      final pointPaint = Paint()
        ..color = pointColors[i]
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round;
      
      // 绘制点
      canvas.drawCircle(points[i], 2, pointPaint);
      
      // 如果是连续的点，绘制线
      if (i > 0) {
        canvas.drawLine(points[i - 1], points[i], pointPaint);
      }
    }
  }

  @override
  bool shouldRepaint(_CanvasPainter oldDelegate) {
    return oldDelegate.image != image ||
        oldDelegate.points.length != points.length ||
        oldDelegate.selectedColor != selectedColor;
  }
}