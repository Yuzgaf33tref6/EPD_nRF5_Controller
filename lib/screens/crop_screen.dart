import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../image/crop_geometry.dart';
import '../image/image_transform.dart';
import '../image/rgba_image.dart';
import '../widgets/section_card.dart';

/// 图片裁剪页。
///
/// 交互与 web 版 `html/js/crop.js` 对齐：拖动平移、双指/滚轮缩放（0.1~5 倍），
/// 裁剪矩形的计算完全复用 [cropSourceRect]（已有 web 版 golden 对拍）。
class CropScreen extends StatefulWidget {
  const CropScreen({
    super.key,
    required this.source,
    required this.canvasWidth,
    required this.canvasHeight,
  });

  /// 待裁剪的原图（源图像素）。
  final RgbaImage source;

  /// 目标画布尺寸，裁剪结果会被缩放到这个尺寸。
  final int canvasWidth;
  final int canvasHeight;

  @override
  State<CropScreen> createState() => _CropScreenState();
}

class _CropScreenState extends State<CropScreen> {
  /// 预览用的小图，避免每帧都拿几百万像素去画。
  static const int _previewMaxEdge = 720;

  ui.Image? _preview;
  RgbaImage? _previewImage;
  double _zoom = 1;
  double _panX = 0;
  double _panY = 0;
  double _zoomAtStart = 1;
  bool _busy = false;
  String? _error;
  Size _viewSize = Size.zero;

  @override
  void initState() {
    super.initState();
    _preparePreview();
  }

  @override
  void dispose() {
    _preview?.dispose();
    super.dispose();
  }

  Future<void> _preparePreview() async {
    try {
      final RgbaImage preview = _downscaleForPreview(widget.source);
      final ui.Image image = await _rgbaToUiImage(preview);
      if (!mounted) {
        image.dispose();
        return;
      }
      setState(() {
        _preview = image;
        _previewImage = preview;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _error = '无法准备预览图：$error');
    }
  }

  /// 把源图缩到预览尺寸（保持宽高比，不放大）。
  RgbaImage _downscaleForPreview(RgbaImage source) {
    final int longest = source.width > source.height
        ? source.width
        : source.height;
    if (longest <= _previewMaxEdge) {
      return source.clone();
    }
    final double ratio = _previewMaxEdge / longest;
    final int width =
        (source.width * ratio).round().clamp(1, _previewMaxEdge).toInt();
    final int height =
        (source.height * ratio).round().clamp(1, _previewMaxEdge).toInt();
    return resizeBilinear(source, width, height);
  }

  Future<ui.Image> _rgbaToUiImage(RgbaImage image) async {
    final ui.ImmutableBuffer buffer = await ui.ImmutableBuffer.fromUint8List(
      image.data,
    );
    final ui.ImageDescriptor descriptor = ui.ImageDescriptor.raw(
      buffer,
      width: image.width,
      height: image.height,
      pixelFormat: ui.PixelFormat.rgba8888,
    );
    try {
      final ui.Codec codec = await descriptor.instantiateCodec();
      try {
        final ui.FrameInfo frame = await codec.getNextFrame();
        return frame.image;
      } finally {
        codec.dispose();
      }
    } finally {
      descriptor.dispose();
      buffer.dispose();
    }
  }

  void _reset() {
    setState(() {
      _zoom = 1;
      _panX = 0;
      _panY = 0;
    });
  }

  void _handleScaleStart(ScaleStartDetails details) {
    _zoomAtStart = _zoom;
  }

  void _handleScaleUpdate(ScaleUpdateDetails details) {
    setState(() {
      _zoom = cropZoomByPinch(_zoomAtStart, details.scale);
      _panX += details.focalPointDelta.dx;
      _panY += details.focalPointDelta.dy;
    });
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is PointerScrollEvent) {
      setState(() {
        _zoom = cropZoomByWheel(_zoom, zoomIn: event.scrollDelta.dy < 0);
      });
    }
  }

