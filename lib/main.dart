import 'package:flutter/material.dart';

import 'app.dart';
import 'services/ble_service.dart';
import 'services/settings_store.dart';

export 'app.dart' show EpdControllerApp;

void main() {
  // flutter_reactive_ble 在构造单例时就会走平台通道初始化，
  // 必须先确保 WidgetsBinding 存在，否则真机启动即抛
  // "Null check operator used on a null value"（ServicesBinding.instance 为空）。
  WidgetsFlutterBinding.ensureInitialized();
  // 真机入口注入真实 BLE 实现与文件版设置存储；
  // 测试直接 new EpdControllerApp() 用模拟蓝牙 + 内存设置。
  runApp(
    EpdControllerApp(
      bleService: ReactiveBleService(),
      settingsStore: FileSettingsStore(),
    ),
  );
}
