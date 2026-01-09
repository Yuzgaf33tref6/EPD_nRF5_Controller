import 'package:flutter/material.dart';
import '../services/bluetooth_service.dart';
import 'image_editor_screen.dart';
import 'scan_screen.dart';

// Global BluetoothService instance shared across app
final _btService = BluetoothService();

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('EPD Controller')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ElevatedButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => ImageEditorScreen(bt: _btService)),
                ),
                child: const Text('打开图片编辑器'),
              ),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ScanScreen()),
                ),
                child: const Text('扫描并连接设备'),
              ),
              const SizedBox(height: 12),
              const Text('这是一个移植骨架：包含抖动算法、图像服务与简单 UI。'),
            ],
          ),
        ),
      ),
    );
  }
}
