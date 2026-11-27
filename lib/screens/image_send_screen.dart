import 'dart:async';

import 'package:flutter/material.dart';

import '../image/dither.dart';
import '../image/process.dart';
import '../image/preview_computer.dart';
import '../image/rgba_image.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';
import '../widgets/image_preview.dart';
import 'canvas_editor_screen.dart';
import 'crop_screen.dart';

/// 图像发送页（二级页面）。
///
/// 布局要点（0.3.0 调整）：
/// - **预览固定在顶部**，只让下面的「处理 / 抖动 / 传图」滚动；
/// - 「处理」「抖动」两张卡可折叠，默认展开，折叠状态不记忆；
/// - 所有预览计算（处理 + 抖动）都在后台 isolate 里跑，超过 300ms 才弹
///   「处理中」遮罩，避免用户以为界面卡死。
class ImageSendScreen extends StatefulWidget {
  const ImageSendScreen({super.key});

  @override
  State<ImageSendScreen> createState() => _ImageSendScreenState();
}

class _ImageSendScreenState extends State<ImageSendScreen> {
  // ---- 预览 ----
  PreviewStage _stage = PreviewStage.dithered;
  late final PreviewComputer _preview = PreviewComputer()
    ..onResult = _onPreviewResult;
  RgbaImage? _previewResult;
  PreviewStage? _resultStage;
  Object? _resultKey;
  Object? _requestedKey;
  Timer? _busyTimer;
  bool _showBusy = false;
  bool _disposed = false;

  // ---- 滑块拖动中的临时值（让滑块跟手，不每次拖动都整图重算）----
  double? _pendingStrength;
  double? _pendingContrast;
  double? _pendingBrightness;
  Timer? _strengthDebounce;
  Timer? _contrastDebounce;
  Timer? _brightnessDebounce;

