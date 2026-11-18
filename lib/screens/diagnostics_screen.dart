import 'package:flutter/material.dart';

import '../image/epd_color.dart';
import '../state/app_state.dart';
import '../widgets/log_panel.dart';
import '../widgets/section_card.dart';

/// 纯色测试用的三个颜色（黑 / 白 / 红，即三色屏的全部基色）。
final List<EpdColor> _solidTestColors = <EpdColor>[
  rgbPalette[0],
  rgbPalette[1],
  rgbPalette[3],
];

/// 蓝牙诊断页：把链路层面的真实状态摊开，方便在没有真机现场时定位问题。
///
/// 显示权限结果、蓝牙子系统状态、连接/固件/MTU、已写入条数与最近收到的通知原文。
/// 这三个按钮分别对应「系统状态」「权限」「链路可写」三个最常出问题的环节。
class DiagnosticsScreen extends StatelessWidget {
  const DiagnosticsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final AppState state = AppStateScope.of(context);
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('蓝牙诊断')),
      body: Column(
        children: <Widget>[
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: <Widget>[
                SectionCard(
                  title: '链路状态',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      _InfoRow(label: '蓝牙', value: state.adapterStatusText),
                      _InfoRow(
                        label: '连接',
                        value: state.isConnected
                            ? '${state.connectedDevice!.name}（${state.connectedDevice!.id}）'
                            : '未连接',
                      ),
                      _InfoRow(label: '固件', value: state.firmwareVersionText),
                      _InfoRow(label: '引脚', value: state.pinsText),
                      _InfoRow(
                        label: 'MTU',
                        value: '${state.mtu}（每块 ${state.writeChunkBytes} 字节）',
                      ),
                      _InfoRow(
                        label: 'RLE',
                        value: state.rleSupported ? '支持' : '不支持',
                      ),
                      _InfoRow(label: '已写入', value: '${state.writesSent} 条负载'),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                SectionCard(
                  title: '诊断动作',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: <Widget>[
                          OutlinedButton.icon(
                            onPressed: () => state.refreshDiagnostics(),
                            icon: const Icon(Icons.refresh),
                            label: const Text('刷新蓝牙状态'),
                          ),
                          OutlinedButton.icon(
                            onPressed: () => state.requestBlePermission(),
                            icon: const Icon(Icons.privacy_tip_outlined),
                            label: const Text('申请蓝牙权限'),
                          ),
                          FilledButton.icon(
                            onPressed: state.isConnected
                                ? () => state.sendDiagnosticInit()
                                : null,
                            icon: const Icon(Icons.play_arrow),
                            label: const Text('发送 INIT 测试'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: const Text('详细传输日志'),
                        subtitle: const Text(
                          '开启后每条写指令（序号 / 长度 / 是否等确认 / 原始字节）'
                          '都会打到 logcat，排查「发不完」「刷新不全」时用',
                        ),
                        value: state.verboseTransfers,
                        onChanged: state.setVerboseTransfers,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '若「扫描不到设备」，先确认系统里的蓝牙已打开、'
                        '「附近的设备」权限已允许；Android 11 及以下还需要定位权限。',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                SectionCard(
                  title: '纯色测试（查平面极性）',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: <Widget>[
                          for (final EpdColor color in _solidTestColors)
                            OutlinedButton(
                              onPressed: state.isConnected
                                  ? () => state.sendSolidColor(color)
                                  : null,
                              child: Text(color.name),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '分别发一次全黑 / 全白 / 全红，屏幕应当整屏变成对应颜色：\n'
                        '· 发全黑却出来红色 → 黑白平面与红白平面搞反了；\n'
                        '· 发全红却出来白色（或反之）→ 红白平面极性相反；\n'
                        '· 三个都对 → 数据链路没问题，问题在抖动后的图本身。',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                SectionCard(
                  title: '收到的通知（最新在上）',
                  child: state.notificationLog.isEmpty
                      ? const Text('还没有收到通知；连接设备并发 INIT 后再看这里')
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: state.notificationLog.reversed
                              .map(
                                (String entry) => Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 2),
                                  child: Text(
                                    entry,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      fontFamily: 'monospace',
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                ),
              ],
            ),
          ),
          const LogPanel(height: 120),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 64,
            child: Text(label, style: theme.textTheme.bodySmall),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
