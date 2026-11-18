import 'package:flutter/material.dart';

import '../state/app_state.dart';

/// 底部日志面板，对应 web 版右上角的 `#log`。
class LogPanel extends StatelessWidget {
  const LogPanel({super.key, this.height = 168});

  final double height;

  @override
  Widget build(BuildContext context) {
    final AppState state = AppStateScope.of(context);
    final ThemeData theme = Theme.of(context);
    final List<LogEntry> logs = state.logs;

    return Container(
      height: height,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        border: Border(top: BorderSide(color: theme.dividerColor)),
      ),
      child: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 4, 0),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text('日志', style: theme.textTheme.labelLarge),
                ),
                IconButton(
                  tooltip: '清空日志',
                  icon: const Icon(Icons.delete_sweep_outlined, size: 20),
                  onPressed: state.clearLogs,
                ),
              ],
            ),
          ),
          Expanded(
            child: logs.isEmpty
                ? Center(
                    child: Text(
                      '暂无日志',
                      style: theme.textTheme.bodySmall,
                    ),
                  )
                : ListView.builder(
                    reverse: true,
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                    itemCount: logs.length,
                    itemBuilder: (BuildContext context, int index) {
                      // reverse: true 时 index 0 是最新的那条。
                      final LogEntry entry = logs[logs.length - 1 - index];
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 1),
                        child: Text(
                          '${entry.timeText}  ${entry.message}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontFamily: 'monospace',
                            color: _colorOf(theme, entry.level),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Color _colorOf(ThemeData theme, LogLevel level) {
    switch (level) {
      case LogLevel.info:
        return theme.colorScheme.onSurfaceVariant;
      case LogLevel.success:
        return theme.colorScheme.primary;
      case LogLevel.warning:
        return Colors.orange.shade800;
      case LogLevel.error:
        return theme.colorScheme.error;
    }
  }
}
