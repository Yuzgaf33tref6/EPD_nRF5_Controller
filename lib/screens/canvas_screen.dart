import 'dart:async';

import 'package:flutter/material.dart';

import '../devices/epd_driver.dart';
import '../image/dither.dart';
import '../image/rgba_image.dart';
import '../state/app_state.dart';
import '../widgets/image_preview.dart';
import '../widgets/log_panel.dart';
import '../widgets/section_card.dart';
import 'canvas_editor_screen.dart';
import 'crop_screen.dart';

/// 画布页：预览抖动结果 + 调抖动参数 + 看真实传图统计 + 发送。
///
/// 性能注意：抖动是纯 CPU 的整图计算（400×300 逐像素 Lab 比色），一次要几十毫秒。
/// 如果 Slider 每动一格就把它算一遍，主线程会被连续堵死，拖动像幻灯片。所以这里
/// 拖动过程中只更新滑块自己的位置，真正提交参数走两种时机：松手（`onChangeEnd`）
/// 以及拖动中 160ms 的防抖 —— 既不会卡，也不至于完全看不到反馈。
class CanvasScreen extends StatefulWidget {
  const CanvasScreen({super.key});

  @override
  State<CanvasScreen> createState() => _CanvasScreenState();
}

class _CanvasScreenState extends State<CanvasScreen> {
  static const Duration _commitDelay = Duration(milliseconds: 160);

  double? _pendingStrength;
  double? _pendingContrast;
  Timer? _strengthTimer;
  Timer? _contrastTimer;

  @override
  void dispose() {
    _strengthTimer?.cancel();
    _contrastTimer?.cancel();
    super.dispose();
  }

  void _dragStrength(AppState state, double value) {
    setState(() => _pendingStrength = value);
    _strengthTimer?.cancel();
    _strengthTimer = Timer(_commitDelay, () => state.setStrength(value));
  }

  void _commitStrength(AppState state, double value) {
    _strengthTimer?.cancel();
    setState(() => _pendingStrength = null);
    state.setStrength(value);
  }

  void _dragContrast(AppState state, double value) {
    setState(() => _pendingContrast = value);
    _contrastTimer?.cancel();
    _contrastTimer = Timer(_commitDelay, () => state.setContrast(value));
  }

  void _commitContrast(AppState state, double value) {
    _contrastTimer?.cancel();
    setState(() => _pendingContrast = null);
    state.setContrast(value);
  }

  /// 选图 → 裁剪 → 换成底图。
  Future<void> _importImage(AppState state) async {
    final RgbaImage? picked = await state.pickImageFromGallery();
    if (picked == null || !mounted) {
      return;
    }
    final RgbaImage? cropped = await Navigator.of(context).push<RgbaImage>(
      MaterialPageRoute<RgbaImage>(
        builder: (BuildContext context) => CropScreen(
          source: picked,
          canvasWidth: state.canvasSize.width,
          canvasHeight: state.canvasSize.height,
        ),
      ),
    );
    if (cropped == null || !mounted) {
      return;
    }
    state.replaceSource(cropped);
    state.addLog(
      LogLevel.success,
      '已导入图片并裁剪到 ${cropped.width}×${cropped.height}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppState state = AppStateScope.of(context);
    final ThemeData theme = Theme.of(context);
    final List<String> warnings = state.warnings;
    final double strength = _pendingStrength ?? state.strength;
    final double contrast = _pendingContrast ?? state.contrast;

    return Scaffold(
      appBar: AppBar(
        title: const Text('画布与传图'),
        actions: <Widget>[
          IconButton(
            tooltip: '画布编辑',
            icon: const Icon(Icons.brush_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (BuildContext context) => const CanvasEditorScreen(),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: <Widget>[
                SectionCard(
                  title: '预览（抖动后）',
                  trailing: Text(
                    '${state.canvasSize.width}×${state.canvasSize.height}',
                    style: theme.textTheme.bodySmall,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Center(
                        // RepaintBoundary：抖动参数变化时只重画画布这块，
                        // 不让整页跟着重绘。
                        child: RepaintBoundary(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 320),
                            child: RgbaImagePreview(image: state.previewImage),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '驱动 ${state.driver.label} · ${state.colorMode.jsName}'
                        ' · 固件 ${state.firmwareVersionText}',
                        style: theme.textTheme.bodySmall,
                      ),
                      if (!state.aspectMatchesCanvas)
                        Text(
                          '原图宽高比与画布不一致，真机上需要先裁剪',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: theme.colorScheme.error),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                SectionCard(
                  title: '抖动',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          const Text('算法'),
                          const SizedBox(width: 12),
                          Expanded(
                            child: DropdownButton<DitherAlgorithm>(
                              isExpanded: true,
                              value: state.algorithm,
                              items: DitherAlgorithm.values
                                  .map(
                                    (DitherAlgorithm alg) =>
                                        DropdownMenuItem<DitherAlgorithm>(
                                      value: alg,
                                      child: Text(alg.jsName),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (DitherAlgorithm? alg) {
                                if (alg != null) {
                                  state.setAlgorithm(alg);
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                      _SliderRow(
                        label: '强度',
                        value: strength,
                        min: 0,
                        max: 5,
                        divisions: 50,
                        display: strength.toStringAsFixed(1),
                        onChanged: (double value) => _dragStrength(state, value),
                        onChangeEnd: (double value) =>
                            _commitStrength(state, value),
                      ),
                      _SliderRow(
                        label: '对比度',
                        value: contrast,
                        min: 0.5,
                        max: 2,
                        divisions: 15,
                        display: contrast.toStringAsFixed(1),
                        onChanged: (double value) =>
                            _dragContrast(state, value),
                        onChangeEnd: (double value) =>
                            _commitContrast(state, value),
                      ),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: <Widget>[
                          OutlinedButton.icon(
                            onPressed: () => _importImage(state),
                            icon: const Icon(Icons.add_photo_alternate_outlined),
                            label: const Text('导入图片'),
                          ),
                          OutlinedButton.icon(
                            onPressed: state.resetSource,
                            icon: const Icon(Icons.restart_alt),
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        state.transferSummary,
                        style: theme.textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'MTU ${state.mtu} · 交错 ${state.interleavedCount} 块'
                        '一次应答 · ${state.rleSupported ? 'RLE 开启' : 'RLE 关闭'}',
                        style: theme.textTheme.bodySmall,
                      ),
                      if (warnings.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 8),
                        for (final String warning in warnings)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 1),
                            child: Text(
                              warning,
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(color: theme.colorScheme.error),
                            ),
                          ),
                      ],
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed:
                            state.isConnected ? () => state.sendPreview() : null,
                        icon: const Icon(Icons.send),
                        label: const Text('发送到设备'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                SectionCard(
                  title: '驱动',
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: state.driver.id,
                    items: kEpdDrivers
                        .map(
                          (EpdDriver driver) => DropdownMenuItem<String>(
                            value: driver.id,
                            child: Text(
                              driver.label,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (String? id) {
                      if (id == null) {
                        return;
                      }
                      final EpdDriver? driver = driverById(id);
                      if (driver != null) {
                        state.setDriver(driver);
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
          const LogPanel(),
        ],
      ),
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.display,
    required this.onChanged,
    this.onChangeEnd,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String display;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeEnd;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Row(
      children: <Widget>[
        SizedBox(
          width: 48,
          child: Text(label, style: theme.textTheme.bodySmall),
        ),
        Expanded(
          child: Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            label: display,
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
