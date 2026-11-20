import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../image/crop_geometry.dart';
import '../image/crop_view_geometry.dart';
import '../image/image_transform.dart';
import '../image/rgba_image.dart';
import '../widgets/common.dart';

/// 图片裁剪页。
///
/// 交互：拖动平移、双指/滚轮缩放，取景框就是画布比例 —— 框里看到什么，出图就是什么。
///
/// 几何用的是 [crop_view_geometry] 里的「cover」模型，而不是 web 版的
/// [cropSourceRect]：后者只按图片宽度算比例，竖图铺到横屏画布上会算出一个比视口
/// 高得多的源矩形，画面顶部有图、下方整片空白（就是用户截图里那个现象）。
/// cover 模型下图片永远铺满视口，`zoom = 1` 时刚好铺满，放大只是裁得更狠。
///
/// 竖图进到横屏画布时，App 也会在上一页提示用户「屏幕方向是竖的，建议先转 90°」。
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

  /// 当前工作图。导入图片后如果方向不对，可以在这里旋转 90°，再裁剪。
  late RgbaImage _working = widget.source;

  ui.Image? _preview;

  /// 预览图的尺寸（= 缩略后的工作图尺寸），用来把源图坐标换成预览图坐标。
  Size _previewSize = Size.zero;

  CropViewState _view = const CropViewState();
  double _zoomAtStart = 1;
  bool _busy = false;
  String? _error;
  Size _viewSize = Size.zero;

  /// 图片盖不到视口时（正常情况下不会发生）用的底色，与最终出图一致。
  CropFill _fill = CropFill.white;

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
      final RgbaImage preview = _downscaleForPreview(_working);
      final ui.Image image = await _rgbaToUiImage(preview);
      if (!mounted) {
        image.dispose();
        return;
      }
      final ui.Image? oldPreview = _preview;
      setState(() {
        _preview = image;
        _previewSize = Size(
          _working.width.toDouble(),
          _working.height.toDouble(),
        );
      });
      oldPreview?.dispose();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _error = '无法准备预览图：$error');
    }
  }

  /// 把源图缩到预览尺寸（保持宽高比，不放大）。
  RgbaImage _downscaleForPreview(RgbaImage source) {
    final int longest =
        source.width > source.height ? source.width : source.height;
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
    setState(() => _view = const CropViewState());
  }

  /// 顺时针旋转 90°。旋转会改变宽高比，所以顺便把取景复位，让用户重新构图。
  Future<void> _rotate() async {
    if (_busy) {
      return;
    }
    setState(() {
      _busy = true;
      _working = rotateImage90Clockwise(_working);
      _view = const CropViewState();
    });
    await _preparePreview();
    if (mounted) {
      setState(() => _busy = false);
    }
  }

  CropViewState _clamped(CropViewState next) {
    if (_viewSize.width <= 0 || _viewSize.height <= 0) {
      return next;
    }
    return next.clamped(
      imageWidth: _working.width.toDouble(),
      imageHeight: _working.height.toDouble(),
      viewWidth: _viewSize.width,
      viewHeight: _viewSize.height,
    );
  }

  void _handleScaleStart(ScaleStartDetails details) {
    _zoomAtStart = _view.zoom;
  }

  void _handleScaleUpdate(ScaleUpdateDetails details) {
    setState(() {
      _view = _clamped(
        CropViewState(
          zoom: cropViewZoomByPinch(_zoomAtStart, details.scale),
          panX: _view.panX + details.focalPointDelta.dx,
          panY: _view.panY + details.focalPointDelta.dy,
        ),
      );
    });
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is PointerScrollEvent) {
      setState(() {
        _view = _clamped(
          _view.copyWith(
            zoom: cropViewZoomByWheel(
              _view.zoom,
              zoomIn: event.scrollDelta.dy < 0,
            ),
          ),
        );
      });
    }
  }

  Future<void> _confirm() async {
    if (_busy || _viewSize.width <= 0 || _viewSize.height <= 0) {
      return;
    }
    setState(() => _busy = true);
    try {
      final CropViewRect rect = sourceRectForView(
        imageWidth: _working.width.toDouble(),
        imageHeight: _working.height.toDouble(),
        viewWidth: _viewSize.width,
        viewHeight: _viewSize.height,
        state: _view,
      );
      final RgbaImage cropped = cropScaled(
        source: _working,
        left: rect.left,
        top: rect.top,
        width: rect.width,
        height: rect.height,
        outWidth: widget.canvasWidth,
        outHeight: widget.canvasHeight,
        fill: _fill,
      );
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(cropped);
    } catch (error) {
      if (mounted) {
        setState(() => _error = '裁剪失败：$error');
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool suggestRotate = shouldSuggestRotate(
      imageWidth: _working.width.toDouble(),
      imageHeight: _working.height.toDouble(),
      canvasWidth: widget.canvasWidth,
      canvasHeight: widget.canvasHeight,
    );
    return Scaffold(
      appBar: AppBar(
        title: const Text('裁剪图片'),
        actions: <Widget>[
          IconButton(
            tooltip: '旋转 90°',
            onPressed: _busy ? null : _rotate,
            icon: const Icon(Icons.rotate_90_degrees_cw),
          ),
          IconButton(
            tooltip: '重置',
            onPressed: _busy ? null : _reset,
            icon: const Icon(Icons.restart_alt),
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          Expanded(
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                final CropViewRect view = fitCanvasRect(
                  availableWidth: constraints.biggest.width,
                  availableHeight: constraints.biggest.height,
                  canvasWidth: widget.canvasWidth,
                  canvasHeight: widget.canvasHeight,
                );
                _viewSize = Size(view.width, view.height);
                return Center(
                  child: SizedBox(
                    width: view.width,
                    height: view.height,
                    child: _buildView(Size(view.width, view.height)),
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
                  '拖动平移，双指或滚轮缩放（1~5 倍）。取景框就是画布比例，'
                  '框里看到什么，发到墨水屏上就是什么。',
                  style: theme.textTheme.bodySmall,
                ),
                if (suggestRotate)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(
                      children: <Widget>[
                        Icon(Icons.screen_rotation,
                            size: 18, color: theme.colorScheme.error),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '这张图是竖的，画布是横的 —— 直接裁只会留下中间一条，'
                            '建议先点右上角旋转 90°。',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.error,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 12),
                _buildFillPicker(context),
                const SizedBox(height: 8),
                Row(
                  children: <Widget>[
                    Text('缩放 ${_view.zoom.toStringAsFixed(2)}×'),
                    const Spacer(),
                    TextButton(
                      onPressed: _busy ? null : _reset,
                      child: const Text('重置'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _busy ? null : _confirm,
                      child: Text(_busy ? '处理中 …' : '完成'),
                    ),
                  ],
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      _error!,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 填色选择器。一般情况下图片铺满视口用不到，留着兜底与演示。
  Widget _buildFillPicker(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Row(
      children: <Widget>[
        Text('底色', style: theme.textTheme.bodyMedium),
        const SizedBox(width: 12),
        SegmentedButton<CropFill>(
          segments: const <ButtonSegment<CropFill>>[
            ButtonSegment<CropFill>(value: CropFill.white, label: Text('白')),
            ButtonSegment<CropFill>(value: CropFill.black, label: Text('黑')),
          ],
          selected: <CropFill>{_fill},
          showSelectedIcon: false,
          onSelectionChanged: _busy
              ? null
              : (Set<CropFill> selection) {
                  setState(() => _fill = selection.first);
                },
        ),
      ],
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
              previewSize: _previewSize,
              sourceSize: Size(
                _working.width.toDouble(),
                _working.height.toDouble(),
              ),
              state: _view,
              fillColor: _fill == CropFill.white
                  ? const Color(0xFFFFFFFF)
                  : const Color(0xFF000000),
              lineColor: Theme.of(context).colorScheme.primary,
            ),
            size: viewSize,
          ),
        ),
      ),
    );
  }
}

/// 把图片按 [CropViewState] 画到视口里，并叠一层取景框。
class _CropPainter extends CustomPainter {
  _CropPainter({
    required this.preview,
    required this.previewSize,
    required this.sourceSize,
    required this.state,
    required this.fillColor,
    required this.lineColor,
  });

  final ui.Image preview;

  /// 预览图的像素尺寸。
  final Size previewSize;

  /// 工作图的像素尺寸（源图）。
  final Size sourceSize;
  final CropViewState state;
  final Color fillColor;
  final Color lineColor;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect dstRect = Offset.zero & size;
    canvas.save();
    canvas.clipRect(dstRect);

    // 图片在视口里的位置（cover 模型下 ≥ 视口，永远不会露出空白）。
    final CropViewRect display = imageDisplayRect(
      imageWidth: sourceSize.width,
      imageHeight: sourceSize.height,
      viewWidth: size.width,
      viewHeight: size.height,
      state: state,
    );
    canvas.drawRect(dstRect, Paint()..color = fillColor);
    canvas.drawImageRect(
      preview,
      Rect.fromLTWH(0, 0, previewSize.width, previewSize.height),
      Rect.fromLTWH(
        display.left,
        display.top,
        display.width,
        display.height,
      ),
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
        oldDelegate.previewSize != previewSize ||
        oldDelegate.sourceSize != sourceSize ||
        oldDelegate.state.zoom != state.zoom ||
        oldDelegate.state.panX != state.panX ||
        oldDelegate.state.panY != state.panY ||
        oldDelegate.fillColor != fillColor ||
        oldDelegate.lineColor != lineColor;
  }
}
