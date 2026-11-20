import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../services/ble_service.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';

/// 权限检查页：列出 App 需要的全部权限及当前状态，并提供申请 / 去设置。
///
/// 与「蓝牙诊断」的分工：这里只管**系统权限**（要不要给、给没给），
/// 蓝牙诊断管**链路**（能不能扫、连上了没、收到了什么通知）。
class PermissionScreen extends StatefulWidget {
  const PermissionScreen({super.key});

  @override
  State<PermissionScreen> createState() => _PermissionScreenState();
}

class _PermissionScreenState extends State<PermissionScreen> {
  List<AppPermissionStatus>? _statuses;
  bool _loading = true;
  bool _requesting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _refresh() async {
    if (!mounted) {
      return;
    }
    setState(() => _loading = true);
    final List<AppPermissionStatus> statuses =
        await AppStateScope.of(context).checkPermissions();
    if (!mounted) {
      return;
    }
    setState(() {
      _statuses = statuses;
      _loading = false;
    });
  }

  Future<void> _requestAll() async {
    setState(() => _requesting = true);
    final AppState state = AppStateScope.of(context);
    await state.retryPermissions();
    if (!mounted) {
      return;
    }
    setState(() => _requesting = false);
    await _refresh();
  }

  Future<void> _openSettings() async {
    await AppStateScope.of(context).openSystemSettings();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AppState state = AppStateScope.of(context);
    final List<AppPermissionStatus> statuses =
        _statuses ?? const <AppPermissionStatus>[];
    final List<AppPermissionStatus> missing = statuses
        .where((AppPermissionStatus s) => !s.granted)
        .toList(growable: false);
    final bool allGranted = !_loading && statuses.isNotEmpty && missing.isEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('权限检查'),
        actions: <Widget>[
          IconButton(
            tooltip: '刷新',
            onPressed: _loading ? null : _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        children: <Widget>[
          SectionCard(
            title: _loading ? '正在检查 …' : (allGranted ? '权限齐全' : '有权限没给'),
            icon: allGranted
                ? Icons.verified_user_outlined
                : Icons.gpp_maybe_outlined,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  _loading
                      ? '正在读取系统里的权限状态。'
                      : allGranted
                          ? '蓝牙相关的权限都已经给了，可以直接扫描并连接设备。'
                          : '有 ${missing.length} 项权限没给。'
                              '「附近的设备」是 Android 12 起扫描/连接蓝牙必须的权限，'
                              '缺失时扫描会静默返回空列表（系统不报错）。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: <Widget>[
                    FilledButton.tonalIcon(
                      onPressed: _requesting ? null : _requestAll,
                      icon: _requesting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.lock_open, size: 18),
                      label: Text(_requesting ? '正在申请 …' : '申请权限'),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: _openSettings,
                      icon: const Icon(Icons.settings_outlined, size: 18),
                      label: const Text('系统设置'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (!_loading && statuses.isNotEmpty) ...<Widget>[
            const SizedBox(height: 12),
            SectionCard(
              title: '权限清单',
              icon: Icons.checklist_rtl,
              child: Column(
                children: <Widget>[
                  for (final AppPermissionStatus status in statuses)
                    _PermissionRow(status: status),
                ],
              ),
            ),
          ],
          if (!_loading && statuses.isEmpty) ...<Widget>[
            const SizedBox(height: 12),
            const SectionCard(
              title: '权限清单',
              icon: Icons.checklist_rtl,
              child: EmptyHint(
                icon: Icons.report_gmailerrorred_outlined,
                text: '读不到权限状态。可能是系统版本过老，或者权限插件初始化失败。',
              ),
            ),
          ],
          const SizedBox(height: 12),
          SectionCard(
            title: '说明',
            icon: Icons.info_outline,
            child: Text(
              '· Android 12 及以上：需要「附近的设备」的扫描与连接两项。\n'
              '· Android 11 及以下：扫描蓝牙必须同时打开定位权限。\n'
              '· 被永久拒绝（「不再询问」）时，系统不会再弹窗，'
              '需要点「系统设置」手动打开。\n'
              '· 联网权限只有「检查更新」用到，属于安装时自动授予，不用手动申请。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.6,
              ),
            ),
          ),
          const SizedBox(height: 12),
          SectionCard(
            title: '蓝牙状态',
            icon: Icons.bluetooth,
            child: Column(
              children: <Widget>[
                InfoRow(label: '链路', value: state.adapterStatusText),
                InfoRow(
                  label: '连接',
                  value: state.isConnected
                      ? (state.connectedDevice?.name ?? '已连接')
                      : '未连接',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PermissionRow extends StatelessWidget {
  const _PermissionRow({required this.status});

  final AppPermissionStatus status;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final (IconData icon, Color color, String text) = switch (status) {
      AppPermissionStatus(alwaysGranted: true) => (
          Icons.remove_circle_outline,
          theme.colorScheme.outline,
          '此系统版本不需要',
        ),
      AppPermissionStatus(granted: true) => (
          Icons.check_circle,
          theme.colorScheme.primary,
          '已授予',
        ),
      AppPermissionStatus(permanentlyDenied: true) => (
          Icons.block,
          theme.colorScheme.error,
          '已被永久拒绝，需去系统设置',
        ),
      _ => (
          Icons.error_outline,
          Colors.orange.shade800,
          '未授予',
        ),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        status.name,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Text(
                      text,
                      style: theme.textTheme.labelSmall?.copyWith(color: color),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '${status.androidName} · ${status.status.name}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontFamily: 'monospace',
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  status.reason,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
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
