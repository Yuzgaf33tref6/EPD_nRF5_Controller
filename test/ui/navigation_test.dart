import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:epd_controller/main.dart';

/// UI 导航测试：底部三栏、各二级页面能打开与返回。
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
    expect(find.text('扫描附近设备'), findsOneWidget);
    await tester.tap(find.text('连接设备'));
    await tester.pumpAndSettle();
    expect(find.text('扫描附近设备'), findsNothing);
    await tester.tap(find.text('连接设备'));
    await tester.pumpAndSettle();
    expect(find.text('扫描附近设备'), findsOneWidget);
  });

  testWidgets('发送页有设备指令与图像入口', (WidgetTester tester) async {
    await pumpApp(tester);
    await switchTab(tester, 1);
    expect(find.text('设备指令'), findsOneWidget);
    expect(find.text('同步时间'), findsOneWidget);
    expect(find.text('清屏'), findsOneWidget);
    expect(find.text('图像发送'), findsOneWidget);
  });

  testWidgets('发送页 → 图像发送 → 画布编辑 → 文字对话框', (WidgetTester tester) async {
    await pumpApp(tester);
    await switchTab(tester, 1);

    await tester.tap(find.text('图像发送'));
    await tester.pumpAndSettle();
    expect(find.text('预览'), findsOneWidget);
    expect(find.text('抖动'), findsWidgets);

    await tester.tap(find.byTooltip('画布编辑'));
    await tester.pumpAndSettle();
    expect(find.text('画布编辑'), findsOneWidget);
    expect(find.text('画笔'), findsOneWidget);

    await tester.tap(find.text('文字'));
    await tester.pumpAndSettle();
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
    expect(find.text('驱动选择'), findsOneWidget);
    expect(find.text('诊断工具'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('软件信息'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('软件信息'), findsOneWidget);
    expect(find.textContaining('Noyield'), findsWidgets);
  });

  testWidgets('设置页 → 纯色测试 → 返回', (WidgetTester tester) async {
    await pumpApp(tester);
    await switchTab(tester, 2);
    await tester.scrollUntilVisible(
      find.text('纯色测试'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('纯色测试'));
    await tester.pumpAndSettle();
    expect(find.text('发送纯色'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('分块档位'), findsOneWidget);
  });

  testWidgets('设置页 → 平面排查 → 返回', (WidgetTester tester) async {
    await pumpApp(tester);
    await switchTab(tester, 2);
    await tester.scrollUntilVisible(
      find.text('平面排查'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('平面排查'));
    await tester.pumpAndSettle();
    expect(find.text('调换黑白 / 红白平面'), findsOneWidget);
    expect(find.text('红白平面取反'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('分块档位'), findsOneWidget);
  });

  testWidgets('设置页 → 蓝牙诊断 → 返回', (WidgetTester tester) async {
    await pumpApp(tester);
    await switchTab(tester, 2);
    await tester.scrollUntilVisible(
      find.text('蓝牙诊断'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('蓝牙诊断'));
    await tester.pumpAndSettle();
    expect(find.text('链路状态'), findsOneWidget);
    expect(find.textContaining('还没有收到通知'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('分块档位'), findsOneWidget);
  });

  testWidgets('设置页 → 日志查看器 → 返回', (WidgetTester tester) async {
    await pumpApp(tester);
    await switchTab(tester, 2);
    await tester.scrollUntilVisible(
      find.text('日志查看器'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('日志查看器'));
    await tester.pumpAndSettle();
    expect(find.text('日志'), findsWidgets);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('分块档位'), findsOneWidget);
  });

  testWidgets('设置页 → 关于与更新 → 返回', (WidgetTester tester) async {
    await pumpApp(tester);
    await switchTab(tester, 2);
    await tester.scrollUntilVisible(
      find.text('检查更新'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('检查更新'));
    await tester.pumpAndSettle();
    expect(find.text('关于与更新'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('分块档位'), findsOneWidget);
  });

  testWidgets('更新日志页渲染硬编码的版本条目', (WidgetTester tester) async {
    await pumpApp(tester);
    await switchTab(tester, 2);
    await tester.scrollUntilVisible(
      find.text('更新日志'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('更新日志'));
    await tester.pumpAndSettle();
    expect(find.textContaining('0.2.0'), findsWidgets);
    expect(find.textContaining('0.1.0'), findsWidgets);
  });

  testWidgets('未连接时发送页的设备指令按钮禁用', (WidgetTester tester) async {
    await pumpApp(tester);
    await switchTab(tester, 1);
    final OutlinedButton clearButton = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, '清屏'),
    );
    expect(clearButton.onPressed, isNull);
  });
}
