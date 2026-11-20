import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:epd_controller/main.dart';
import 'package:epd_controller/services/app_info.dart';

/// UI 导航测试：底部三栏、各二级页面能打开与返回。
///
/// 测试视口是 800x600，很多入口在 ListView 的折叠线以下：直接 tap 会因为
/// 控件在屏幕外而点不中（测试框架会报 "outside the bounds of the render tree"），
/// 所以统一先滚到可见再交互。
///
/// 注意两点坑：
/// 1. 页面里可能同时存在多个 Scrollable（列表 + 下拉框），用 `.last` 取到的不一定
///    是列表本身，某些页面上甚至一个都没有；所以滚动一律基于目标控件做 [ensureVisible]。
/// 2. 从二级页面 `pageBack()` 回来时，列表的滚动位置还停在原处，原先在屏幕上的
///    元素未必还在，因此返回后的断言只看 AppBar 标题这类恒定的东西。
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

  /// 把 [finder] 对应的控件滚进可视区域：优先用所在页面的列表滚过去，
  /// 若找不到列表（例如控件本来就在首屏），直接跳过，不做无谓的滚动。
  Future<void> scrollTo(WidgetTester tester, Finder finder) async {
    final Finder scrollable = find.byType(Scrollable);
    if (scrollable.evaluate().isEmpty) {
      return;
    }
    await tester.scrollUntilVisible(
      finder,
      200,
      scrollable: scrollable.first,
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

    // 折叠头是包住「连接设备」那一行的 InkWell；直接点 InkWell 本体，
    // 比点其中的 Text 更可靠（Text 位于 Expanded 里，tap 中心可能落在
    // 行内其他兄弟组件上）。
    final Finder header = find
        .ancestor(
          of: find.text('连接设备').first,
          matching: find.byType(InkWell),
        )
        .first;
    await tester.ensureVisible(header);
    await tester.pumpAndSettle();
    await tester.tap(header);
    await tester.pumpAndSettle();
    expect(find.text('扫描附近设备'), findsNothing);

    // 收起后列表变短，折叠头位置会变；再定位一次比较稳。
    await tester.ensureVisible(header);
    await tester.pumpAndSettle();
    await tester.tap(header);
    await tester.pumpAndSettle();
    expect(find.text('扫描附近设备'), findsOneWidget);
  });

  testWidgets('发送页有设备指令与图像入口', (WidgetTester tester) async {
    await pumpApp(tester);
    await switchTab(tester, 1);
    expect(find.text('设备指令'), findsOneWidget);
    expect(find.textContaining('时间同步'), findsOneWidget);
    expect(find.text('日历模式'), findsOneWidget);
    await scrollTo(tester, find.text('图像发送'));
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
    expect(find.text('设置'), findsWidgets);
    expect(find.text('分块档位'), findsOneWidget);

    await scrollTo(tester, find.text('驱动选择'));
    expect(find.text('驱动选择'), findsOneWidget);

    await scrollTo(tester, find.text('诊断工具'));
    expect(find.text('诊断工具'), findsOneWidget);

    await scrollTo(tester, find.textContaining('Noyield'));
    expect(find.textContaining('Noyield'), findsWidgets);
  });

  testWidgets('设置页 → 纯色测试 → 返回', (WidgetTester tester) async {
    await pumpApp(tester);
    await switchTab(tester, 2);
    await tapAfterScroll(tester, find.text('纯色测试'));
    expect(find.text('发送纯色'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    // 返回后列表滚动位置未复位，只断言恒定存在的 AppBar 标题。
    expect(find.text('设置'), findsWidgets);
  });

  testWidgets('设置页 → 平面排查 → 返回', (WidgetTester tester) async {
    await pumpApp(tester);
    await switchTab(tester, 2);
    await tapAfterScroll(tester, find.text('平面排查'));
    expect(find.text('调换黑白 / 红白平面'), findsOneWidget);
    expect(find.text('红白平面取反'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('设置'), findsWidgets);
  });

  testWidgets('设置页 → 权限检查 → 返回', (WidgetTester tester) async {
    await pumpApp(tester);
    await switchTab(tester, 2);

    await tapAfterScroll(tester, find.text('权限检查'));
    expect(find.text('权限清单'), findsOneWidget);
    expect(find.text('附近的设备（扫描）'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    // 「设置」既是 AppBar 标题也是底部导航标签，所以用 findsWidgets。
    expect(find.text('设置'), findsWidgets);
  });

  testWidgets('设置页 → 蓝牙诊断 → 返回', (WidgetTester tester) async {
    await pumpApp(tester);
    await switchTab(tester, 2);
    await tapAfterScroll(tester, find.text('蓝牙诊断'));
    expect(find.text('链路状态'), findsOneWidget);
    // 未连接时信号强度显示占位符，且「刷新信号」不可点。
    expect(find.text('信号'), findsOneWidget);
    expect(find.text('刷新信号'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('设置'), findsWidgets);
  });

  testWidgets('设置页 → 日志查看器 → 返回', (WidgetTester tester) async {
    await pumpApp(tester);
    await switchTab(tester, 2);
    await tapAfterScroll(tester, find.text('日志查看器'));
    expect(find.text('日志'), findsWidgets);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('设置'), findsWidgets);
  });

  testWidgets('设置页 → 关于与更新 → 返回', (WidgetTester tester) async {
    await pumpApp(tester);
    await switchTab(tester, 2);
    await tapAfterScroll(tester, find.text('检查更新'));
    expect(find.text('关于与更新'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('设置'), findsWidgets);
  });

  testWidgets('更新日志页渲染硬编码的版本条目', (WidgetTester tester) async {
    await pumpApp(tester);
    await switchTab(tester, 2);
    await tapAfterScroll(tester, find.text('更新日志'));
    // 最新一版（目前是 0.2.1）应当直接出现在首屏。
    expect(find.textContaining(AppVersion.version), findsWidgets);
    await scrollTo(tester, find.textContaining('0.1.0'));
    expect(find.textContaining('0.1.0'), findsWidgets);
  });

  testWidgets('未连接时发送页的设备指令按钮禁用', (WidgetTester tester) async {
    await pumpApp(tester);
    await switchTab(tester, 1);
    // 按钮文案带指令编号（0x02 清屏），用 textContaining 定位更稳。
    final Finder clearFinder = find.ancestor(
      of: find.textContaining('清屏'),
      matching: find.byType(OutlinedButton),
    );
    await scrollTo(tester, clearFinder);
    final OutlinedButton clearButton = tester.widget<OutlinedButton>(clearFinder);
    expect(clearButton.onPressed, isNull);
  });
}
