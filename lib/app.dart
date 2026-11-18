import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
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

  @override
  void dispose() {
    _state.dispose();
    super.dispose();
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
            home: const HomeScreen(),
          );
        },
      ),
    );
  }
}
