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
                      // 第一栏：时间同步（0x20，两种模式）。
                      _CommandSection(
                        title: '0x20 时间同步',
                        children: <Widget>[
                          _CommandButton(
                            code: '0x20',
                            label: '日历模式',
                            filled: true,
                            onPressed: connected
                                ? () => state.syncTime(clockMode: false)
                                : null,
                          ),
                          _CommandButton(
                            code: '0x20',
                            label: '时钟模式',
                            onPressed: connected
                                ? () => state.syncTime(clockMode: true)
                                : null,
                          ),
                        ],
                        footer: '时钟模式会整屏刷新以消除残影，建议只在需要时使用。',
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 10),
                        child: Divider(height: 1),
                      ),
                      // 第二栏：常用指令（0x0X）。一行三个，字号比上面小一点，
                      // 避免「0x02 清屏」被挤成两行。
                      _CommandSection(
                        title: '常用',
                        compact: true,
                        children: <Widget>[
                          _CommandButton(
                            code: '0x02',
                            label: '清屏',
                            compact: true,
                            onPressed:
                                connected ? () => state.clearScreen() : null,
                          ),
                          _CommandButton(
                            code: '0x05',
                            label: '刷新',
                            compact: true,
                            onPressed:
                                connected ? () => state.refreshScreen() : null,
                          ),
                          _CommandButton(
                            code: '0x06',
                            label: '睡眠',
                            compact: true,
                            onPressed:
                                connected ? () => state.sleepDevice() : null,
                          ),
                        ],
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

/// 设备指令里的一栏：小标题 + 一行按钮 + 可选的小字说明。
///
/// 每栏最多三列；[compact] 时字号小一点，用来塞下 0x0X 那三个常用指令。
class _CommandSection extends StatelessWidget {
  const _CommandSection({
    required this.title,
    required this.children,
    this.footer,
    this.compact = false,
  });

  final String title;
  final List<Widget> children;
  final String? footer;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          title,
          style: compact
              ? theme.textTheme.labelMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)
              : theme.textTheme.labelLarge
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        Row(
          children: <Widget>[
            for (int i = 0; i < children.length; i++) ...<Widget>[
              if (i > 0) const SizedBox(width: 8),
              Expanded(child: children[i]),
            ],
          ],
        ),
        if (footer != null) ...<Widget>[
          const SizedBox(height: 6),
          Text(
            footer!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

/// 带指令编号的按钮：编号在上（等宽小字），名称在下，避免长中文被挤断行。
class _CommandButton extends StatelessWidget {
  const _CommandButton({
    required this.code,
    required this.label,
    required this.onPressed,
    this.filled = false,
    this.compact = false,
  });

  final String code;
  final String label;
  final VoidCallback? onPressed;
  final bool filled;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Widget content = Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          code,
          style: (compact ? theme.textTheme.labelSmall : theme.textTheme.labelMedium)
              ?.copyWith(
            fontFamily: 'monospace',
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: compact ? theme.textTheme.labelLarge : theme.textTheme.bodyMedium,
        ),
      ],
    );
    final EdgeInsets padding = compact
        ? const EdgeInsets.symmetric(horizontal: 4, vertical: 6)
        : const EdgeInsets.symmetric(horizontal: 8, vertical: 8);

    if (filled) {
      return FilledButton.tonal(
        onPressed: onPressed,
        style: FilledButton.styleFrom(padding: padding),
        child: content,
      );
    }
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(padding: padding),
      child: content,
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
