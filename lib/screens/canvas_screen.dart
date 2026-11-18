import 'package:flutter/material.dart';

import '../devices/epd_driver.dart';
import '../image/dither.dart';
import '../state/app_state.dart';
import '../widgets/image_preview.dart';
import '../widgets/log_panel.dart';
import '../widgets/section_card.dart';

/// 画布页：预览抖动结果 + 调抖动参数 + 看真实传图统计 + 模拟发送。
class CanvasScreen extends StatelessWidget {
  const CanvasScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final AppState state = AppStateScope.of(context);
    final ThemeData theme = Theme.of(context);
    final List<String> warnings = state.warnings;

    return Scaffold(
      appBar: AppBar(title: const Text('画布与传图')),
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
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 320),
                          child: RgbaImagePreview(image: state.previewImage),
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
                        value: state.strength,
                        min: 0,
                        max: 5,
                        divisions: 50,
                        display: state.strength.toStringAsFixed(1),
                        onChanged: state.setStrength,
                      ),
                      _SliderRow(
                        label: '对比度',
                        value: state.contrast,
                        min: 0.5,
                        max: 2,
                        divisions: 15,
                        display: state.contrast.toStringAsFixed(1),
                        onChanged: state.setContrast,
                      ),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: <Widget>[
                          OutlinedButton.icon(
                            onPressed: state.rotateSource,
                            icon: const Icon(Icons.rotate_90_degrees_cw),
                            label: const Text('旋转 90°'),
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
                            state.isConnected ? state.sendPreview : null,
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
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String display;
  final ValueChanged<double> onChanged;

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
