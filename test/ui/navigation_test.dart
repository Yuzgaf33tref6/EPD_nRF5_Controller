import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:epd_controller/main.dart';

/// UI 骨架的导航测试：只验证页面能打开、标题对、能返回。
///
/// 故意不测蓝牙（还没接），也不做截图对比（golden 图有平台差异）。
void main() {
  testWidgets('首页渲染标题与入口', (WidgetTester tester) async {
    await tester.pumpWidget(const EpdControllerApp());
    expect(find.text('EPD Controller'), findsOneWidget);
    expect(find.text('搜索并连接'), findsOneWidget);
    expect(find.text('编辑并发送'), findsOneWidget);
    expect(find.text('未连接设备'), findsOneWidget);
    expect(find.text('日志'), findsOneWidget);
  });

  testWidgets('首页 → 设备连接 → 返回', (WidgetTester tester) async {
    await tester.pumpWidget(const EpdControllerApp());

    await tester.tap(find.text('搜索并连接'));
    await tester.pumpAndSettle();
    expect(find.text('设备连接'), findsOneWidget);
    expect(find.text('扫描附近设备'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('EPD Controller'), findsOneWidget);
  });

  testWidgets('首页 → 画布与传图 → 返回', (WidgetTester tester) async {
    await tester.pumpWidget(const EpdControllerApp());

    await tester.tap(find.text('编辑并发送'));
    await tester.pumpAndSettle();
    expect(find.text('画布与传图'), findsOneWidget);
    expect(find.text('预览（抖动后）'), findsOneWidget);

    // 传图统计在列表下方，ListView 懒构建，必须先滚到可见位置。
    await tester.scrollUntilVisible(
      find.textContaining('条写指令'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.textContaining('条写指令'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('EPD Controller'), findsOneWidget);
  });

  testWidgets('首页 → 偏好设置 → 返回', (WidgetTester tester) async {
    await tester.pumpWidget(const EpdControllerApp());

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    expect(find.text('偏好设置'), findsOneWidget);
    expect(find.text('主题'), findsOneWidget);
    expect(find.textContaining('MTU'), findsWidgets);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('EPD Controller'), findsOneWidget);
  });

  testWidgets('首页 → 蓝牙诊断 → 返回', (WidgetTester tester) async {
    await tester.pumpWidget(const EpdControllerApp());

    await tester.scrollUntilVisible(
      find.text('蓝牙诊断'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('蓝牙诊断'));
    await tester.pumpAndSettle();
    expect(find.text('蓝牙诊断'), findsWidgets);
    expect(find.text('链路状态'), findsOneWidget);
    expect(find.textContaining('还没有收到通知'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('EPD Controller'), findsOneWidget);
  });

  testWidgets('未连接时设备控制按钮禁用', (WidgetTester tester) async {
    await tester.pumpWidget(const EpdControllerApp());

    await tester.scrollUntilVisible(
      find.text('清屏'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    final OutlinedButton clearButton = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, '清屏'),
    );
    expect(clearButton.onPressed, isNull);
  });
}
