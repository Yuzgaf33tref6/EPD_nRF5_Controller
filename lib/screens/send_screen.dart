import 'package:flutter/material.dart';

import '../state/app_state.dart';
import '../widgets/common.dart';
import '../widgets/image_preview.dart';
import 'debug_commands_screen.dart';
import 'image_send_screen.dart';

/// 发送页：一级放设备指令，图像发送作为二级页面的入口。
///
/// 图像预览要跑抖动 + 位打包（400×300 在百毫秒量级），放在一级页面会让每次
/// 切换标签都卡一下，所以拆成独立页面按需计算。
class SendScreen extends StatelessWidget {
  const SendScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final AppState state = AppStateScope.of(context);
    final bool connected = state.isConnected;
    return Scaffold(
      appBar: AppBar(title: const Text('发送')),
      body: Column(
        children: <Widget>[
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
              children: <Widget>[
                if (!connected) ...<Widget>[
                  _ConnectHint(state: state),
                  const SizedBox(height: 12),
                ],
                SectionCard(
                  title: '设备指令',
                  icon: Icons.tune,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: FilledButton.tonalIcon(
                              onPressed: connected
                                  ? () => state.syncTime(clockMode: false)
                                  : null,
                              icon: const Icon(Icons.event, size: 18),
                              label: const Text('0x20 同步时间'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: connected
                                  ? () => state.syncTime(clockMode: true)
                                  : null,
                              icon: const Icon(Icons.schedule, size: 18),
                              label: const Text('0x20 时钟模式'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed:
                                  connected ? () => state.clearScreen() : null,
                              icon: const Icon(Icons.cleaning_services_outlined,
                                  size: 18),
                              label: const Text('0x02 清屏'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed:
                                  connected ? () => state.refreshScreen() : null,
                              icon: const Icon(Icons.refresh, size: 18),
                              label: const Text('0x05 刷新'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed:
                                  connected ? () => state.sleepDevice() : null,
                              icon: const Icon(Icons.bedtime_outlined, size: 18),
                              label: const Text('0x06 睡眠'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '时钟模式会整屏刷新以消除残影，建议只在需要时使用。',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color:
                                  Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _ImageEntryCard(state: state),
                const SizedBox(height: 12),
                SectionCard(
                  title: '调试',
                  icon: Icons.build_outlined,
                  child: SettingTile(
                    icon: Icons.terminal,
                    title: '设备指令 · 调试',
                    subtitle: '直接发 0x03 / 0x04 / 0x21 / 0x90 / 0x91 / 0x92 / 0x99，'
                        '以及纯色测试',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const DebugCommandsScreen(),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SectionCard(
                  title: '当前参数',
                  icon: Icons.settings_ethernet,
                  child: Column(
                    children: <Widget>[
                      InfoRow(
                        label: '驱动',
                        value: '0x${state.driver.id.toUpperCase()} · '
                            '${state.driver.label}',
                      ),
                      InfoRow(
                        label: '画布',
                        value: '${state.canvasSize.width}×'
                            '${state.canvasSize.height}',
                      ),
                      InfoRow(
                        key: const Key('send-summary'),
                        label: '传图',
                        value: state.transferSummary,
                      ),
                      if (state.warnings.isNotEmpty)
                        ...state.warnings.map(
                          (String warning) => Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              warning,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          DeviceStatusBar(state: state),
        ],
      ),
    );
  }
}

/// 未连接时的提示条。
class _ConnectHint extends StatelessWidget {
  const _ConnectHint({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.info_outline, color: theme.colorScheme.onSecondaryContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '未连接设备，指令与传图都不可用。回到首页连接墨水屏即可。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSecondaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 图像发送入口卡片：显示一个小尺寸预览 + 进入二级页面。
///
/// 这里的缩略图**用原图**而不是抖动结果：抖动要在后台 isolate 里算几十毫秒，
/// 而首页/发送页只是给个「有图」的指示，没必要为了 72×54 的小图付这个代价
/// —— 这正是之前一进发送页就发卡的来源之一。
class _ImageEntryCard extends StatelessWidget {
  const _ImageEntryCard({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const ImageSendScreen()),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
          child: Row(
            children: <Widget>[
              SizedBox(
                width: 72,
                height: 54,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: RgbaImagePreview(
                    image: state.sourceImage,
                    maxWidth: 72,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      '图像发送',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '画布编辑 · 抖动预览 · 导入图片 · 发送到屏幕',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: theme.colorScheme.outline),
            ],
          ),
        ),
      ),
    );
  }
}
