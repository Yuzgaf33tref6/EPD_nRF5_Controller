import 'dart:async';

import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'screens/send_screen.dart';
import 'screens/settings_screen.dart';
import 'services/ble_service.dart';
import 'services/settings_store.dart';
import 'state/app_state.dart';

/// 应用根组件。
///
/// 持有 [AppState]（唯一的状态源），并把它挂到 widget 树的最外层。
///
/// [bleService] 为空时用模拟蓝牙（widget 测试走这条路，不需要真机与插件通道）；
/// 真机入口在 `main.dart` 里传入 [ReactiveBleService]。
class EpdControllerApp extends StatefulWidget {
  const EpdControllerApp({super.key, this.bleService, this.settingsStore});

  final EpdBleService? bleService;

  /// 设置持久化实现；空则用内存实现（测试用），真机在 `main.dart` 注入文件实现。
  final SettingsStore? settingsStore;

  @override
  State<EpdControllerApp> createState() => _EpdControllerAppState();
}

class _EpdControllerAppState extends State<EpdControllerApp> {
  late final AppState _state = AppState(
    bleService: widget.bleService,
    settingsStore: widget.settingsStore,
  );

  /// 监听状态变化，用于在首帧启动权限检查、以及弹「驱动可能错误」提示。
  VoidCallback? _listener;

  @override
  void initState() {
    super.initState();
    _listener = _onStateChanged;
    _state.addListener(_listener!);
    // 首帧之后再检查权限：此时已有 Overlay，可以弹系统授权框与提示条。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_checkPermissionsOnLaunch());
    });
  }

  @override
  void dispose() {
    if (_listener != null) {
      _state.removeListener(_listener!);
    }
    _state.dispose();
    super.dispose();
  }

  /// 首次启动（本次进程）自动申请蓝牙权限。
  ///
  /// 系统会自己弹授权框；这里只负责「一打开就去要」，并把结果留在状态里供 UI 展示。
  Future<void> _checkPermissionsOnLaunch() async {
    await _state.ensurePermissionsOnce();
    if (!mounted) {
      return;
    }
    _maybeWarnDriver();
  }

  void _onStateChanged() {
    _maybeWarnDriver();
  }

  /// 连上了但没收到固件的配置通知时，提示用户手动确认驱动。
  void _maybeWarnDriver() {
    if (!mounted || !_state.shouldWarnDriverMismatch) {
      return;
    }
    _state.markDriverWarningShown();
    unawaited(_showDriverWarning());
  }

  Future<void> _showDriverWarning() async {
    final bool? mute = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('没收到设备的驱动信息'),
        content: const Text(
          '连上了，但设备没有上报引脚与驱动号。\n\n'
          '如果屏幕上的图案明显不对（比如颜色反了、画面错位），'
          '说明当前驱动可能不匹配，请到「设置 → 驱动」里手动选择。',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('知道了'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('不再提示'),
          ),
        ],
      ),
    );
    if (mute == true) {
      _state.setDriverWarningMuted(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppStateScope(
      state: _state,
      child: Builder(
        builder: (BuildContext context) {
          final AppState state = AppStateScope.of(context);
          return MaterialApp(
            title: 'EPD Controller',
            debugShowCheckedModeBanner: false,
            themeMode: state.themeMode,
            theme: ThemeData(colorSchemeSeed: Colors.indigo),
            darkTheme: ThemeData(
              colorSchemeSeed: Colors.indigo,
              brightness: Brightness.dark,
            ),
            home: const AppShell(),
          );
        },
      ),
    );
  }
}

/// 三栏导航外壳：首页 / 发送 / 设置。
///
/// 用 [IndexedStack] 保住每页的滚动位置与局部状态（尤其图像页的预览开销）。
class AppShell extends StatefulWidget {
  const AppShell({super.key, this.initialIndex = 0});

  final int initialIndex;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  late int _index = widget.initialIndex;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: const <Widget>[
          HomeScreen(),
          SendScreen(),
          SettingsScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (int value) => setState(() => _index = value),
        destinations: const <NavigationDestination>[
          NavigationDestination(
            icon: Icon(Icons.bluetooth_outlined),
            selectedIcon: Icon(Icons.bluetooth),
            label: '首页',
          ),
          NavigationDestination(
            icon: Icon(Icons.send_outlined),
            selectedIcon: Icon(Icons.send),
            label: '发送',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: '设置',
          ),
        ],
      ),
    );
  }
}
