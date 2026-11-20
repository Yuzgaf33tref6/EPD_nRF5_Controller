import 'package:flutter/material.dart';

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
                InfoRow(label: '作者', value: AppVersion.authors),
                InfoRow(
                  label: '仓库',
                  value: AppVersion.repoUrl,
                  labelWidth: 56,
                ),
                InfoRow(
                  label: '固件',
                  value: AppVersion.upstreamUrl,
                  labelWidth: 56,
                ),
                const SizedBox(height: 8),
                Text(
                  '把 EPD-nRF5 的 Web 上位机搬到 Android：通过蓝牙（BLE）给墨水屏'
                  '同步时间、清屏、传图。图像链路与 web 版逐字节对拍，'
                  '抖动、位打包、传图分块全部一致。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
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
        const SizedBox(height: 8),
        Text(
          error,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.error,
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
              const SizedBox(height: 4),
              if (result.releaseName != null)
                Text(
                  result.releaseName!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
              if (result.releaseUrl != null) ...<Widget>[
                const SizedBox(height: 6),
                SelectableText(
                  result.releaseUrl!,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
              ],
              const SizedBox(height: 4),
              Text(
                '下载地址：GitHub Releases 页面里的 EPDController-<版本>-<ABI>.apk',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
            ],
          ),
        ),
      ];
    }
    return <Widget>[
      const SizedBox(height: 8),
      Text(
        '已是最新版本（v${result.currentVersion}）',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.primary,
        ),
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
