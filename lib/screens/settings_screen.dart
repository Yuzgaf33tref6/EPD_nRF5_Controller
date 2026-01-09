import 'package:flutter/material.dart';
import '../services/bluetooth_service.dart';

class ControlScreen extends StatefulWidget {
  final BluetoothService bt;
  const ControlScreen({super.key, required this.bt});

  @override
  State<ControlScreen> createState() => _ControlScreenState();
}

class _ControlScreenState extends State<ControlScreen> {
  bool _sending = false;
  String _logs = '';

  void _log(String msg) {
    setState(() {
      _logs = '$msg\n$_logs';
    });
  }

  Future<void> _clearScreen() async {
    setState(() => _sending = true);
    final ok = await widget.bt.clearScreen();
    _log(ok ? '✓ 清屏成功' : '✗ 清屏失败');
    setState(() => _sending = false);
  }

  Future<void> _refresh() async {
    setState(() => _sending = true);
    final ok = await widget.bt.refresh();
    _log(ok ? '✓ 刷新成功' : '✗ 刷新失败');
    setState(() => _sending = false);
  }

  Future<void> _syncTime(int mode) async {
    setState(() => _sending = true);
    final ok = await widget.bt.setTime(mode);
    final modeStr = mode == 1 ? '日历' : mode == 2 ? '时钟' : '未知';
    _log(ok ? '✓ 时间同步成功 ($modeStr)' : '✗ 时间同步失败');
    setState(() => _sending = false);
  }

  Future<void> _sleep() async {
    setState(() => _sending = true);
    final ok = await widget.bt.sleep();
    _log(ok ? '✓ 设备进入睡眠' : '✗ 睡眠命令失败');
    setState(() => _sending = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设备控制')),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('设备操作', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ElevatedButton(
                    onPressed: _sending ? null : _clearScreen,
                    child: const Text('清除屏幕'),
                  ),
                  ElevatedButton(
                    onPressed: _sending ? null : _refresh,
                    child: const Text('刷新屏幕'),
                  ),
                  ElevatedButton(
                    onPressed: _sending ? null : () => _syncTime(1),
                    child: const Text('日历模式'),
                  ),
                  ElevatedButton(
                    onPressed: _sending ? null : () => _syncTime(2),
                    child: const Text('时钟模式'),
                  ),
                  ElevatedButton(
                    onPressed: _sending ? null : _sleep,
                    child: const Text('进入睡眠'),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              const Text('操作日志', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(border: Border.all(), borderRadius: BorderRadius.circular(4)),
                child: Text(_logs.isEmpty ? '(无日志)' : _logs, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
