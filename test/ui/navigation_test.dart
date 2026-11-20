import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:epd_controller/main.dart';

/// UI 导航测试：底部三栏、各二级页面能打开与返回。
///
/// 测试视口是 800x600，很多入口在 ListView 的折叠线以下：直接 tap 会因为
/// 控件在屏幕外而点不中（测试框架会报 "outside the bounds of the render tree"）。
/// 所以统一先用 [ensureVisible] 把目标滚到可见位置，再交互。
void main() {
  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(const EpdControllerApp());
    await tester.pumpAndSettle();
  }

  /// 切到底部导航的第 [index] 栏（0 首页 / 1 发送 / 2 设置）。
  Future<void> switchTab(WidgetTester tester, int index) async {
    await tester.tap(find.byType(NavigationDestination).at(index));
    await tester.pumpAndSettle();
  }

  /// 把 [finder] 对应的控件滚进可视区域（折叠线以下的入口都需要）。
  Future<void> scrollTo(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(
      finder,
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
  }

  /// 滚到可见后点击。
  Future<void> tapAfterScroll(WidgetTester tester, Finder finder) async {
    await scrollTo(tester, finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  testWidgets('底部导航有三栏，首页默认选中', (WidgetTester tester) async {
    await pumpApp(tester);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('首页'), findsOneWidget);
    expect(find.text('发送'), findsOneWidget);
    expect(find.text('设置'), findsOneWidget);
    expect(find.byType(NavigationDestination), findsNWidgets(3));
  });

  testWidgets('首页显示连接状态卡与快捷按钮', (WidgetTester tester) async {
    await pumpApp(tester);
    expect(find.text('未连接'), findsWidgets);
    expect(find.text('连接'), findsWidgets);
    expect(find.text('重连'), findsWidgets);
    // 未连接时扫描区自动展开。
    expect(find.text('连接设备'), findsOneWidget);
    expect(find.text('扫描附近设备'), findsOneWidget);
  });

  testWidgets('首页扫描区可以收起和展开', (WidgetTester tester) async {
    await pumpApp(tester);
    await scrollTo(tester, find.text('扫描附近设备'));
    expect(find.text('扫描附近设备'), findsOneWidget);

    await tapAfterScroll(tester, find.text('连接设备'));
    expect(find.text('扫描附近设备'), findsNothing);

    await tapAfterScroll(tester, find.text('连接设备'));
    expect(find.text('扫描附近设备'), findsOneWidget);
  });

  testWidgets('发送页有设备指令与图像入口', (WidgetTester tester) async {
    await pumpApp(tester);
    await switchTab(tester, 1);
    expect(find.text('设备指令'), findsOneWidget);
    expect(find.text('同步时间'), findsOneWidget);
    await scrollTo(tester, find.text('图像发送'));
    expect(find.text('清屏'), findsOneWidget);
    expect(find.text('图像发送'), findsOneWidget);
  });

  testWidgets('发送页 → 图像发送 → 画布编辑 → 文字对话框', (WidgetTester tester) async {
    await pumpApp(tester);
    await switchTab(tester, 1);

    await tapAfterScroll(tester, find.text('图像发送'));
    // 预览卡片的标题会随「抖动 / 原图」开关变化，所以用前缀匹配。
    expect(find.textContaining('预览（'), findsOneWidget);
    expect(find.text('抖动'), findsWidgets);

    await tester.tap(find.byTooltip('画布编辑'));
    await tester.pumpAndSettle();
    expect(find.text('画布编辑'), findsOneWidget);
    expect(find.text('画笔'), findsOneWidget);

    await tapAfterScroll(tester, find.text('文字'));
    expect(find.text('添加文字'), findsOneWidget);
    expect(find.text('文字内容'), findsOneWidget);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.text('添加文字'), findsNothing);
    expect(find.text('画布编辑'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('图像发送'), findsOneWidget);
  });

  testWidgets('设置页分组与关键项都在', (WidgetTester tester) async {
    await pumpApp(tester);
    await switchTab(tester, 2);
    expect(find.text('应用'), findsOneWidget);
    expect(find.text('分块档位'), findsOneWidget);

    await scrollTo(tester, find.text('驱动选择'));
    expect(find.text('驱动选择'), findsOneWidget);

    await scrollTo(tester, find.text('诊断工具'));
    expect(find.text('诊断工具'), findsOneWidget);

    await scrollTo(tester, find.text('软件信息'));
    expect(find.text('软件信息'), findsOneWidget);
    expect(find.textContaining('Noyield'), findsWidgets);
  });

  testWidgets('设置页 → 纯色测试 → 返回', (WidgetTester tester) async {
    await pumpApp(tester);
    await switchTab(tester, 2);
    await tapAfterScroll(tester, find.text('纯色测试'));
    expect(find.text('发送纯色'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('分块档位'), findsOneWidget);
  });

  testWidgets('设置页 → 平面排查 → 返回', (WidgetTester tester) async {
    await pumpApp(tester);
    await switchTab(tester, 2);
    await tapAfterScroll(tester, find.text('平面排查'));
    expect(find.text('调换黑白 / 红白平面'), findsOneWidget);
    expect(find.text('红白平面取反'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('分块档位'), findsOneWidget);
  });

  testWidgets('设置页 → 蓝牙诊断 → 返回', (WidgetTester tester) async {
    await pumpApp(tester);
    await switchTab(tester, 2);
    await tapAfterScroll(tester, find.text('蓝牙诊断'));
    expect(find.text('链路状态'), findsOneWidget);
    expect(find.textContaining('还没有收到通知'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('分块档位'), findsOneWidget);
  });

  testWidgets('设置页 → 日志查看器 → 返回', (WidgetTester tester) async {
    await pumpApp(tester);
    await switchTab(tester, 2);
    await tapAfterScroll(tester, find.text('日志查看器'));
    expect(find.text('日志'), findsWidgets);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('分块档位'), findsOneWidget);
  });

  testWidgets('设置页 → 关于与更新 → 返回', (WidgetTester tester) async {
    await pumpApp(tester);
    await switchTab(tester, 2);
    await tapAfterScroll(tester, find.text('检查更新'));
    expect(find.text('关于与更新'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('分块档位'), findsOneWidget);
  });

  testWidgets('更新日志页渲染硬编码的版本条目', (WidgetTester tester) async {
    await pumpApp(tester);
    await switchTab(tester, 2);
    await tapAfterScroll(tester, find.text('更新日志'));
    expect(find.textContaining('0.2.0'), findsWidgets);
    await scrollTo(tester, find.textContaining('0.1.0'));
    expect(find.textContaining('0.1.0'), findsWidgets);
  });

  testWidgets('未连接时发送页的设备指令按钮禁用', (WidgetTester tester) async {
    await pumpApp(tester);
    await switchTab(tester, 1);
    await scrollTo(tester, find.widgetWithText(OutlinedButton, '清屏'));
    final OutlinedButton clearButton = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, '清屏'),
    );
    expect(clearButton.onPressed, isNull);
  });
}
