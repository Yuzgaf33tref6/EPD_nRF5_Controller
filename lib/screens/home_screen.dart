import 'package:flutter/material.dart';

import '../services/app_info.dart';
import '../services/ble_service.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';
import '../widgets/connection_status_card.dart';
import '../widgets/image_preview.dart';
import 'diagnostics_screen.dart' show describeRssi;
import 'logs_screen.dart';
import 'permission_screen.dart';
import 'releases_screen.dart';

/// 首页：连接状态大卡片 + 快捷按钮 + 折叠的设备扫描 + 应用与设备信息。
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  /// 设备扫描区是否展开：默认收起，未连接时自动展开（用户确认过的交互）。
  bool? _expandedOverride;

  bool _autoExpandApplied = false;

  /// 上一次看到的连接状态，用来在「刚连上」时自动收起扫描区。
  bool _wasConnected = false;

  @override
  Widget build(BuildContext context) {
    final AppState state = AppStateScope.of(context);
    // 连上之后自动收起扫描区；断开之后恢复成「未连接时自动展开」。
    // 注意：这里只在**连接状态发生变化**时才改动 _expandedOverride，
    // 否则每次重建都会把用户手动折叠/展开的选择覆盖掉。
    // （之前写成无条件 `else { _expandedOverride = null; }`，
    //   导致未连接时用户点了折叠头又会立刻被展开回来。）
    final bool connected = state.isConnected;
    if (connected != _wasConnected) {
      _wasConnected = connected;
      _expandedOverride = connected ? false : null;
    }
    final bool expanded = _expandedOverride ?? !connected;
    if (!_autoExpandApplied) {
      _autoExpandApplied = true;
      state.ensurePermissionsOnce();
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('EPD Controller'),
        actions: <Widget>[
          IconButton(
            tooltip: '日志',
            icon: const Icon(Icons.receipt_long_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const LogsScreen()),
            ),
          ),
          IconButton(
            tooltip: '关于与更新',
            icon: const Icon(Icons.info_outline),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const ReleasesScreen()),
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
                ConnectionStatusCard(state: state),
                const SizedBox(height: 10),
                QuickConnectButtons(
                  state: state,
                  onConnect: () {
                    setState(() => _expandedOverride = true);
                    _startScanIfNeeded(state);
                  },
                  onReconnect: () => _reconnect(state),
                ),
                if (state.permissionDenied) ...<Widget>[
                  const SizedBox(height: 10),
                  _PermissionBanner(
                    onRetry: () => state.retryPermissions(),
                    onOpenDetail: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const PermissionScreen(),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                _ScanSection(
                  state: state,
                  expanded: expanded,
                  onToggle: () =>
                      setState(() => _expandedOverride = !expanded),
                ),
                const SizedBox(height: 14),
                _AppInfoSection(state: state),
                const SizedBox(height: 14),
                _DeviceInfoSection(state: state),
              ],
            ),
          ),
          DeviceStatusBar(state: state),
        ],
      ),
    );
  }

  void _startScanIfNeeded(AppState state) {
    if (state.isScanning) {
      return;
    }
    state.scan();
  }

  Future<void> _reconnect(AppState state) async {
    final String? id = state.lastDeviceId;
    if (id == null) {
      setState(() => _expandedOverride = true);
      await state.scan();
      return;
    }
    await state.connect(
      EpdBleDevice(
        id: id,
        name: state.lastDeviceName ?? '上次的设备',
        rssi: 0,
      ),
    );
  }
}

/// 权限被拒时的横幅提示。
class _PermissionBanner extends StatelessWidget {
  const _PermissionBanner({
    required this.onRetry,
    required this.onOpenDetail,
  });

  final VoidCallback onRetry;

  /// 打开「权限检查」页，看具体是哪条权限没给。
  final VoidCallback onOpenDetail;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.warning_amber_rounded,
              color: theme.colorScheme.onErrorContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '没有蓝牙权限就扫不到设备，也连不上墨水屏。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onErrorContainer,
              ),
            ),
          ),
          TextButton(onPressed: onOpenDetail, child: const Text('查看')),
          TextButton(onPressed: onRetry, child: const Text('重新申请')),
        ],
      ),
    );
  }
}

/// 折叠的设备扫描与选择区。
class _ScanSection extends StatelessWidget {
  const _ScanSection({
    required this.state,
    required this.expanded,
    required this.onToggle,
  });

