import 'package:flutter/material.dart';

/// 通用的分组卡片：一个标题 + 一组内容。
///
/// 首页/发送页/设置页共用，避免各页各写一套 `Card` 结构导致样式漂移。
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.title,
    required this.child,
    this.trailing,
    this.icon,
    this.dense = false,
  });

  final String title;
  final Widget child;

  /// 标题右侧的附加控件（例如一个「全部」按钮）。
  final Widget? trailing;

  /// 标题左侧的小图标。
  final IconData? icon;

  /// 紧凑模式：内边距更小，适合设置页这种一屏放很多组的场景。
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: EdgeInsets.fromLTRB(dense ? 12 : 16, dense ? 10 : 14, 12, dense ? 10 : 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                if (icon != null) ...<Widget>[
                  Icon(icon, size: dense ? 16 : 18, color: theme.colorScheme.primary),
                  const SizedBox(width: 6),
                ],
                Expanded(
                  child: Text(
                    title,
                    style: (dense
                            ? theme.textTheme.titleSmall
                            : theme.textTheme.titleMedium)
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
            SizedBox(height: dense ? 6 : 10),
            child,
          ],
        ),
      ),
    );
  }
}

/// 「标签 + 值」的一行，设置页与诊断页大量使用。
class InfoRow extends StatelessWidget {
  const InfoRow({
    super.key,
    required this.label,
    required this.value,
    this.labelWidth = 84,
    this.valueColor,
    this.monospace = false,
    this.onTap,
    this.onCopy,
    this.trailing,
  });

  final String label;
  final String value;
  final double labelWidth;
  final Color? valueColor;

  /// 值用等宽字体（引脚、十六进制串看起来更整齐）。
  final bool monospace;

  /// 点击整行时触发（例如打开链接）。
  final VoidCallback? onTap;

  /// 点击复制按钮时触发；为 null 则不显示复制按钮。参数是 [value]。
  final ValueChanged<String>? onCopy;

  /// 值右侧的额外内容（例如「打开」「复制」图标按钮）。
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool tappable = onTap != null;
    final Widget row = Padding(
      padding: EdgeInsets.symmetric(vertical: tappable ? 6 : 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: labelWidth,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: tappable ? theme.colorScheme.primary : valueColor,
                fontFamily: monospace ? 'monospace' : null,
                decoration: tappable ? TextDecoration.underline : null,
                decorationColor: tappable
                    ? theme.colorScheme.primary.withValues(alpha: 0.4)
                    : null,
              ),
            ),
          ),
          if (trailing != null) ...<Widget>[
            const SizedBox(width: 4),
            trailing!,
          ],
        ],
      ),
    );
    if (!tappable) {
      return row;
    }
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: row,
    );
  }
}

/// 分组标题（设置页里把小标题与卡片分开时使用）。
class GroupHeader extends StatelessWidget {
  const GroupHeader({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
      child: Text(
        title,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

/// 一行可点击的设置项：图标 + 标题 + 说明 + 右侧箭头。
class SettingTile extends StatelessWidget {
  const SettingTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: Icon(icon, color: theme.colorScheme.primary),
      title: Text(title, style: theme.textTheme.bodyLarge),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
      trailing: trailing ??
          (onTap == null
              ? null
              : Icon(Icons.chevron_right, color: theme.colorScheme.outline)),
      onTap: onTap,
    );
  }
}

/// 带说明的开关行（比裸 `SwitchListTile` 更容易对齐）。
class SettingSwitch extends StatelessWidget {
  const SettingSwitch({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return SwitchListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      secondary: Icon(icon, color: theme.colorScheme.primary),
      title: Text(title, style: theme.textTheme.bodyLarge),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
      value: value,
      onChanged: onChanged,
    );
  }
}

/// 空状态的居中提示。
class EmptyHint extends StatelessWidget {
  const EmptyHint({super.key, required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        children: <Widget>[
          Icon(icon, size: 32, color: theme.colorScheme.outlineVariant),
          const SizedBox(height: 8),
          Text(
            text,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
