import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/app_info.dart';
import '../screens/logs_screen.dart' show ReleaseNotesScreen;
import '../screens/releases_screen.dart' show ReleasesScreen;
import 'common.dart';

/// 作者主页（用户要求：界面上只显示名字，链接藏在点击里）。
const String kAuthorUrl = 'https://github.com/Yuzgaf33tref6';

/// 「软件信息」区块：设置页与「关于与更新」页共用同一份实现。
///
/// 之前两处各写一份，内容会漂移（设置的版本说明写死了 0.2.0 的描述，而关于页
/// 是从 `AppVersion` 取的）。现在统一从这里渲染，改一处两边同步。
///
/// [actions] 为 null 时不显示底部按钮行（关于页自己有更丰富的操作区）。
class AppInfoCard extends StatelessWidget {
  const AppInfoCard({super.key, this.showActions = true, this.dense = true});

  /// 是否显示「更新日志 / 检查更新」按钮。
  final bool showActions;

  /// 紧凑排版（设置页嵌在分组里时用）。
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return SectionCard(
      title: AppVersion.appName,
      icon: Icons.auto_stories_outlined,
      dense: dense,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          InfoRow(label: '版本', value: AppVersion.fullVersion),
          InfoRow(
            label: '作者',
            value: AppVersion.authors,
            onTap: () => showLinkActions(
              context,
              kAuthorUrl,
              '作者主页',
            ),
            onCopy: (String v) => copyToClipboard(context, v),
          ),
          LinkRow(
            label: '仓库',
            url: AppVersion.repoUrl,
            onOpen: () =>
                showLinkActions(context, AppVersion.repoUrl, '项目仓库'),
            onCopy: () => copyToClipboard(context, AppVersion.repoUrl),
          ),
          LinkRow(
            label: '固件',
            url: AppVersion.upstreamUrl,
            onOpen: () => showLinkActions(
              context,
              AppVersion.upstreamUrl,
              '上游固件项目',
            ),
            onCopy: () => copyToClipboard(context, AppVersion.upstreamUrl),
          ),
          const SizedBox(height: 10),
          Text(
            '把 EPD-nRF5 的 Web 上位机搬到 Android：通过蓝牙（BLE）给墨水屏'
            '同步时间、清屏、传图。图像链路与 web 版逐字节对拍，'
            '抖动、位打包、传图分块全部一致。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.55,
            ),
          ),
          if (showActions) ...<Widget>[
            const SizedBox(height: 10),
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const ReleaseNotesScreen(),
                      ),
                    ),
                    icon: const Icon(Icons.history, size: 18),
                    label: const Text('更新日志'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const ReleasesScreen(),
                      ),
                    ),
                    icon: const Icon(Icons.cloud_download_outlined, size: 18),
                    label: const Text('检查更新'),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          Text(
            '许可证：GPL-3.0 · 固件与 Web 上位机来自 tsl0922/EPD-nRF5',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// 带「复制」图标按钮的链接行。
///
/// 链接用等宽字体自动折行，按钮固定在最右侧，多行时也对得齐。
class LinkRow extends StatelessWidget {
  const LinkRow({
    super.key,
    required this.label,
    required this.url,
    required this.onOpen,
    required this.onCopy,
  });

  final String label;
  final String url;
  final VoidCallback onOpen;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    return InfoRow(
      label: label,
      value: url,
      monospace: true,
      onTap: onOpen,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          IconButton(
            tooltip: '复制链接',
            visualDensity: VisualDensity.compact,
            iconSize: 18,
            onPressed: onCopy,
            icon: const Icon(Icons.copy_outlined),
          ),
        ],
      ),
    );
  }
}

/// 把文本复制到剪贴板，并用 SnackBar 告诉用户复制了什么。
Future<void> copyToClipboard(BuildContext context, String text) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (!context.mounted) {
    return;
  }
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text('已复制：$text'),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2),
    ),
  );
}

/// 打开链接前先确认一次，避免误触跳走。
///
/// 当前构建不引入 `url_launcher`（会带一个原生依赖），所以对话框里给的是
/// 「复制链接」——复制后用户可以自己粘到浏览器。
Future<void> showLinkActions(
  BuildContext context,
  String url,
  String title,
) async {
  final bool? shouldCopy = await showDialog<bool>(
    context: context,
    builder: (BuildContext ctx) => AlertDialog(
      title: Text('打开$title？'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SelectableText(
            url,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
          const SizedBox(height: 8),
          const Text('当前版本不直接调用浏览器，复制后可粘贴到浏览器打开。'),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('复制链接'),
        ),
      ],
    ),
  );
  if (shouldCopy == true) {
    if (!context.mounted) {
      return;
    }
    await copyToClipboard(context, url);
  }
}