  final AppState state;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Column(
        children: <Widget>[
          InkWell(
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
              child: Row(
                children: <Widget>[
                  Icon(Icons.sensors, size: 18,
                      color: theme.colorScheme.primary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '连接设备',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  Text(
                    state.devices.isEmpty
                        ? (expanded ? '点此收起' : '点此展开')
                        : '扫描到 ${state.devices.length} 个设备',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Icon(expanded ? Icons.expand_less : Icons.expand_more),
                ],
              ),
            ),
          ),
          if (expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  FilledButton.tonalIcon(
                    onPressed:
                        state.isScanning ? null : () => state.scan(),
                    icon: state.isScanning
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.search, size: 18),
                    label: Text(state.isScanning ? '正在扫描 …' : '扫描附近设备'),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '扫描使用系统蓝牙；如果扫不到，确认墨水屏已按唤醒键、'
                    '没连着别的手机，并已允许「附近的设备」权限。',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (state.devices.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 10),
                    for (final EpdBleDevice device in state.devices)
                      _DeviceTile(device: device, state: state),
                  ] else if (!state.isScanning)
                    const EmptyHint(
                      icon: Icons.bluetooth_searching,
                      text: '还没有发现设备',
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _DeviceTile extends StatelessWidget {
  const _DeviceTile({required this.device, required this.state});

  final EpdBleDevice device;
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final bool isCurrent = state.connectedDevice?.id == device.id;
    final ThemeData theme = Theme.of(context);
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        isCurrent ? Icons.bluetooth_connected : Icons.bluetooth,
        color: isCurrent ? theme.colorScheme.primary : theme.colorScheme.outline,
      ),
      title: Text(
        device.name.isEmpty ? '(未命名设备)' : device.name,
        style: theme.textTheme.bodyMedium,
      ),
      subtitle: Text(
        '${device.id} · 信号 ${device.rssi} dBm',
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: isCurrent
          ? OutlinedButton(
              onPressed: () => state.disconnect(),
              child: const Text('断开'),
            )
          : FilledButton.tonal(
              onPressed: state.isConnecting || state.isConnected
                  ? null
                  : () => state.connect(device),
              child: const Text('连接'),
            ),
    );
  }
}

/// 应用信息（版本、作者、更新日志、检查更新）。
class _AppInfoSection extends StatelessWidget {
  const _AppInfoSection({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: '应用信息',
      icon: Icons.info_outline,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SettingTile(
            icon: Icons.tag,
            title: '${AppVersion.appName} ${AppVersion.fullVersion}',
            subtitle: '作者：${AppVersion.authors}',
            trailing: const SizedBox.shrink(),
          ),
          SettingTile(
            icon: Icons.history,
            title: '更新日志',
            subtitle: '查看每个版本改了什么',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const ReleaseNotesScreen(),
              ),
            ),
          ),
          SettingTile(
            icon: Icons.cloud_download_outlined,
            title: '检查更新',
            subtitle: '对比 GitHub Releases 上的最新版本',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const ReleasesScreen()),
            ),
          ),
        ],
      ),
    );
  }
}

/// 当前设备信息（驱动、画布、固件、MTU 等）。
class _DeviceInfoSection extends StatelessWidget {
  const _DeviceInfoSection({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final String firmware = state.isConnected ? state.firmwareVersionText : '—';
    return SectionCard(
      title: '运行设备信息',
      icon: Icons.developer_board_outlined,
      child: Column(
        children: <Widget>[
          InfoRow(label: '连接状态', value: state.isConnected ? '已连接' : '未连接'),
          InfoRow(
            label: '设备',
            value: state.connectedDevice?.name ?? '—',
          ),
          InfoRow(label: '固件版本', value: firmware, monospace: true),
          InfoRow(
            label: '信号强度',
            value: state.isConnected
                ? (state.liveRssi == null
                    ? '读取中 …'
                    : '${state.liveRssi} dBm（${describeRssi(state.liveRssi!)}）')
                : '—',
          ),
          InfoRow(
            label: '驱动',
            value: '0x${state.driver.id.toUpperCase()} · ${state.driver.controller}',
            monospace: true,
          ),
          InfoRow(
            label: '画布',
            value: '${state.canvasSize.width}×${state.canvasSize.height}',
          ),
          InfoRow(
            label: '颜色模式',
            value: state.colorMode.jsName,
            monospace: true,
          ),
          InfoRow(label: '引脚', value: state.pinsText, monospace: true),
          InfoRow(
            label: 'MTU',
            value: '${state.mtu}（每块 ${state.writeChunkBytes} 字节）',
          ),
        ],
      ),
    );
  }
}
