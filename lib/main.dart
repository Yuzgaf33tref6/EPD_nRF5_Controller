import 'package:flutter/material.dart';

import 'app.dart';
import 'services/ble_service.dart';

export 'app.dart' show EpdControllerApp;

void main() {
  // 真机入口注入真实 BLE 实现；测试直接 new EpdControllerApp() 用模拟蓝牙。
  runApp(EpdControllerApp(bleService: ReactiveBleService()));
}
