import 'package:flutter/material.dart';

import '../image/epd_color.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';

/// 纯色测试页：整屏发黑 / 白 / 红，用来验证链路与平面极性。
class SolidColorScreen extends StatelessWidget {
  const SolidColorScreen({super.key});

  static final List<EpdColor> _colors = <EpdColor>[
    rgbPalette[0], // 黑
    rgbPalette[1], // 白
    rgbPalette[3], // 红
  ];

  @override
  Widget build(BuildContext context) {
    final AppState state = AppStateScope.of(context);
    final ThemeData theme = Theme.of(context);
    final bool connected = state.isConnected;
    return Scaffold(
      appBar: AppBar(title: const Text('纯色测试')),
      body: Column(
        children: <Widget>[
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
              children: <Widget>[
                if (!connected)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: EmptyHint(
                      icon: Icons.bluetooth_disabled,
                      text: '还没有连接设备，先回首页连上再测试。',
                    ),
                  ),
                SectionCard(
                  title: '发送纯色',
                  icon: Icons.palette_outlined,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: <Widget>[
                          for (final EpdColor color in _colors)
                            OutlinedButton(
                              onPressed: connected
                                  ? () => state.sendSolidColor(color)
                                  : null,
                              child: Text('全${color.name}'),
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        '怎么判断：\n'
                        '· 三个都正常 → 数据链路没问题，问题在抖动后的图本身；\n'
                        '· 发全黑却出红色 → 黑白平面与红白平面搞反了；\n'
                        '· 发全红却出白色（或反之）→ 红白平面极性相反。',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                SectionCard(
                  title: '当前参数',
                  icon: Icons.tune,
                  dense: true,
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
                      InfoRow(label: '颜色模式', value: state.colorMode.jsName),
                      InfoRow(label: 'MTU', value: '${state.mtu}'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
