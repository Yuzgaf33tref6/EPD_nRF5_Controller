import 'package:flutter/material.dart';

void main() {
  runApp(const EpdControllerApp());
}

/// 应用根组件。
///
/// 骨架阶段只负责启动，不涉及任何第三方依赖；
/// 蓝牙、协议、图像处理各层在后续提交中逐个接入。
class EpdControllerApp extends StatelessWidget {
  const EpdControllerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'EPD Controller',
      theme: ThemeData(colorSchemeSeed: Colors.indigo),
      home: const Scaffold(
        body: Center(
          child: Text('EPD Controller'),
        ),
      ),
    );
  }
}
