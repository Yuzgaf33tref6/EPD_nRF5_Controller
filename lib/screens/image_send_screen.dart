import 'dart:async';

import 'package:flutter/material.dart';

import '../image/dither.dart';
import '../image/preview_computer.dart';
import '../image/process.dart';
import '../image/rgba_image.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';
import '../widgets/image_preview.dart';
import 'canvas_editor_screen.dart';
import 'crop_screen.dart';

/// 图像发送页（二级）：画布预览 + 处理 + 抖动参数 + 导入/编辑 + 发送。
///
/// 流水线固定为 **原图 → 处理 → 抖动**：处理阶段调亮度/自动亮度/色彩简化，
/// 抖动阶段把图压到墨水屏调色板。预览可以停在三档中的任意一步，方便对比
/// 「哪一步把画面弄坏了」。
///
/// 这里会跑处理和抖动（400×300 图约百毫秒），所以做成独立页面按需进入，
/// 不放在底部导航的一级页里；算式本身丢在后台 isolate（[PreviewComputer]）。
class ImageSendScreen extends StatefulWidget {
  const ImageSendScreen({super.key});

  @override
  State<ImageSendScreen> createState() => _ImageSendScreenState();
}

class _ImageSendScreenState extends State<ImageSendScreen> {
  /// 拖动滑块时先用局部值跟手，松开（或停顿 160ms）才真正提交，避免每帧整图重算。
  double? _pendingStrength;
  double? _pendingContrast;
  double? _pendingBrightness;
  Timer? _strengthDebounce;
  Timer? _contrastDebounce;
  Timer? _brightnessDebounce;

  /// 预览停在哪一档。
  PreviewStage _stage = PreviewStage.dithered;

  /// 后台算好的预览。为 null 时表示还没算完，先拿同步缓存顶上。
  late final PreviewComputer _preview = PreviewComputer()
    ..onResult = ((DitherJob job, RgbaImage image) {
      if (!mounted || _disposed) {
        return;
      }
      // 算的过程中可能已经切了档，这种过期结果直接丢。
      if (job.stage != _stage) {
        return;
      }
      setState(() {
        _ditherResult = image;
        _resultStage = job.stage;
      });
    });

  RgbaImage? _ditherResult;
  PreviewStage? _resultStage;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _requestPreview());
  }

  @override
  void dispose() {
    _disposed = true;
    _strengthDebounce?.cancel();
    _contrastDebounce?.cancel();
    _brightnessDebounce?.cancel();
    _preview.dispose();
    super.dispose();
  }

  /// 把当前参数丢给后台 isolate 算预览。
  void _requestPreview() {
    final AppState? state = AppStateScope.maybeOf(context);
    if (state == null) {
      return;
    }
    _preview.request(state.previewJob(_stage));
  }

  /// 当前该显示哪张图：优先后台结果（同档位），否则用同步缓存顶上。
  RgbaImage _previewFor(AppState state) {
    if (_resultStage == _stage && _ditherResult != null) {
      return _ditherResult!;
    }
    return switch (_stage) {
      PreviewStage.original => state.sourceImage,
      PreviewStage.processed => state.processedImage,
      PreviewStage.dithered => state.previewImage,
    };
  }

  String get _previewTitle => switch (_stage) {
        PreviewStage.original => '预览（原图）',
        PreviewStage.processed => '预览（处理）',
        PreviewStage.dithered => '预览（抖动后）',
      };

  @override
  Widget build(BuildContext context) {
    final AppState state = AppStateScope.of(context);
    final ThemeData theme = Theme.of(context);
    final RgbaImage preview = _previewFor(state);
    // 参数一变就重新排队（相同入参会被 PreviewComputer 直接跳过）。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _requestPreview();
      }
    });
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
                  title: _previewTitle,
                  icon: Icons.image_outlined,
                  trailing: SegmentedButton<PreviewStage>(
                    showSelectedIcon: false,
                    style: const ButtonStyle(
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    segments: <ButtonSegment<PreviewStage>>[
                      for (final PreviewStage stage in PreviewStage.values)
                        ButtonSegment<PreviewStage>(
                          value: stage,
                          label: Text(stage.label),
                        ),
                    ],
                    selected: <PreviewStage>{_stage},
                    onSelectionChanged: (Set<PreviewStage> value) {
                      setState(() {
                        _stage = value.first;
                        // 换档后旧结果不再对应，先清掉避免看到上一档的画面。
                        _ditherResult = null;
                        _resultStage = null;
                      });
                      _requestPreview();
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
                  title: '处理',
                  icon: Icons.tune,
                  trailing: Text(
                    state.processSummary,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: const Text('自动亮度'),
                        subtitle: const Text(
                          '按直方图拉伸黑白点，不改色相、不改构图。',
                        ),
                        value: state.autoBrightness,
                        onChanged: (bool value) {
                          state.setAutoBrightness(value);
                          _requestPreview();
                        },
                      ),
                      _SliderRow(
                        label: '亮度',
                        value: _pendingBrightness ?? state.brightness,
                        min: -100,
                        max: 100,
                        divisions: 200,
                        display: formatBrightness(
                          _pendingBrightness ?? state.brightness,
                        ),
                        onChanged: (double value) {
                          setState(() => _pendingBrightness = value);
                          _brightnessDebounce?.cancel();
                          _brightnessDebounce = Timer(
                            const Duration(milliseconds: 160),
                            () => _commitBrightness(value),
                          );
                        },
                        onChangeEnd: _commitBrightness,
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: const Text('色彩简化'),
                        subtitle: Text(
                          '把整张图压到 ${state.simplifyColorCount} 色再抖动，'
                          '色块感更强但更干净。',
                        ),
                        value: state.simplifyColors,
                        onChanged: (bool value) {
                          state.setSimplifyColors(value);
                          _requestPreview();
                        },
                      ),
                      if (state.simplifyColors)
                        _SliderRow(
                          label: '色数',
                          value: state.simplifyColorCount.toDouble(),
                          min: 2,
                          max: 64,
                          divisions: 62,
                          display: '${state.simplifyColorCount}',
                          onChanged: (double value) {
                            state.setSimplifyColorCount(value.round());
                            _requestPreview();
                          },
                        ),
                      const SizedBox(height: 4),
                      TextButton.icon(
                        onPressed: () {
                          state.resetProcess();
                          _requestPreview();
                        },
                        icon: const Icon(Icons.restart_alt, size: 18),
                        label: const Text('恢复默认处理'),
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
                            _requestPreview();
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
                            onPressed: () {
                              state.rotateSource();
                              _requestPreview();
                            },
                            icon: const Icon(Icons.rotate_90_degrees_cw,
                                size: 18),
                            label: const Text('旋转画布'),
                          ),
                          OutlinedButton.icon(
                            onPressed: () {
                              state.resetSource();
                              _requestPreview();
                            },
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
    _requestPreview();
  }

  void _commitContrast(double value) {
    _contrastDebounce?.cancel();
    final AppState state = AppStateScope.of(context);
    state.setContrast(value);
    if (mounted) {
      setState(() => _pendingContrast = null);
    }
    _requestPreview();
  }

  void _commitBrightness(double value) {
    _brightnessDebounce?.cancel();
    final AppState state = AppStateScope.of(context);
    state.setBrightness(value);
    if (mounted) {
      setState(() => _pendingBrightness = null);
    }
    _requestPreview();
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
    _requestPreview();
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
          width: 44,
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
