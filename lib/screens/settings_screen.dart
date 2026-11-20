import 'package:flutter/material.dart';

import '../devices/epd_driver.dart';
import '../models/transfer_speed.dart';
import '../state/app_state.dart';
import '../widgets/app_info_card.dart';
import '../widgets/common.dart';
import 'diagnostics_screen.dart';
import 'permission_screen.dart';
import 'plane_check_screen.dart';
import 'solid_color_screen.dart';

/// 设置页：应用 / 传输 / 驱动 / 诊断 / 关于 五组。
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final AppState state = AppStateScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: Column(
        children: <Widget>[
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
              children: <Widget>[
                const GroupHeader(title: '应用'),
                _AppGroup(state: state),
                const GroupHeader(title: '传输'),
                _TransferGroup(state: state),
                const GroupHeader(title: '驱动'),
                _DriverGroup(state: state),
                const GroupHeader(title: '诊断'),
                _DiagnosticsGroup(state: state),
                const GroupHeader(title: '关于'),
                _AboutGroup(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AppGroup extends StatelessWidget {
  const _AppGroup({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return SectionCard(
      title: '外观',
      icon: Icons.palette_outlined,
      dense: true,
      child: Column(
        children: <Widget>[
          DropdownButtonFormField<ThemeMode>(
            initialValue: state.themeMode,
            decoration: const InputDecoration(
              labelText: '主题',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: const <DropdownMenuItem<ThemeMode>>[
              DropdownMenuItem<ThemeMode>(
                  value: ThemeMode.system, child: Text('跟随系统')),
              DropdownMenuItem<ThemeMode>(
                  value: ThemeMode.light, child: Text('浅色')),
              DropdownMenuItem<ThemeMode>(
                  value: ThemeMode.dark, child: Text('深色')),
            ],
            onChanged: (ThemeMode? value) {
              if (value != null) {
                state.setThemeMode(value);
              }
            },
          ),
          const SizedBox(height: 6),
          Text(
            '主题选择会被保存，下次启动直接生效。',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _TransferGroup extends StatelessWidget {
  const _TransferGroup({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final int? rssi = state.isConnected ? state.liveRssi : null;
    return Column(
      children: <Widget>[
        SectionCard(
          title: 'MTU',
          icon: Icons.straighten,
          dense: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              InfoRow(
                label: '当前',
                value: '${state.mtu}（每块 ${state.writeChunkBytes} 字节）',
              ),
              InfoRow(
                label: '写请求',
                value: '${state.writeMtu - 2} 字节有效负载上限',
              ),
              if (rssi != null) InfoRow(label: '信号', value: '$rssi dBm'),              const SizedBox(height: 6),
              Text(
                '说明：固件通知里的 mtu=244 是「特征值最大长度」，即 GATT MTU - 3；'
                'App 连接时主动协商到 247，真机上一般就是 247。'
                '两者是同一个链路的不同说法，不是矛盾。',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      '手动设置 MTU（20 – 247）',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  SizedBox(
                    width: 120,
                    child: Slider(
                      value: state.mtu.toDouble().clamp(20, 247),
                      min: 20,
                      max: 247,
                      divisions: 227,
                      label: '${state.mtu}',
                      onChanged: (double value) =>
                          state.setMtu(value.round()),
                    ),
                  ),
                ],
              ),
              Text(
                '改动越大不一定越快：超过链路对手能接受的范围会掉包或断连，'
                '一般保持自动协商的 247 即可。',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        SectionCard(
          title: '分块档位',
          icon: Icons.straighten_outlined,
          dense: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: <Widget>[
                  for (final TransferSpeed speed in TransferSpeed.values)
                    ChoiceChip(
                      label: Text(
                        speed.isCustom
                            ? '${speed.label}（${state.customChunkBytes}）'
                            : '${speed.label}',
                      ),
                      selected: state.speed == speed,
                      onSelected: (_) => state.setSpeed(speed),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              if (state.speed.isCustom) ...<Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        '自定义每块字节数（8 – ${state.writeMtu - 2}）',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                    SizedBox(
                      width: 130,
                      child: Slider(
                        value: state.customChunkBytes
                            .toDouble()
                            .clamp(8, state.writeMtu - 2),
                        min: 8,
                        max: (state.writeMtu - 2).toDouble(),
                        divisions: (state.writeMtu - 2) - 8,
                        label: '${state.customChunkBytes}',
                        onChanged: (double value) =>
                            state.setCustomChunkBytes(value.round()),
                      ),
                    ),
                  ],
                ),
              ],
              Text(
                '一次传图会被切成若干块依次发送。块小更稳、块大更快；'
                '实测 MTU 247 下每块 242 字节可以稳定传完。',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        SectionCard(
          title: '交错块数',
          icon: Icons.swap_horiz,
          dense: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      '每 ${state.interleavedCount} 块做一次往返',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  SizedBox(
                    width: 130,
                    child: Slider(
                      value: state.interleavedCount.toDouble().clamp(1, 100),
                      min: 1,
                      max: 100,
                      divisions: 99,
                      label: '${state.interleavedCount}',
                      onChanged: (double value) =>
                          state.setInterleavedCount(value.round()),
                    ),
                  ),
                ],
              ),
              Text(
                'App 现在每条写指令都等设备确认，这个值只作为统计提示；'
                '与 web 版保持一致默认 50。',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4),
              SettingSwitch(
                icon: Icons.compress,
                title: 'RLE 压缩传输',
                subtitle: '固件在连接时上报 rle=1 才会自动启用；'
                    '勾选这里是强制开启，固件不支持时会刷出乱块。',
                value: state.rleSupported,
                onChanged: state.setRleSupported,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DriverGroup extends StatelessWidget {
  const _DriverGroup({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return SectionCard(
      title: '驱动选择',
      icon: Icons.developer_board,
      dense: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SegmentedButton<DriverSelectionMode>(
            showSelectedIcon: false,
            segments: const <ButtonSegment<DriverSelectionMode>>[
              ButtonSegment<DriverSelectionMode>(
                  value: DriverSelectionMode.auto, label: Text('自动')),
              ButtonSegment<DriverSelectionMode>(
                  value: DriverSelectionMode.manual, label: Text('手动')),
            ],
            selected: <DriverSelectionMode>{state.driverMode},
            onSelectionChanged: (Set<DriverSelectionMode> value) =>
                state.setDriverMode(value.first),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: state.driver.id,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: '驱动',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: <DropdownMenuItem<String>>[
              for (final EpdDriver driver in kEpdDrivers)
                DropdownMenuItem<String>(
                  value: driver.id,
                  child: Text(
                    '0x${driver.id.toUpperCase()} · ${driver.label}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (String? id) {
              if (id == null || id == state.driver.id) {
                return;
              }
              final EpdDriver? driver = driverById(id);
              if (driver != null) {
                state.setDriver(driver);
                if (state.driverMode == DriverSelectionMode.auto) {
                  state.setDriverMode(DriverSelectionMode.manual);
                }
              }
            },
          ),
          const SizedBox(height: 6),
          Text(
            '自动：连上后按固件上报的驱动号匹配（推荐）。手动：忽略固件上报，'
            '始终用这里选中的驱动 —— 固件没上报或上报不对时才用。',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          SettingSwitch(
            icon: Icons.notifications_off_outlined,
            title: '不再提示「驱动可能错误」',
            subtitle: '没有收到固件配置通知时会提示手动确认驱动。',
            value: state.driverWarningMuted,
            onChanged: state.setDriverWarningMuted,
          ),
        ],
      ),
    );
  }
}

class _DiagnosticsGroup extends StatelessWidget {
  const _DiagnosticsGroup({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: '诊断工具',
      icon: Icons.bug_report_outlined,
      dense: true,
      child: Column(
        children: <Widget>[
          SettingSwitch(
            icon: Icons.terminal,
            title: '详细传输日志',
            subtitle: '把每条写指令与收到的通知打到 logcat（排查用）。',
            value: state.verboseTransfers,
            onChanged: state.setVerboseTransfers,
          ),
          SettingTile(
            icon: Icons.verified_user_outlined,
            title: '权限检查',
            subtitle: '查看并申请本应用需要的全部系统权限',
            onTap: () => _push(context, const PermissionScreen()),
          ),
          SettingTile(
            icon: Icons.monitor_heart_outlined,
            title: '蓝牙诊断',
            subtitle: '适配器状态、原始通知、链路排查',
            onTap: () => _push(context, const DiagnosticsScreen()),
          ),
          SettingTile(
            icon: Icons.palette_outlined,
            title: '纯色测试',
            subtitle: '整屏发黑/白/红，验证链路与平面',
            onTap: () => _push(context, const SolidColorScreen()),
          ),
          SettingTile(
            icon: Icons.flip,
            title: '平面排查',
            subtitle: '调换黑白/红白平面、红平面取反',
            onTap: () => _push(context, const PlaneCheckScreen()),
          ),
          SettingTile(
            icon: Icons.receipt_long_outlined,
            title: '日志查看器',
            subtitle: '完整运行日志',
            onTap: () => _push(context, const LogsScreen()),
          ),
        ],
      ),
    );
  }

  void _push(BuildContext context, Widget screen) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => screen),
    );
  }
}

class _AboutGroup extends StatelessWidget {
  const _AboutGroup();

  @override
  Widget build(BuildContext context) {
    // 与「关于与更新」页共用同一个区块，避免两处文案/字段漂移。
    return const AppInfoCard(showActions: true);
  }
}

