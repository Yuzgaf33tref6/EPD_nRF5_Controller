import 'package:flutter/material.dart';

import '../state/app_state.dart';
import '../widgets/log_panel.dart';
import '../widgets/section_card.dart';
import 'canvas_screen.dart';
import 'connect_screen.dart';
import 'settings_screen.dart';

/// 首页：连接状态 + 入口 + 设备控制 + 日志。
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final AppState state = AppStateScope.of(context);
    final bool connected = state.isConnected;

    return Scaffold(
      appBar: AppBar(
        title: const Text('EPD Controller'),
        actions: <Widget>[
          IconButton(
            tooltip: '偏好设置',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => _open(context, const SettingsScreen()),
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: <Widget>[
                _ConnectionCard(state: state),
                const SizedBox(height: 12),
                SectionCard(
                  title: '入口',
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[
                      FilledButton.icon(
                        onPressed: () => _open(context, const ConnectScreen()),
                        icon: const Icon(Icons.bluetooth_searching),
                        label: const Text('搜索并连接'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => _open(context, const CanvasScreen()),
                        icon: const Icon(Icons.brush_outlined),
                        label: const Text('编辑并发送'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => _open(context, const SettingsScreen()),
                        icon: const Icon(Icons.tune),
                        label: const Text('传输参数'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                SectionCard(
                  title: '设备控制',
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[
                      OutlinedButton(
                        onPressed: connected
                            ? () => state.syncTime(clockMode: false)
                            : null,
                        child: const Text('同步时间（日历）'),
                      ),
                      OutlinedButton(
                        onPressed: connected
                            ? () => state.syncTime(clockMode: true)
                            : null,
                        child: const Text('同步时间（时钟）'),
                      ),
                      OutlinedButton(
                        onPressed: connected ? state.clearScreen : null,
                        child: const Text('清屏'),
                      ),
                      OutlinedButton(
                        onPressed: connected ? state.refreshScreen : null,
                        child: const Text('刷新'),
                      ),
                      OutlinedButton(
                        onPressed: connected ? state.sleepDevice : null,
                        child: const Text('睡眠'),
                      ),
                    ],
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

  void _open(BuildContext context, Widget screen) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (BuildContext context) => screen),
    );
  }
}

/// 顶部连接状态卡片。
class _ConnectionCard extends StatelessWidget {
  const _ConnectionCard({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool connected = state.isConnected;
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: connected
              ? theme.colorScheme.primaryContainer
              : theme.colorScheme.surfaceContainerHighest,
          child: Icon(
            connected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
            color: connected
                ? theme.colorScheme.onPrimaryContainer
                : theme.colorScheme.onSurfaceVariant,
          ),
        ),
        title: Text(connected ? state.connectedDevice!.name : '未连接设备'),
        subtitle: Text(
          connected
              ? '固件 ${state.firmwareVersionText} · 驱动 0x${state.driver.id.toUpperCase()} · '
                  '${state.canvasSize.width}×${state.canvasSize.height} · MTU ${state.mtu}'
              : '蓝牙层尚未接入，当前为模拟数据；进入「搜索并连接」可以体验完整流程',
        ),
        isThreeLine: !connected,
        trailing: connected
            ? TextButton(
                onPressed: state.disconnect,
                child: const Text('断开'),
              )
            : null,
      ),
    );
  }
}
