import 'package:flutter/material.dart';

import '../services/app_info.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';

/// 日志查看器：完整日志列表 + 筛选。
class LogsScreen extends StatefulWidget {
  const LogsScreen({super.key});

  @override
  State<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends State<LogsScreen> {
  /// 是否只看警告与错误。
  bool _onlyProblems = false;

  @override
  Widget build(BuildContext context) {
    final AppState state = AppStateScope.of(context);
    final ThemeData theme = Theme.of(context);
    final List<LogEntry> entries = _onlyProblems
        ? state.logs
            .where((LogEntry e) =>
                e.level == LogLevel.warning || e.level == LogLevel.error)
            .toList()
        : state.logs;
    return Scaffold(
      appBar: AppBar(
        title: const Text('日志'),
        actions: <Widget>[
          IconButton(
            tooltip: _onlyProblems ? '显示全部' : '只看问题',
            icon: Icon(_onlyProblems
                ? Icons.filter_alt
                : Icons.filter_alt_outlined),
            onPressed: () => setState(() => _onlyProblems = !_onlyProblems),
          ),
          IconButton(
            tooltip: '清空',
            icon: const Icon(Icons.delete_outline),
            onPressed: entries.isEmpty
                ? null
                : () {
                    state.clearLogs();
                    setState(() {});
                  },
          ),
        ],
      ),
      body: entries.isEmpty
          ? const Center(
              child: Text('还没有日志'),
            )
          : ListView.builder(
              reverse: true,
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
              itemCount: entries.length,
              itemBuilder: (BuildContext context, int index) {
                final LogEntry entry = entries[entries.length - 1 - index];
                final Color color = switch (entry.level) {
                  LogLevel.success => theme.colorScheme.primary,
                  LogLevel.warning => Colors.orange.shade800,
                  LogLevel.error => theme.colorScheme.error,
                  LogLevel.info => theme.colorScheme.onSurfaceVariant,
                };
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        entry.timeText,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.outline,
                          fontFamily: 'monospace',
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: SelectableText(
                          entry.message,
                          style: theme.textTheme.bodySmall?.copyWith(color: color),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}

/// 更新日志页：硬编码在 `kReleaseNotes` 里，离线可看。
class ReleaseNotesScreen extends StatelessWidget {
  const ReleaseNotesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('更新日志')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        children: <Widget>[
          for (final ReleaseNote note in kReleaseNotes)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: SectionCard(
                title: 'v${note.version}',
                icon: Icons.new_releases_outlined,
                trailing: Text(
                  note.date,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    for (final String item in note.highlights)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text('· ', style: theme.textTheme.bodySmall),
                            Expanded(
                              child: Text(
                                item,
                                style: theme.textTheme.bodySmall,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
