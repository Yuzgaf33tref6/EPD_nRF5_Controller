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
    final int custom = state.customChunkBytes;
    return custom > byMtu ? byMtu : custom;
  }
  if (speed.isMax) {
    return byMtu;
  }
  final int preset = speed.presetChunkBytes;
  return preset > byMtu ? byMtu : preset;
}

/// 档位的一句话说明。
String _speedHint(TransferSpeed speed) {
  switch (speed) {
    case TransferSpeed.stable:
      return '18 字节，与 web 版默认值一致，最稳但最慢（400×300 三色约 1600 条写）。';
    case TransferSpeed.normal:
      return '64 字节，日常推荐。';
    case TransferSpeed.fast:
      return '128 字节，明显快一截。';
    case TransferSpeed.max:
      return '吃满单包上限（MTU 247 时是 242 字节），真机已验证稳定。';
    case TransferSpeed.custom:
      return '自己填每块字节数，上限随 MTU 变化。';
  }
}

/// 自定义分块滑块的位置（必须落在 min..max 之间，否则 Slider 会断言失败）。
double _customSliderValue(AppState state) {
  final double max = (state.writeMtu - 2).toDouble();
  final double value = state.customChunkBytes.toDouble();
  if (value < 8) {
    return 8;
  }
  return value > max ? max : value;
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
                        'MTU ${state.mtu} · 单包有效负载上限 '
                        '${state.writeMtu} · 每块 ${state.writeChunkBytes} 字节',
                        style: theme.textTheme.bodyMedium,
                      ),
                      if (state.speed.isCustom)
                        Slider(
                          value: _customSliderValue(state),
                          min: 8,
                          max: (state.writeMtu - 2).toDouble(),
                          divisions: state.writeMtu - 10,
                          label: '${state.customChunkBytes}',
                          onChanged: (double value) =>
                              state.setCustomChunkBytes(value.round()),
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
                        'MTU 是单包（ATT）大小，与分块是两回事：'
                        '连接后主动协商到 ${state.mtu}，一条写指令最多能带 '
                        '${state.writeMtu} 字节（MTU-3）；再减掉命令字与 flag 就是 '
                        '${state.writeMtu - 2} 字节有效负载。\n'
                        '注意固件在通知里报的“mtu=244”其实是它自己能收的负载上限'
                        '（MTU-3），不是 MTU 本身，所以会和这里的 ${state.mtu} 差 3。',
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: 8),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: state.rleSupported,
                        onChanged: state.setRleSupported,
                        title: const Text('强制启用 RLE 压缩传输'),
                        subtitle: const Text(
                          '默认只认固件通知里的 rle=1（与 web 版一致）；'
                          '固件不支持时强行打开会让屏幕刷成乱块',
                        ),
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