  /// 弹「处理中」遮罩的阈值：低于这个时长用户感知不到，没必要闪一下。
  static const Duration _busyThreshold = Duration(milliseconds: 300);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _requestPreview());
  }

  @override
  void dispose() {
    _disposed = true;
    _busyTimer?.cancel();
    _strengthDebounce?.cancel();
    _contrastDebounce?.cancel();
    _brightnessDebounce?.cancel();
    _preview.dispose();
    super.dispose();
  }

  void _onPreviewResult(DitherJob job, RgbaImage image) {
    if (!mounted || _disposed || job.stage != _stage) {
      return;
    }
    setState(() {
      _previewResult = image;
      _resultStage = job.stage;
      _resultKey = job.key;
      _showBusy = false;
    });
    _busyTimer?.cancel();
  }

  /// 请求一次当前档位的预览计算。
  void _requestPreview() {
    final AppState? state = AppStateScope.maybeOf(context);
    if (state == null) {
      return;
    }
    final DitherJob job = state.previewJob(_stage);
    _requestedKey = job.key;
    _preview.request(job);

    _busyTimer?.cancel();
    _busyTimer = Timer(_busyThreshold, () {
      if (!mounted || _disposed) {
        return;
      }
      if (_resultKey == _requestedKey) {
        return;
      }
      setState(() => _showBusy = true);
    });
  }

  /// 当前该显示的图：有本阶段结果就用结果，否则退回原图（**不要**在这里
  /// 同步调用 `state.processedImage`，那正是原来的卡顿来源）。
  RgbaImage _previewFor(AppState state) {
    if (_resultStage == _stage && _previewResult != null) {
      return _previewResult!;
    }
    return state.sourceImage;
  }

  String get _previewTitle {
    return switch (_stage) {
      PreviewStage.original => '预览（原图）',
      PreviewStage.processed => '预览（处理）',
      PreviewStage.dithered => '预览（抖动后）',
    };
  }

  @override
  Widget build(BuildContext context) {
    final AppState state = AppStateScope.of(context);
    final ThemeData theme = Theme.of(context);
    final RgbaImage preview = _previewFor(state);

    return Scaffold(
      appBar: AppBar(
        title: const Text('图像发送'),
        actions: <Widget>[
          IconButton(
            tooltip: '画布编辑',
            icon: const Icon(Icons.brush_outlined),
            onPressed: () async {
              await Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => const CanvasEditorScreen(),
                ),
              );
              _requestPreview();
            },
          ),
        ],
      ),
      body: Stack(
        children: <Widget>[
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              // 预览占上半部分的一个固定比例，剩下的留给可滚动的调整区。
              final double previewHeight = (constraints.maxHeight * 0.42)
                  .clamp(120.0, 300.0)
                  .toDouble();
              return Column(
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                    child: _buildPreviewCard(
                      state,
                      theme,
                      preview,
                      previewHeight,
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                      children: <Widget>[
                        _buildProcessCard(state, theme),
                        const SizedBox(height: 12),
                        _buildDitherCard(state, theme),
                        const SizedBox(height: 12),
                        _buildSendCard(state, theme),
                      ],
                    ),
                  ),
                  DeviceStatusBar(state: state),
                ],
              );
            },
          ),
          if (_showBusy) _buildBusyOverlay(theme),
        ],
      ),
    );
  }

  Widget _buildPreviewCard(
    AppState state,
    ThemeData theme,
    RgbaImage preview,
    double previewHeight,
  ) {
    return SectionCard(
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
        onSelectionChanged: (Set<PreviewStage> selected) {
          setState(() {
            _stage = selected.first;
            _showBusy = false;
          });
          _requestPreview();
        },
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // 高度固定：无论下面的调整区怎么滚，预览都待在原地不跳。
          SizedBox(
            height: previewHeight,
            child: Center(
              child: AspectRatio(
                aspectRatio: preview.width / preview.height,
                child: RepaintBoundary(
                  child: RgbaImagePreview(image: preview, maxWidth: 400),
                ),
              ),
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
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '图片比例与画布不一致，抖动前建议重新裁剪。',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildProcessCard(AppState state, ThemeData theme) {
    return CollapsibleCard(
      title: '处理',
      icon: Icons.tune,
      trailing: Text(
        state.processSummary,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          DropdownButtonFormField<PreprocessPreset>(
            initialValue: state.preprocess,
            decoration: const InputDecoration(
              labelText: '预处理效果',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: <DropdownMenuItem<PreprocessPreset>>[
              for (final PreprocessPreset preset in PreprocessPreset.values)
                DropdownMenuItem<PreprocessPreset>(
                  value: preset,
                  child: Text(preset.label),
                ),
            ],
            onChanged: (PreprocessPreset? preset) {
              if (preset == null) {
                return;
              }
              state.setPreprocess(preset);
              _requestPreview();
            },
          ),
          SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            value: state.brightnessBalance,
            onChanged: (bool value) {
              state.setBrightnessBalance(value);
              _requestPreview();
            },
            title: const Text('亮度均衡'),
            subtitle: const Text(
              '分位裁剪定黑白点，并把中间调拉到中间；对大片白背景或整体偏暗的图更有效。',
            ),
          ),
          _SliderRow(
            label: '亮度',
            value: _pendingBrightness ?? state.brightness,
            min: -100,
            max: 100,
            divisions: 200,
            display: formatBrightness(_pendingBrightness ?? state.brightness),
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
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () {
                final double value = state.applyAutoBrightness();
                setState(() => _pendingBrightness = null);
                _requestPreview();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      '自动亮度：亮度 ${formatBrightness(value)}',
                    ),
                    duration: const Duration(seconds: 2),
                  ),
                );
              },
              icon: const Icon(Icons.auto_fix_high, size: 18),
              label: const Text('自动亮度'),
            ),
          ),
          SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            value: state.simplifyColors,
            onChanged: (bool value) {
              state.setSimplifyColors(value);
              _requestPreview();
            },
            title: const Text('色彩简化'),
            subtitle: const Text(
              '把整张图压到 N 色再抖动，能减少调色板边缘的反复横跳，但会改变观感。',
            ),
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
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () {
                state.resetProcess();
                setState(() {
                  _pendingBrightness = null;
                });
                _requestPreview();
              },
              icon: const Icon(Icons.restart_alt, size: 18),
              label: const Text('恢复默认处理'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDitherCard(AppState state, ThemeData theme) {
    final List<_AlgorithmOption> options = _algorithmOptions;
    final int selectedIndex = options.indexWhere(
      (_AlgorithmOption option) => option.algorithm == state.algorithm,
    );
    final bool isDiffusion = _isErrorDiffusion(state.algorithm);

    return CollapsibleCard(
      title: '抖动',
      icon: Icons.grain,
      trailing: Text(
        '强度 ${state.strength.toStringAsFixed(1)} · '
        '对比 ${state.contrast.toStringAsFixed(1)}',
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          DropdownButtonFormField<int>(
            initialValue: selectedIndex < 0 ? 0 : selectedIndex,
            decoration: const InputDecoration(
              labelText: '抖动算法',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: <DropdownMenuItem<int>>[
              for (int i = 0; i < options.length; i++)
                DropdownMenuItem<int>(
                  value: i,
                  enabled: options[i].algorithm != null,
                  child: Text(
                    options[i].algorithm == null
                        ? options[i].header!
                        : _algorithmLabel(options[i].algorithm!),
                  ),
                ),
            ],
            onChanged: (int? index) {
              if (index == null || index < 0 || index >= options.length) {
                return;
              }
              final DitherAlgorithm? algorithm = options[index].algorithm;
              if (algorithm == null) {
                return;
              }
              state.setAlgorithm(algorithm);
              _requestPreview();
            },
          ),
          Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 2),
            child: Text(
              '适用范围：${_algorithmScope(state.algorithm)}',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          if (state.algorithm == DitherAlgorithm.blueNoise &&
              !state.noiseMaskReady)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                state.noiseMaskLoading
                    ? '正在加载蓝噪声纹理 …'
                    : '蓝噪声纹理尚未就绪：暂时用程序生成的散列噪声代替。',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ),
          SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            value: state.serpentine,
            onChanged: isDiffusion
                ? (bool value) {
                    state.setSerpentine(value);
                    _requestPreview();
                  }
                : null,
            title: const Text('蛇形扫描'),
            subtitle: Text(
              isDiffusion
                  ? '奇数行反向扫描再扩散，能明显打散单向推流产生的斜纹。'
                  : '只对误差扩散类算法有效（有序抖动是逐像素独立的）。',
            ),
          ),
          _SliderRow(
            label: '强度',
            value: _pendingStrength ?? state.strength,
            min: 0,
            max: 5,
            divisions: 50,
            display: (_pendingStrength ?? state.strength).toStringAsFixed(1),
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
            display: (_pendingContrast ?? state.contrast).toStringAsFixed(1),
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
                icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
                label: const Text('导入图片'),
              ),
              OutlinedButton.icon(
                onPressed: () {
                  state.rotateSource();
                  _requestPreview();
                },
                icon: const Icon(Icons.rotate_90_degrees_cw, size: 18),
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
    );
  }

  Widget _buildSendCard(AppState state, ThemeData theme) {
    return SectionCard(
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
            onPressed: state.isConnected ? () => state.sendPreview() : null,
            icon: const Icon(Icons.send, size: 18),
            label: Text(state.isConnected ? '发送到设备' : '未连接设备，无法发送'),
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
    );
  }

  Widget _buildBusyOverlay(ThemeData theme) {
    return Positioned.fill(
      child: GestureDetector(
        onTap: () {},
        child: ColoredBox(
          color: Colors.black54,
          child: Center(
            child: Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 16,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 12),
                    Text('处理中 …', style: theme.textTheme.bodyMedium),
                  ],
                ),
              ),
            ),
          ),
        ),
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

  /// 按「算法类型」分组的下拉选项（表头项 [algorithm] 为 null，不可选）。
  List<_AlgorithmOption> get _algorithmOptions => <_AlgorithmOption>[
        const _AlgorithmOption.header('── 误差扩散（照片 / 插画通用）──'),
        const _AlgorithmOption.item(DitherAlgorithm.floydSteinberg),
        const _AlgorithmOption.item(DitherAlgorithm.atkinson),
        const _AlgorithmOption.item(DitherAlgorithm.stucki),
        const _AlgorithmOption.item(DitherAlgorithm.jarvis),
        const _AlgorithmOption.item(DitherAlgorithm.sierraLite),
        const _AlgorithmOption.item(DitherAlgorithm.burkes),
        const _AlgorithmOption.item(DitherAlgorithm.shiauFan),
        const _AlgorithmOption.item(DitherAlgorithm.shiauFan2),
        const _AlgorithmOption.header('── 有序抖动（网点风格）──'),
        const _AlgorithmOption.item(DitherAlgorithm.bayer),
        const _AlgorithmOption.item(DitherAlgorithm.bayer4x4),
        const _AlgorithmOption.item(DitherAlgorithm.blueNoise),
        const _AlgorithmOption.header('── 不抖动 ──'),
        const _AlgorithmOption.item(DitherAlgorithm.none),
      ];

  bool _isErrorDiffusion(DitherAlgorithm algorithm) {
    return switch (algorithm) {
      DitherAlgorithm.floydSteinberg ||
      DitherAlgorithm.atkinson ||
      DitherAlgorithm.stucki ||
      DitherAlgorithm.jarvis ||
      DitherAlgorithm.sierraLite ||
      DitherAlgorithm.burkes ||
      DitherAlgorithm.shiauFan ||
      DitherAlgorithm.shiauFan2 =>
        true,
      DitherAlgorithm.bayer ||
      DitherAlgorithm.bayer4x4 ||
      DitherAlgorithm.blueNoise ||
      DitherAlgorithm.none =>
        false,
    };
  }

  String _algorithmLabel(DitherAlgorithm algorithm) {
    return switch (algorithm) {
      DitherAlgorithm.floydSteinberg => 'Floyd–Steinberg（默认）',
      DitherAlgorithm.atkinson => 'Atkinson',
      DitherAlgorithm.stucki => 'Stucki',
      DitherAlgorithm.jarvis => 'Jarvis',
      DitherAlgorithm.bayer => 'Bayer 8×8',
      DitherAlgorithm.sierraLite => 'Sierra Lite',
      DitherAlgorithm.burkes => 'Burkes',
      DitherAlgorithm.shiauFan => 'Shiau-Fan',
      DitherAlgorithm.shiauFan2 => 'Shiau-Fan 2',
      DitherAlgorithm.bayer4x4 => 'Bayer 4×4',
      DitherAlgorithm.blueNoise => '蓝噪声',
      DitherAlgorithm.none => '不抖动',
    };
  }

  String _algorithmScope(DitherAlgorithm algorithm) {
    return switch (algorithm) {
      DitherAlgorithm.floydSteinberg => '通用首选，照片和插画都稳，颗粒略细。',
      DitherAlgorithm.atkinson => '高对比线条、文字；亮部细节会丢，复古 Mac 观感。',
      DitherAlgorithm.stucki => '照片，颗粒比 Floyd 更小，但更慢。',
      DitherAlgorithm.jarvis => '照片，过渡最平滑，速度最慢。',
      DitherAlgorithm.sierraLite => '快速通用，边缘干净，算力最省。',
      DitherAlgorithm.burkes => '照片，斜纹少、颗粒均匀。',
      DitherAlgorithm.shiauFan => '文字、线条、图表（偏右扩散，保留笔画）。',
      DitherAlgorithm.shiauFan2 => '暗部细节多的图：夜景、深色插画。',
      DitherAlgorithm.bayer => '8×8 网点，复古网点感，适合渐变与图标。',
      DitherAlgorithm.bayer4x4 => '4×4 网点，颗粒更粗，印刷海报感。',
      DitherAlgorithm.blueNoise => '照片首选：没有规则网格，观感最接近连续调。',
      DitherAlgorithm.none => '只适合纯色块或本身已是网点的图。',
    };
  }
}

/// 下拉框里的一项：要么是分组表头，要么是一个算法。
class _AlgorithmOption {
  const _AlgorithmOption.header(this.header) : algorithm = null;
  const _AlgorithmOption.item(this.algorithm) : header = null;

  final String? header;
  final DitherAlgorithm? algorithm;
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
