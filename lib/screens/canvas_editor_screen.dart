import 'package:flutter/material.dart';

import '../image/canvas_editing.dart';
import '../image/epd_color.dart';
import '../image/rgba_image.dart';
import '../image/text_stamp.dart';
import '../state/app_state.dart';
import '../widgets/image_preview.dart';
import '../widgets/section_card.dart';

/// 画布编辑页：手绘、橡皮、撤销/重做、填充、改画笔颜色与粗细。
///
/// 双缓冲做法：底图（已经落笔的内容）和"正在画的那一笔"分两层画。
/// - 底图只在一次落笔结束时重绘一次；
/// - 手指移动过程中只重绘一个轻量 overlay（一条路径），不重新遍历 12 万像素。
/// 这样手指跟手，不会拖影也不会卡。
class CanvasEditorScreen extends StatefulWidget {
  const CanvasEditorScreen({super.key});

  @override
  State<CanvasEditorScreen> createState() => _CanvasEditorScreenState();
}

class _CanvasEditorScreenState extends State<CanvasEditorScreen> {
  bool _initialized = false;
  late RgbaImage _working;
  int _baseVersion = 0;

  bool _erasing = false;
  int _colorIndex = 0;
  double _radius = 4;

  /// 正在定位、还没落盘的文字块。
  _TextPending? _pendingText;
  Offset _lastLocalPosition = Offset.zero;

