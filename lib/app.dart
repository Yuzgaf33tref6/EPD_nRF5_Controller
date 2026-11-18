import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'state/app_state.dart';

/// 应用根组件。
///
/// 持有 [AppState]（唯一的状态源），并把它挂到 widget 树的最外层。
/// 本轮是 UI 骨架：导航、画布预览、传图统计都是真的，蓝牙是假的。
class EpdControllerApp extends StatefulWidget {
  const EpdControllerApp({super.key});

  @override
  State<EpdControllerApp> createState() => _EpdControllerAppState();
}

class _EpdControllerAppState extends State<EpdControllerApp> {
  final AppState _state = AppState();

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
