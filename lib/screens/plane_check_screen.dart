import 'package:flutter/material.dart';

import '../state/app_state.dart';
import '../widgets/common.dart';

/// 平面排查页：调换黑白 / 红白平面、红白平面取反。
///
/// 只在固件的平面映射与面板不一致时才需要动用；正常情况下两个开关都保持关闭。
class PlaneCheckScreen extends StatelessWidget {
  const PlaneCheckScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final AppState state = AppStateScope.of(context);
    final ThemeData theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('平面排查')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
        children: <Widget>[
          SectionCard(
            title: '开关',
            icon: Icons.flip,
            child: Column(
              children: <Widget>[
                SettingSwitch(
                  icon: Icons.swap_vert,
                  title: '调换黑白 / 红白平面',
                  subtitle: '把两个要写入的面互换后再发送。',
                  value: state.swapPlanes,
                  onChanged: state.setSwapPlanes,
                ),
                SettingSwitch(
                  icon: Icons.invert_colors,
                  title: '红白平面取反',
                  subtitle: '把红白平面每个字节按位取反。',
                  value: state.invertRedPlane,
                  onChanged: state.setInvertRedPlane,
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          SectionCard(
            title: '什么时候用',
            icon: Icons.help_outline,
            dense: true,
            child: Text(
              '先用上一页的纯色测试判断现象：\n'
              '· 全黑出红、全红出黑 → 打开「调换黑白 / 红白平面」；\n'
              '· 全红出白、全白出红 → 打开「红白平面取反」。\n'
              '开关只影响之后发送的图，改完回到发送页重发一次即可看到效果。'
              '正常驱动不需要动这两项，排查完记得关掉。',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
