import 'package:flutter/material.dart';

import '../services/app_info.dart';
import '../services/update_checker.dart';
import '../widgets/app_info_card.dart';
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



  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('关于与更新')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        children: <Widget>[
          const AppInfoCard(showActions: false),
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
                    onPressed: () => copyToClipboard(context, result.releaseUrl!),
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

