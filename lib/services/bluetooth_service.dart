import 'package:flutter/foundation.dart';
import '../models/epd_device.dart';

class BluetoothService extends ChangeNotifier {
  List<EpdDevice> devices = [];
  EpdDevice? connectedDevice;
  bool isScanning = false;
  String log = '';
  
  // 扫描控制
  Future<void> startScan() async {
    isScanning = true;
    notifyListeners();
    // TODO: 实现蓝牙扫描
  }
  
  Future<void> stopScan() async {
    isScanning = false;
    notifyListeners();
  }
  
  // 连接管理
  Future<bool> connect(EpdDevice device) async {
    // TODO: 实现蓝牙连接
    connectedDevice = device;
    notifyListeners();
    return true;
  }
  
  Future<void> disconnect() async {
    connectedDevice = null;
    notifyListeners();
  }
  
  // 日志管理
  void addLog(String message) {
    final now = DateTime.now();
    final time = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
    log = '$log$time $message\n';
    notifyListeners();
  }
  
  void clearLog() {
    log = '';
    notifyListeners();
  }
}