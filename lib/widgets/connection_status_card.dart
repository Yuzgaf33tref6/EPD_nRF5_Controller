import 'package:flutter/material.dart';

import '../state/app_state.dart';

/// 首页顶部的连接状态大卡片。
///
/// 未连接时显示灰度状态与「去连接」提示；已连接时显示设备名、信号强度、
/// 固件版本、驱动与画布。下面的三个快捷按钮（连接 / 断开 / 重连）由首页负责。
class ConnectionStatusCard extends StatelessWidget {
  const ConnectionStatusCard({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool connected = state.isConnected;
    final bool busy = state.isConnecting;
    final Color accent = connected
        ? (busy ? theme.colorScheme.tertiary : theme.colorScheme.primary)
        : theme.colorScheme.outline;

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: connected
          ? theme.colorScheme.primaryContainer.withValues(alpha: 0.55)
          : theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: accent.withValues(alpha: 0.15),
              ),
              child: Icon(
                connected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
                color: accent,
                size: 26,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    connected
                        ? (busy ? '正在连接 …' : '已连接')
                        : (busy ? '正在连接 …' : '未连接'),
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: connected ? theme.colorScheme.onPrimaryContainer : null,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    state.connectedDevice?.name ?? _disconnectedHint(state),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: connected
                          ? theme.colorScheme.onPrimaryContainer
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (connected) ...<Widget>[
                    const SizedBox(height: 10),
                    _StatusChips(state: state),
                  ] else if (state.adapterStatusText != '未检查') ...<Widget>[
                    const SizedBox(height: 6),
                    Text(
                      '蓝牙状态：${state.adapterStatusText}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _disconnectedHint(AppState state) {
    final String? name = state.lastDeviceName;
    if (name != null && name.isNotEmpty) {
      return '上次连接：$name';
    }
    return '还没有连接过设备';
  }
}

/// 已连接时的一排小标签：信号 / 固件 / 驱动 / 画布。
class _StatusChips extends StatelessWidget {
  const _StatusChips({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final int? rssi = state.connectedDevice?.rssi;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: <Widget>[
        if (rssi != null) _Chip(icon: Icons.signal_cellular_alt, text: '$rssi dBm'),
        _Chip(icon: Icons.memory, text: '固件 ${state.firmwareVersionText}'),
        _Chip(
          icon: Icons.tune,
          text: '驱动 0x${state.driver.id.toUpperCase()}',
        ),
        _Chip(
          icon: Icons.crop_free,
          text: '${state.canvasSize.width}×${state.canvasSize.height}',
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 13, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(
            text,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// 首页的「连接 / 断开 / 重连」快捷按钮组。
class QuickConnectButtons extends StatelessWidget {
  const QuickConnectButtons({
    super.key,
    required this.state,
    required this.onConnect,
    required this.onReconnect,
  });

  final AppState state;

  /// 连接（首次需要先扫描，交给上层决定怎么引导）。
  final VoidCallback onConnect;

  /// 重连：用记住的上次设备直接连。
  final VoidCallback onReconnect;

  @override
  Widget build(BuildContext context) {
    final bool connected = state.isConnected;
    final bool busy = state.isConnecting;
    return Row(
      children: <Widget>[
        Expanded(
          child: FilledButton.icon(
            onPressed: (!connected && !busy) ? onConnect : null,
            icon: const Icon(Icons.link, size: 18),
            label: const Text('连接'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: (connected && !busy) ? () => state.disconnect() : null,
            icon: const Icon(Icons.link_off, size: 18),
            label: const Text('断开'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: (!busy) ? onReconnect : null,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('重连'),
          ),
        ),
      ],
    );
  }
}
