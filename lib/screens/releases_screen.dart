import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/app_info.dart';
import '../services/update_checker.dart';
import '../widgets/common.dart';
import 'logs_screen.dart';

/// 关于与更新页：当前版本、作者、检查更新、更新日志入口。
class ReleasesScreen extends StatefulWidget {
  const ReleasesScreen({super.key, this.checker});

  /// 测试可注入假的检查器；默认走真实网络。
  final UpdateChecker? checker;

  @override
  State<ReleasesScreen> createState() => _ReleasesScreenState();
}

class _ReleasesScreenState extends State<ReleasesScreen> {
  late final UpdateChecker _checker = widget.checker ?? UpdateChecker();
  UpdateCheckResult? _result;
  bool _checking = false;

  /// 作者名 → 个人主页。界面上只显示名字，链接藏在点击里。
  static const String _authorUrl = 'https://github.com/Yuzgaf33tref6';

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('关于与更新')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        children: <Widget>[
          SectionCard(
            title: AppVersion.appName,
            icon: Icons.auto_stories_outlined,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                InfoRow(label: '版本', value: AppVersion.fullVersion),
                InfoRow(
                  label: '作者',
                  value: AppVersion.authors,
                  onTap: () => _confirmOpen(context, _authorUrl, '作者主页'),
                  onCopy: (String v) => _copy(context, v),
                ),
                _LinkRow(
                  label: '仓库',
                  url: AppVersion.repoUrl,
                  onOpen: () => _confirmOpen(context, AppVersion.repoUrl, '项目仓库'),
                  onCopy: () => _copy(context, AppVersion.repoUrl),
                ),
                _LinkRow(
                  label: '固件',
                  url: AppVersion.upstreamUrl,
                  onOpen: () =>
                      _confirmOpen(context, AppVersion.upstreamUrl, '上游固件项目'),
                  onCopy: () => _copy(context, AppVersion.upstreamUrl),
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
              ],
            ),
          ),
          const SizedBox(height: 12),
          SectionCard(
            title: '检查更新',
            icon: Icons.cloud_download_outlined,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                FilledButton.tonalIcon(
                  onPressed: _checking ? null : _check,
                  icon: _checking
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh, size: 18),
                  label: Text(_checking ? '正在查询 …' : '检查 GitHub 上的最新版本'),
                ),
                Text(
                  '只在点这个按钮时联网查询一次，不会后台自动检查。',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (_result != null) ..._buildResult(context, _result!),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SectionCard(
            title: '更多',
            icon: Icons.more_horiz,
            child: Column(
              children: <Widget>[
                SettingTile(
                  icon: Icons.history,
                  title: '更新日志',
                  subtitle: '本次及历史版本改了什么',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const ReleaseNotesScreen(),
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

  /// 把链接复制到剪贴板，并用 SnackBar 告诉用户复制了什么。
  Future<void> _copy(BuildContext context, String text) async {
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
  Future<void> _confirmOpen(
    BuildContext context,
    String url,
    String title,
  ) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text('打开$title？'),
        content: SelectableText(
          url,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('复制链接'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
        ],
      ),
    );
    if (!context.mounted) {
      return;
    }
    if (ok == true) {
      await _copy(context, url);
    }
  }

  List<Widget> _buildResult(BuildContext context, UpdateCheckResult result) {
    final ThemeData theme = Theme.of(context);
    final String? error = result.error;
    if (error != null) {
      return <Widget>[
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: theme.colorScheme.errorContainer,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(
                    Icons.error_outline,
                    size: 16,
                    color: theme.colorScheme.onErrorContainer,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '检查失败',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onErrorContainer,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                error,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onErrorContainer,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ];
    }
    if (result.hasUpdate) {
      return <Widget>[
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                '发现新版本 v${result.latestVersion}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
              if (result.releaseName != null) ...<Widget>[
                const SizedBox(height: 2),
                Text(
                  result.releaseName!,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
              ],
              const SizedBox(height: 6),
              Text(
                '到发布页下载 EPDController-${result.latestVersion}-<ABI>.apk，'
                '选和手机架构对应的那个（现在多数手机是 arm64-v8a）。',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onPrimaryContainer,
                  height: 1.5,
                ),
              ),
              if (result.releaseUrl != null) ...<Widget>[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.icon(
                    onPressed: () => _copy(context, result.releaseUrl!),
                    icon: const Icon(Icons.copy_all, size: 16),
                    label: const Text('复制下载页链接'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ];
    }
    return <Widget>[
      const SizedBox(height: 8),
      Row(
        children: <Widget>[
          Icon(
            Icons.check_circle_outline,
            size: 16,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 6),
          Text(
            '已是最新版本（v${result.currentVersion}）',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
        ],
      ),
    ];
  }

  Future<void> _check() async {
    setState(() {
      _checking = true;
      _result = null;
    });
    final UpdateCheckResult result = await _checker.check();
    if (!mounted) {
      return;
    }
    setState(() {
      _checking = false;
      _result = result;
    });
  }
}

/// 带「打开」与「复制」两个图标按钮的链接行。
///
/// 链接用等宽字体自动折行，两个按钮固定在最右侧，保证多行时也对得齐。
class _LinkRow extends StatelessWidget {
  const _LinkRow({
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