  /// 正在画的一笔（图片坐标系）。
  final List<Offset> _strokePoints = <Offset>[];
  final ValueNotifier<int> _strokeTick = ValueNotifier<int>(0);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) {
      return;
    }
    final AppState state = AppStateScope.of(context);
    _working = state.sourceImage.clone();
    _initialized = true;
    // 直接在 didChangeDependencies 里 notifyListeners 会撞上「构建期间 markNeedsBuild」，
    // 所以把历史初始化推到第一帧之后。
    WidgetsBinding.instance.addPostFrameCallback((Duration _) {
      if (!mounted) {
        return;
      }
      AppStateScope.of(context).beginEditing();
    });
  }

  @override
  void dispose() {
    _strokeTick.dispose();
    super.dispose();
  }

  BrushColor get _brushColor => kBrushColors[_colorIndex];

  void _beginStroke(Offset imagePoint) {
    _strokePoints
      ..clear()
      ..add(imagePoint);
    _strokeTick.value += 1;
  }

  void _extendStroke(Offset imagePoint) {
    if (_strokePoints.isEmpty) {
      _beginStroke(imagePoint);
      return;
    }
    _strokePoints.add(imagePoint);
    _strokeTick.value += 1;
  }

  void _endStroke() {
    if (_strokePoints.isEmpty) {
      return;
    }
    if (_strokePoints.length == 1) {
      final Offset p = _strokePoints.first;
      drawDot(
        _working,
        x: p.dx,
        y: p.dy,
        radius: _radius,
        r: _erasing ? 255 : _brushColor.r,
        g: _erasing ? 255 : _brushColor.g,
        b: _erasing ? 255 : _brushColor.b,
      );
    } else {
      for (int i = 1; i < _strokePoints.length; i++) {
        final Offset a = _strokePoints[i - 1];
        final Offset b = _strokePoints[i];
        drawStroke(
          _working,
          x0: a.dx,
          y0: a.dy,
          x1: b.dx,
          y1: b.dy,
          radius: _radius,
          r: _erasing ? 255 : _brushColor.r,
          g: _erasing ? 255 : _brushColor.g,
          b: _erasing ? 255 : _brushColor.b,
        );
      }
    }
    _strokePoints.clear();
    setState(() => _baseVersion += 1);
    final AppState state = AppStateScope.of(context);
    state.commitEdit(_working.clone());
  }

  void _syncFromState() {
    final AppState state = AppStateScope.of(context);
    setState(() {
      _working = state.sourceImage.clone();
      _baseVersion += 1;
      _strokePoints.clear();
    });
    _strokeTick.value += 1;
  }

  void _fillWhite() {
    fillImage(_working, rgbPalette[1]);
    setState(() => _baseVersion += 1);
    AppStateScope.of(context).commitEdit(_working.clone());
  }

  Future<void> _showTextDialog() async {
    final TextEditingController controller = TextEditingController();
    double fontSize = 28;
    int colorIndex = _colorIndex;
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (
            BuildContext context,
            void Function(void Function()) setDialogState,
          ) {
            return AlertDialog(
              title: const Text('添加文字'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    TextField(
                      controller: controller,
                      autofocus: true,
                      maxLines: 3,
                      minLines: 1,
                      decoration: const InputDecoration(
                        labelText: '文字内容',
                        hintText: '输入要写进画布的字',
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: <Widget>[
                        const SizedBox(width: 48, child: Text('字号')),
                        Expanded(
                          child: Slider(
                            value: fontSize,
                            min: 12,
                            max: 96,
                            divisions: 21,
                            label: fontSize.toStringAsFixed(0),
                            onChanged: (double value) => setDialogState(
                              () => fontSize = value,
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 32,
                          child: Text(
                            fontSize.toStringAsFixed(0),
                            textAlign: TextAlign.end,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: <Widget>[
                        for (int i = 0; i < kBrushColors.length; i++)
                          _ColorChip(
                            color: kBrushColors[i],
                            selected: i == colorIndex,
                            onPressed: () =>
                                setDialogState(() => colorIndex = i),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () {
                    if (controller.text.trim().isEmpty) {
                      return;
                    }
                    Navigator.of(dialogContext).pop(true);
                  },
                  child: const Text('确定'),
                ),
              ],
            );
          },
        );
      },
    );

    final String text = controller.text.trim();
    controller.dispose();
    if (confirmed != true || text.isEmpty) {
      return;
    }
    setState(() {
      _pendingText = _TextPending(
        text: text,
        fontSize: fontSize,
        colorIndex: colorIndex,
        position: Offset(
          (_working.width - text.length * fontSize * 0.5) / 2,
          (_working.height - fontSize * 1.2) / 2,
        ),
      );
    });
  }

  Future<void> _placeText() async {
    final _TextPending? pending = _pendingText;
    if (pending == null) {
      return;
    }
    final BrushColor color = kBrushColors[pending.colorIndex];
    final RgbaImage stamp = await renderText(
      text: pending.text,
      fontSize: pending.fontSize,
      r: color.r,
      g: color.g,
      b: color.b,
      maxWidth: _working.width.toDouble(),
    );
    if (!mounted) {
      return;
    }
    compositeOver(
      _working,
      stamp,
      offsetX: pending.position.dx.round(),
      offsetY: pending.position.dy.round(),
    );
    setState(() {
      _pendingText = null;
      _baseVersion += 1;
    });
    AppStateScope.of(context).commitEdit(_working.clone());
  }

  @override
  Widget build(BuildContext context) {
    final AppState state = AppStateScope.of(context);
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('画布编辑'),
        actions: <Widget>[
          if (_pendingText != null) ...<Widget>[
            TextButton(
              onPressed: () => setState(() => _pendingText = null),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: _placeText,
              child: const Text('放置'),
            ),
          ] else ...<Widget>[
            IconButton(
              tooltip: '撤销',
              icon: const Icon(Icons.undo),
              onPressed: state.canUndo
                  ? () {
                      state.undoEdit();
                      _syncFromState();
                    }
                  : null,
            ),
            IconButton(
              tooltip: '重做',
              icon: const Icon(Icons.redo),
              onPressed: state.canRedo
                  ? () {
                      state.redoEdit();
                      _syncFromState();
                    }
                  : null,
            ),
          ],
        ],
      ),
      body: Column(
        children: <Widget>[
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Center(
                child: LayoutBuilder(
                  builder: (BuildContext context, BoxConstraints constraints) {
                    final int width = _working.width;
                    final int height = _working.height;
                    final double scale = constraints.maxWidth / width;
                    final double displayWidth = constraints.maxWidth;
                    final double displayHeight = height * scale;
                    return SizedBox(
                      width: displayWidth,
                      height: displayHeight,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onPanStart: (DragStartDetails details) {
                          if (_pendingText != null) {
                            _lastLocalPosition = details.localPosition;
                            return;
                          }
                          _beginStroke(_toImage(details.localPosition, scale));
                        },
                        onPanUpdate: (DragUpdateDetails details) {
                          final _TextPending? pending = _pendingText;
                          if (pending != null) {
                            final Offset delta =
                                (details.localPosition - _lastLocalPosition) /
                                    scale;
                            _lastLocalPosition = details.localPosition;
                            setState(() => pending.position += delta);
                            return;
                          }
                          _extendStroke(_toImage(details.localPosition, scale));
                        },
                        onPanEnd: (DragEndDetails details) {
                          if (_pendingText != null) {
                            return;
                          }
                          _endStroke();
                        },
                        onPanCancel: () {
                          if (_pendingText != null) {
                            return;
                          }
                          _endStroke();
                        },
                        child: RepaintBoundary(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              border: Border.all(color: theme.dividerColor),
                            ),
                            child: Stack(
                              fit: StackFit.expand,
                              children: <Widget>[
                                CustomPaint(
                                  painter: RgbaImagePainter(
                                    _working,
                                    version: _baseVersion,
                                  ),
                                ),
                                CustomPaint(
                                  painter: _StrokePainter(
                                    points: _strokePoints,
                                    radius: _radius,
                                    scale: scale,
                                    erase: _erasing,
                                    brushColor: _brushColor,
                                    repaint: _strokeTick,
                                  ),
                                ),
                                if (_pendingText != null)
                                  CustomPaint(
                                    painter: _TextGhostPainter(
                                      pending: _pendingText!,
                                      scale: scale,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
          SectionCard(
            title: '工具',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: <Widget>[
                    _ToolButton(
                      label: '画笔',
                      icon: Icons.edit_outlined,
                      selected: !_erasing,
                      onPressed: () => setState(() => _erasing = false),
                    ),
                    _ToolButton(
                      label: '橡皮',
                      icon: Icons.auto_fix_normal,
                      selected: _erasing,
                      onPressed: () => setState(() => _erasing = true),
                    ),
                    OutlinedButton.icon(
                      onPressed: _fillWhite,
                      icon: const Icon(Icons.format_color_reset),
                      label: const Text('填白'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _pendingText == null ? _showTextDialog : null,
                      icon: const Icon(Icons.text_fields),
                      label: const Text('文字'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: <Widget>[
                    SizedBox(
                      width: 48,
                      child: Text('粗细', style: theme.textTheme.bodySmall),
                    ),
                    Expanded(
                      child: Slider(
                        value: _radius,
                        min: 1,
                        max: 24,
                        divisions: 23,
                        label: _radius.toStringAsFixed(0),
                        onChanged: (double value) =>
                            setState(() => _radius = value),
                      ),
                    ),
                    SizedBox(
                      width: 32,
                      child: Text(
                        _radius.toStringAsFixed(0),
                        textAlign: TextAlign.end,
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    for (int i = 0; i < kBrushColors.length; i++)
                      _ColorChip(
                        color: kBrushColors[i],
                        selected: i == _colorIndex,
                        onPressed: () => setState(() {
                          _colorIndex = i;
                          _erasing = false;
                        }),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '当前画布 ${_working.width}×${_working.height}；'
                  '画完回到上一页，抖动与传图用的就是这张图。',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Offset _toImage(Offset localPosition, double scale) {
    return Offset(localPosition.dx / scale, localPosition.dy / scale);
  }
}

/// 正在画的那一笔。轻量，只画一条路径。
class _StrokePainter extends CustomPainter {
  _StrokePainter({
    required this.points,
    required this.radius,
    required this.scale,
    required this.erase,
    required this.brushColor,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final List<Offset> points;
  final double radius;
  final double scale;
  final bool erase;
  final BrushColor brushColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) {
      return;
    }
    final Paint paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = radius * 2 * scale
      ..color = erase
          ? Colors.white
          : Color.fromARGB(255, brushColor.r, brushColor.g, brushColor.b);

    if (points.length == 1) {
      final Offset p = points.first;
      canvas.drawCircle(
        Offset(p.dx * scale, p.dy * scale),
        radius * scale,
        Paint()
          ..style = PaintingStyle.fill
          ..color = paint.color,
      );
      return;
    }

    final Path path = Path()
      ..moveTo(points.first.dx * scale, points.first.dy * scale);
    for (int i = 1; i < points.length; i++) {
      path.lineTo(points[i].dx * scale, points[i].dy * scale);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _StrokePainter oldDelegate) {
    return true;
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    if (selected) {
      return FilledButton.icon(
        onPressed: onPressed,
        icon: Icon(icon),
        label: Text(label),
      );
    }
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon),
      label: Text(label),
    );
  }
}

class _ColorChip extends StatelessWidget {
  const _ColorChip({
    required this.color,
    required this.selected,
    required this.onPressed,
  });

  final BrushColor color;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: Color.fromARGB(255, color.r, color.g, color.b),
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? theme.colorScheme.primary : theme.dividerColor,
            width: selected ? 3 : 1,
          ),
        ),
      ),
    );
  }
}

/// 还没有落盘的文字块（可以拖动定位）。
class _TextPending {
  _TextPending({
    required this.text,
    required this.fontSize,
    required this.colorIndex,
    required this.position,
  });

  final String text;
  final double fontSize;
  final int colorIndex;

  /// 左上角坐标（图片坐标系），拖动时会变。
  Offset position;
}

/// 定位阶段画的文字预览（按屏幕比例缩放）。
class _TextGhostPainter extends CustomPainter {
  _TextGhostPainter({required this.pending, required this.scale});

  final _TextPending pending;
  final double scale;

  @override
  void paint(Canvas canvas, Size size) {
    final BrushColor color = kBrushColors[pending.colorIndex];
    final TextPainter painter = TextPainter(
      text: TextSpan(
        text: pending.text,
        style: TextStyle(
          fontSize: pending.fontSize * scale,
          height: 1.2,
          color: Color.fromARGB(255, color.r, color.g, color.b),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: size.width);
    painter.paint(
      canvas,
      Offset(pending.position.dx * scale, pending.position.dy * scale),
    );
    painter.dispose();
  }

  @override
  bool shouldRepaint(covariant _TextGhostPainter oldDelegate) => true;
}
