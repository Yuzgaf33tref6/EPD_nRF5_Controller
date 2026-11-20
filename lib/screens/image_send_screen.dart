import 'dart:async';

import 'package:flutter/material.dart';

import '../image/dither.dart';
import '../image/rgba_image.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';
import '../widgets/image_preview.dart';
import 'canvas_editor_screen.dart';
import 'crop_screen.dart';

/// 图像发送页（二级）：画布预览 + 抖动参数 + 导入/编辑 + 发送。
///
/// 这里会跑抖动与位打包（400×300 图约百毫秒），所以做成独立页面按需进入，
/// 不放在底部导航的一级页里。
class ImageSendScreen extends StatefulWidget {
  const ImageSendScreen({super.key});

  @override
  State<ImageSendScreen> createState() => _ImageSendScreenState();
}

class _ImageSendScreenState extends State<ImageSendScreen> {
  /// 拖动滑块时先用局部值跟手，松开（或停顿 160ms）才真正提交，避免每帧整图重算。
  double? _pendingStrength;
  double? _pendingContrast;
  Timer? _strengthDebounce;
  Timer? _contrastDebounce;

  /// 预览显示原图还是抖动后的效果。
  bool _showDither = true;

  @override
  void dispose() {
    _strengthDebounce?.cancel();
    _contrastDebounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppState state = AppStateScope.of(context);
    final ThemeData theme = Theme.of(context);
    final RgbaImage preview =
        _showDither ? state.previewImage : state.sourceImage;
    return Scaffold(
      appBar: AppBar(
        title: const Text('图像发送'),
        actions: <Widget>[
          IconButton(
            tooltip: '画布编辑',
            icon: const Icon(Icons.brush_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const CanvasEditorScreen(),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
              children: <Widget>[
                SectionCard(
                  title: _showDither ? '预览（抖动后）' : '预览（原图）',
                  icon: Icons.image_outlined,
                  trailing: SegmentedButton<bool>(
                    showSelectedIcon: false,
                    style: const ButtonStyle(
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    segments: const <ButtonSegment<bool>>[
                      ButtonSegment<bool>(value: true, label: Text('抖动')),
                      ButtonSegment<bool>(value: false, label: Text('原图')),
                    ],
                    selected: <bool>{_showDither},
                    onSelectionChanged: (Set<bool> value) {
                      setState(() => _showDither = value.first);
                    },
                  ),
                  child: Column(
                    children: <Widget>[
                      RepaintBoundary(
                        child: RgbaImagePreview(
                          image: preview,
                          maxWidth: 340,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${state.driver.label} · ${state.colorMode.jsName} · '
                        '${preview.width}×${preview.height}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (!state.aspectMatchesCanvas)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            '当前图像比例与画布不符，建议导入图片后裁剪或旋转。',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.error,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                SectionCard(
                  title: '抖动',
                  icon: Icons.grain,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      DropdownButton<DitherAlgorithm>(
                        isExpanded: true,
                        value: state.algorithm,
                        onChanged: (DitherAlgorithm? value) {
                          if (value != null) {
                            state.setAlgorithm(value);
                          }
                        },
                        items: <DropdownMenuItem<DitherAlgorithm>>[
                          for (final DitherAlgorithm algorithm
                              in DitherAlgorithm.values)
                            DropdownMenuItem<DitherAlgorithm>(
                              value: algorithm,
                              child: Text(_algorithmLabel(algorithm)),
                            ),
                        ],
                      ),
                      _SliderRow(
                        label: '强度',
                        value: _pendingStrength ?? state.strength,
                        min: 0,
                        max: 5,
                        divisions: 50,
                        display: (_pendingStrength ?? state.strength)
                            .toStringAsFixed(1),
                        onChanged: (double value) {
                          setState(() => _pendingStrength = value);
                          _strengthDebounce?.cancel();
                          _strengthDebounce = Timer(
                            const Duration(milliseconds: 160),
                            () => _commitStrength(value),
                          );
                        },
                        onChangeEnd: _commitStrength,
                      ),
                      _SliderRow(
                        label: '对比度',
                        value: _pendingContrast ?? state.contrast,
                        min: 0.5,
                        max: 2,
                        divisions: 15,
                        display: (_pendingContrast ?? state.contrast)
                            .toStringAsFixed(1),
                        onChanged: (double value) {
                          setState(() => _pendingContrast = value);
                          _contrastDebounce?.cancel();
                          _contrastDebounce = Timer(
                            const Duration(milliseconds: 160),
                            () => _commitContrast(value),
                          );
                        },
                        onChangeEnd: _commitContrast,
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: <Widget>[
                          OutlinedButton.icon(
                            onPressed: () => _importImage(state),
                            icon: const Icon(Icons.add_photo_alternate_outlined,
                                size: 18),
                            label: const Text('导入图片'),
                          ),
                          OutlinedButton.icon(
                            onPressed: () => state.rotateSource(),
                            icon: const Icon(Icons.rotate_90_degrees_cw,
                                size: 18),
                            label: const Text('旋转画布'),
                          ),
                          OutlinedButton.icon(
                            onPressed: () => state.resetSource(),
                            icon: const Icon(Icons.restart_alt, size: 18),
                            label: const Text('重置示例图'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                SectionCard(
                  title: '传图',
                  icon: Icons.send_outlined,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Text(
                        state.transferSummary,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'MTU ${state.mtu} · 每块 ${state.writeChunkBytes} 字节 · '
                        '${state.speed.label}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      for (final String warning in state.warnings)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            warning,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.error,
                            ),
                          ),
                        ),
                      const SizedBox(height: 10),
                      FilledButton.icon(
                        onPressed: state.isConnected
                            ? () => state.sendPreview()
                            : null,
                        icon: const Icon(Icons.send, size: 18),
                        label: Text(state.isConnected
                            ? '发送到设备'
                            : '未连接设备，无法发送'),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '发送过程会逐条等待设备确认；整屏刷新需要 2~10 秒。',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          DeviceStatusBar(state: state),
        ],
      ),
    );
  }

  void _commitStrength(double value) {
    _strengthDebounce?.cancel();
    final AppState state = AppStateScope.of(context);
    state.setStrength(value);
    if (mounted) {
      setState(() => _pendingStrength = null);
    }
  }

  void _commitContrast(double value) {
    _contrastDebounce?.cancel();
    final AppState state = AppStateScope.of(context);
    state.setContrast(value);
    if (mounted) {
      setState(() => _pendingContrast = null);
    }
  }

  Future<void> _importImage(AppState state) async {
    final RgbaImage? picked = await state.pickImageFromGallery();
    if (picked == null || !mounted) {
      return;
    }
    final RgbaImage? cropped = await Navigator.of(context).push<RgbaImage>(
      MaterialPageRoute<RgbaImage>(
        builder: (_) => CropScreen(
          source: picked,
          canvasWidth: state.canvasSize.width,
          canvasHeight: state.canvasSize.height,
        ),
      ),
    );
    if (cropped == null) {
      return;
    }
    state.replaceSource(cropped);
    state.addLog(
      LogLevel.success,
      '已导入图片并裁剪到 ${cropped.width}×${cropped.height}',
    );
  }

  String _algorithmLabel(DitherAlgorithm algorithm) {
    return switch (algorithm) {
      DitherAlgorithm.floydSteinberg => 'Floyd–Steinberg（默认）',
      DitherAlgorithm.atkinson => 'Atkinson',
      DitherAlgorithm.stucki => 'Stucki',
      DitherAlgorithm.jarvis => 'Jarvis',
      DitherAlgorithm.bayer => 'Bayer',
      DitherAlgorithm.none => '不抖动',
    };
  }
}

/// 一行「标签 + 滑块 + 数值」。
class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.display,
    required this.onChanged,
    this.onChangeEnd,
    this.divisions,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final String display;
  final int? divisions;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeEnd;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Row(
      children: <Widget>[
        SizedBox(
          width: 52,
          child: Text(label, style: theme.textTheme.bodySmall),
        ),
        Expanded(
          child: Slider(
            value: value.clamp(min, max).toDouble(),
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
            onChangeEnd: onChangeEnd,
          ),
        ),
        SizedBox(
          width: 40,
          child: Text(
            display,
            textAlign: TextAlign.end,
            style: theme.textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}
