import 'dart:async';
import 'package:flutter/material.dart';
import '../services/bluetooth_service.dart';
import '../models/epd_device.dart';
import 'settings_screen.dart';

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final BluetoothService _bt = BluetoothService();
  final Map<String, EpdDevice> _devices = {};
  StreamSubscription? _scanSub;
  bool _scanning = false;
  bool _connected = false;
  String _connectedName = '';
  String _logs = '';

  @override
  void initState() {
    super.initState();
    // Listen to notifications from device
    _bt.notifyStream.listen((data) {
      _addLog('📥 ${data.toString()}');
    });
  }

  void _addLog(String msg) {
    setState(() {
      _logs = '$msg\n$_logs';
      if (_logs.split('\n').length > 50) {
        _logs = _logs.split('\n').take(50).join('\n');
      }
    });
  }

  void _startScan() async {
    // Request permissions first
    final hasPerms = await _bt.ensurePermissions();
    if (!hasPerms) {
      _addLog('❌ 蓝牙权限被拒绝');
      return;
    }
    _devices.clear();
    setState(() => _scanning = true);
    _bt.startScan();
    _addLog('🔍 开始扫描...');
    _scanSub = _bt.scanStream.listen((d) {
      setState(() {
        _devices[d.id] = EpdDevice(id: d.id, name: d.name.isEmpty ? 'Unknown' : d.name, rssi: d.rssi);
      });
    });
  }

  void _stopScan() {
    _scanSub?.cancel();
    _scanSub = null;
    _bt.stopScan();
    setState(() => _scanning = false);
    _addLog('⏹️ 停止扫描');
  }

  Future<void> _connect(String id, String name) async {
    setState(() => _scanning = false);
    _stopScan();
    _addLog('🔗 正在连接 $name...');
    final ok = await _bt.connect(id);
    if (ok) {
      setState(() {
        _connected = true;
        _connectedName = name;
      });
      _addLog('✅ 已连接到 $name');
    } else {
      _addLog('❌ 连接失败');
    }
  }

  Future<void> _disconnect() async {
    await _bt.disconnect();
    setState(() {
      _connected = false;
      _connectedName = '';
    });
    _addLog('👋 已断开连接');
  }

  @override
  void dispose() {
    _scanSub?.cancel();
    _bt.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('蓝牙设备')),
      body: Column(
        children: [
          // Connection status
          Container(
            color: _connected ? Colors.green.shade100 : Colors.grey.shade100,
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(_connected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
                    color: _connected ? Colors.green : Colors.grey),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _connected ? '✓ 已连接: $_connectedName' : '✗ 未连接',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: _connected ? Colors.green.shade700 : Colors.grey.shade700,
                    ),
                  ),
                ),
                if (_connected)
                  ElevatedButton(
                    onPressed: _disconnect,
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                    child: const Text('断开'),
                  ),
              ],
            ),
          ),
          // Scan controls
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                ElevatedButton(
                  onPressed: _scanning ? _stopScan : _startScan,
                  child: Text(_scanning ? '停止扫描' : '开始扫描'),
                ),
                const SizedBox(width: 12),
                Text('设备数: ${_devices.length}'),
                const Spacer(),
                if (_connected)
                  ElevatedButton(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => ControlScreen(bt: _bt)),
                    ),
                    child: const Text('设备控制'),
                  ),
              ],
            ),
          ),
          // Device list
          Expanded(
            child: _devices.isEmpty
                ? Center(
                    child: Text(_scanning ? '扫描中...' : '无设备',
                        style: const TextStyle(color: Colors.grey)),
                  )
                : ListView(
                    children: _devices.values.map((d) => ListTile(
                      title: Text(d.name),
                      subtitle: Text(d.id),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (d.rssi != null) Text('${d.rssi} dBm', style: const TextStyle(fontSize: 12)),
                          const SizedBox(height: 4),
                          ElevatedButton(
                            onPressed: () => _connect(d.id, d.name),
                            child: const Text('连接'),
                          ),
                        ],
                      ),
                    )).toList(),
                  ),
          ),
          // Logs
          Container(
            padding: const EdgeInsets.all(8),
            height: 150,
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: Colors.grey.shade300)),
              color: Colors.grey.shade50,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('日志', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                Expanded(
                  child: SingleChildScrollView(
                    child: Text(
                      _logs.isEmpty ? '(无日志)' : _logs,
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