  Future<void> _confirm(Size viewSize) async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      final CropSourceRect rect = cropSourceRect(
        imageWidth: widget.source.width.toDouble(),
        viewWidth: viewSize.width,
        viewHeight: viewSize.height,
        zoom: _zoom,
        panX: _panX,
        panY: _panY,
      );
      final RgbaImage cropped = cropScaled(
        source: widget.source,
        left: rect.left,
        top: rect.top,
        width: rect.width,
        height: rect.height,
        outWidth: widget.canvasWidth,
        outHeight: widget.canvasHeight,
      );
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(cropped);
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('裁剪图片'),
        actions: <Widget>[
          IconButton(
            tooltip: '重置',
            onPressed: _reset,
            icon: const Icon(Icons.restart_alt),
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          Expanded(
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                final Size viewSize = _fitCanvasRect(
                  constraints.biggest,
                  widget.canvasWidth,
                  widget.canvasHeight,
                );
                _viewSize = viewSize;
                return Center(
                  child: SizedBox(
                    width: viewSize.width,
                    height: viewSize.height,
                    child: _buildView(viewSize),
                  ),
                );
              },
            ),
          ),
          SectionCard(
            title: '裁剪',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  '拖动平移，双指或滚轮缩放（0.1~5 倍）。'
                  '裁剪结果会缩放到 ${widget.canvasWidth}×${widget.canvasHeight}。',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                Row(
                  children: <Widget>[
                    Text('缩放 ${_zoom.toStringAsFixed(2)}×'),
                    const Spacer(),
                    TextButton(onPressed: _reset, child: const Text('重置')),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _busy
                          ? null
                          : () => _confirm(_viewSize),
                      child: Text(_busy ? '处理中 …' : '完成'),
                    ),
                  ],
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      _error!,
                      style: TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildView(Size viewSize) {
    final ui.Image? preview = _preview;
    if (preview == null) {
      return Center(
        child: _error == null
            ? const CircularProgressIndicator()
            : const SizedBox.shrink(),
      );
    }
    return Listener(
      onPointerSignal: _handlePointerSignal,
      child: GestureDetector(
        onScaleStart: _handleScaleStart,
        onScaleUpdate: _handleScaleUpdate,
        child: ClipRect(
          child: CustomPaint(
            painter: _CropPainter(
              preview: preview,
              previewSize: Size(
                _previewImage!.width.toDouble(),
                _previewImage!.height.toDouble(),
              ),
              sourceSize: Size(
                widget.source.width.toDouble(),
                widget.source.height.toDouble(),
              ),
              zoom: _zoom,
              panX: _panX,
              panY: _panY,
              lineColor: Theme.of(context).colorScheme.primary,
            ),
            size: viewSize,
          ),
        ),
      ),
    );
  }

  /// 在可用区域里按画布宽高比取出最大的矩形。
  Size _fitCanvasRect(Size available, int canvasWidth, int canvasHeight) {
    final double targetAspect = canvasWidth / canvasHeight;
    double width = available.width;
    double height = width / targetAspect;
    if (height > available.height) {
      height = available.height;
      width = height * targetAspect;
    }
    if (width < 1 || height < 1) {
      return const Size(1, 1);
    }
    return Size(width, height);
  }
}

/// 把裁剪框内的源图部分画到视口里，并叠一层取景框。
class _CropPainter extends CustomPainter {
  _CropPainter({
    required this.preview,
    required this.previewSize,
    required this.sourceSize,
    required this.zoom,
    required this.panX,
    required this.panY,
    required this.lineColor,
  });

  final ui.Image preview;
  final Size previewSize;
  final Size sourceSize;
  final double zoom;
  final double panX;
  final double panY;
  final Color lineColor;

  @override
  void paint(Canvas canvas, Size size) {
    final CropSourceRect rect = cropSourceRect(
      imageWidth: sourceSize.width,
      viewWidth: size.width,
      viewHeight: size.height,
      zoom: zoom,
      panX: panX,
      panY: panY,
    );
    // 把源图坐标换算到预览图坐标后，直接整块贴到视口上。
    final double sx = previewSize.width / sourceSize.width;
    final double sy = previewSize.height / sourceSize.height;
    final Rect srcRect = Rect.fromLTWH(
      rect.left * sx,
      rect.top * sy,
      rect.width * sx,
      rect.height * sy,
    );
    final Rect dstRect = Offset.zero & size;

    canvas.save();
    canvas.clipRect(dstRect);
    canvas.drawImageRect(
      preview,
      srcRect,
      dstRect,
      Paint()..filterQuality = FilterQuality.medium,
    );
    canvas.restore();

    final Paint border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = lineColor;
    canvas.drawRect(dstRect.deflate(1), border);

    // 三分线，方便构图。
    final Paint guide = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = lineColor.withValues(alpha: 0.35);
    for (int i = 1; i < 3; i++) {
      final double dx = size.width * i / 3;
      final double dy = size.height * i / 3;
      canvas.drawLine(Offset(dx, 0), Offset(dx, size.height), guide);
      canvas.drawLine(Offset(0, dy), Offset(size.width, dy), guide);
    }
  }

  @override
  bool shouldRepaint(_CropPainter oldDelegate) {
    return oldDelegate.preview != preview ||
        oldDelegate.zoom != zoom ||
        oldDelegate.panX != panX ||
        oldDelegate.panY != panY;
  }
}
