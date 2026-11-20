import 'package:flutter/material.dart';

import '../state/app_state.dart';
import '../widgets/common.dart';
import 'permission_screen.dart';

/// 蓝牙诊断页：链路状态、诊断动作、原始通知。系统权限集中在「权限检查」页。
class DiagnosticsScreen extends StatelessWidget {
  const DiagnosticsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final AppState state = AppStateScope.of(context);
    final ThemeData theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('蓝牙诊断')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
        children: <Widget>[
          SectionCard(
            title: '链路状态',
            icon: Icons.lan_outlined,
            dense: true,
            child: Column(
              children: <Widget>[
                InfoRow(label: '蓝牙', value: state.adapterStatusText),
                InfoRow(
                  label: '连接',
                  value: state.isConnected
                      ? (state.connectedDevice?.name ?? '已连接')
                      : (state.isConnecting ? '连接中 …' : '未连接'),
                ),
                InfoRow(label: '固件', value: state.firmwareVersionText),
                InfoRow(label: '引脚', value: state.pinsText),
                InfoRow(
                  label: 'MTU',
                  value: '${state.mtu}（每块 ${state.writeChunkBytes} 字节）',
                ),
                InfoRow(label: 'RLE', value: state.rleSupported ? '开' : '关'),
                InfoRow(label: '已写入', value: '${state.writesSent} 条'),
              ],
            ),
          ),
          const SizedBox(height: 10),
          SectionCard(
            title: '诊断动作',
            icon: Icons.play_circle_outline,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    OutlinedButton(
                      onPressed: state.refreshDiagnostics,
                      child: const Text('刷新蓝牙状态'),
                    ),
                    OutlinedButton(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const PermissionScreen(),
                        ),
                      ),
                      child: const Text('权限检查'),
                    ),
                    OutlinedButton(
                      onPressed:
                          state.isConnected ? state.sendDiagnosticInit : null,
                      child: const Text('发送 INIT 测试'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '扫描不到设备时依次检查：蓝牙已打开；「权限检查」页里'
                  '「附近的设备」已授权；墨水屏已开机（按一下唤醒）；没有别的手机连着它。',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          SectionCard(
            title: '收到的通知（最新在上）',
            icon: Icons.notifications_active_outlined,
            child: state.notificationLog.isEmpty
                ? const EmptyHint(
                    icon: Icons.notifications_off_outlined,
                    text: '还没有收到通知；连接设备并发 INIT 后再看这里',
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      for (final String line in state.notificationLog.reversed)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: SelectableText(
                            line,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12,
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
