import 'package:flutter/material.dart';

import '../devices/epd_driver.dart';
import '../models/transfer_speed.dart';
import '../state/app_state.dart';
import '../widgets/log_panel.dart';
import '../widgets/section_card.dart';

/// 某个档位在当前 MTU 下实际能用的每块有效负载字节数。
int _chunkBytesFor(TransferSpeed speed, AppState state) {
  final int byMtu = state.writeMtu - 2;
  if (speed.isCustom) {
    return byMtu;
  }
  final int preset = speed.presetChunkBytes;
  return preset > byMtu ? byMtu : preset;
}

/// 档位的一句话说明。
String _speedHint(TransferSpeed speed) {
  switch (speed) {
    case TransferSpeed.conservative:
      return '18 字节，与 web 版默认值一致，最稳但最慢（400×300 三色约 1600 条写）。';
    case TransferSpeed.fast:
      return '64 字节，日常折中档。';
    case TransferSpeed.extreme:
      return '180 字节，最快；对固件接收缓冲最不友好，只在稳定后才用。';
    case TransferSpeed.custom:
      return '按下面的 MTU 滑块推算，适合自己试。';
  }
}

/// 偏好设置：外观、传输参数、调试开关。
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final AppState state = AppStateScope.of(context);
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('偏好设置')),
      body: Column(
        children: <Widget>[
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: <Widget>[
                SectionCard(
                  title: '外观',
                  child: Row(
                    children: <Widget>[
                      const Text('主题'),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButton<ThemeMode>(
                          isExpanded: true,
                          value: state.themeMode,
                          items: const <DropdownMenuItem<ThemeMode>>[
                            DropdownMenuItem<ThemeMode>(
                              value: ThemeMode.system,
                              child: Text('跟随系统'),
                            ),
                            DropdownMenuItem<ThemeMode>(
                              value: ThemeMode.light,
                              child: Text('浅色'),
                            ),
                            DropdownMenuItem<ThemeMode>(
                              value: ThemeMode.dark,
                              child: Text('深色'),
                            ),
                          ],
                          onChanged: (ThemeMode? mode) {
                            if (mode != null) {
                              state.setThemeMode(mode);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                SectionCard(
                  title: '传输参数',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          const Text('分块档位'),
                          const SizedBox(width: 12),
                          Expanded(
                            child: DropdownButton<TransferSpeed>(
                              isExpanded: true,
                              value: state.speed,
                              items: TransferSpeed.values
                                  .map(
                                    (TransferSpeed speed) =>
                                        DropdownMenuItem<TransferSpeed>(
                                      value: speed,
                                      child: Text(
                                        '${speed.label}（每块 '
                                        '${_chunkBytesFor(speed, state)} 字节）',
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (TransferSpeed? speed) {
                                if (speed != null) {
                                  state.setSpeed(speed);
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _speedHint(state.speed),
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'MTU ${state.mtu} · 每块 ${state.writeChunkBytes} 字节',
                        style: theme.textTheme.bodyMedium,
                      ),
                      if (state.speed.isCustom)
                        Slider(
                          value: state.mtu.toDouble(),
                          min: 20,
                          max: 247,
                          divisions: 227,
                          label: '${state.mtu}',
                          onChanged: (double value) =>
                              state.setMtu(value.round()),
                        ),
                      Text(
                        '交错块数 ${state.interleavedCount}',
                        style: theme.textTheme.bodyMedium,
                      ),
                      Slider(
                        value: state.interleavedCount.toDouble(),
                        min: 1,
                        max: 100,
                        divisions: 99,
                        label: '${state.interleavedCount}',
                        onChanged: (double value) =>
                            state.setInterleavedCount(value.round()),
                      ),
                      Text(
                        'MTU 来自固件 INIT 之后的通知（web 版默认 20）；'
                        '交错块数只在关闭「逐条等确认」时有意义。',
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: 8),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: state.rleSupported,
                        onChanged: state.setRleSupported,
                        title: const Text('假定固件支持 RLE'),
                        subtitle: const Text('固件版本 ≥ 0x16 时连接后会自动开启'),
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
                const SizedBox(height: 12),
                SectionCard(
                  title: '关于',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const Text('EPD Controller 0.1.0'),
                      const SizedBox(height: 4),
                      Text(
                        '协议、RLE、位打包、抖动、传图编排均已与 web 版逐字节对拍；'
                        '蓝牙层与画笔编辑尚未接入。',
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: state.clearLogs,
                        icon: const Icon(Icons.delete_sweep_outlined),
                        label: const Text('清空日志'),
                      ),
                    ],
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
