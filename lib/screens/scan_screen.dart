import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/bluetooth_service.dart';
import '../models/epd_device.dart';
import '../widgets/device_card.dart';

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startScanning();
    });
  }

  void _startScanning() {
    final bluetoothService = Provider.of<BluetoothService>(
      context,
      listen: false,
    );
    bluetoothService.startScan();
  }

  @override
  Widget build(BuildContext context) {
    final bluetoothService = Provider.of<BluetoothService>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('设备扫描'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            bluetoothService.stopScan();
            Navigator.of(context).pop();
          },
        ),
      ),
      body: Column(
        children: [
          // 扫描控制
          _buildScanControls(bluetoothService),
          
          // 设备列表
          _buildDeviceList(bluetoothService),
        ],
      ),
    );
  }

  Widget _buildScanControls(BluetoothService bluetoothService) {
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    bluetoothService.isScanning
                        ? '正在扫描设备...'
                        : '扫描已停止',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '已发现 ${bluetoothService.devices.length} 个设备',
                    style: const TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            IconButton(
              icon: Icon(
                bluetoothService.isScanning
                    ? Icons.stop
                    : Icons.refresh,
                size: 30,
              ),
              onPressed: () {
                if (bluetoothService.isScanning) {
                  bluetoothService.stopScan();
                } else {
                  bluetoothService.startScan();
                }
              },
              tooltip: bluetoothService.isScanning ? '停止扫描' : '重新扫描',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeviceList(BluetoothService bluetoothService) {
    return Expanded(
      child: RefreshIndicator(
        onRefresh: () async {
          bluetoothService.stopScan();
          await Future.delayed(const Duration(milliseconds: 500));
          bluetoothService.startScan();
        },
        child: Consumer<BluetoothService>(
          builder: (context, service, child) {
            final devices = service.devices;
            
            if (devices.isEmpty && !service.isScanning) {
              return const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.bluetooth_searching,
                      size: 64,
                      color: Colors.grey,
                    ),
                    SizedBox(height: 16),
                    Text(
                      '未发现设备',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              );
            }

            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: devices.length,
              itemBuilder: (context, index) {
                final device = devices[index];
                return DeviceCard(
                  device: device,
                  onConnect: () => _connectToDevice(service, device),
                  onDisconnect: () => service.disconnect(),
                );
              },
            );
          },
        ),
      ),
    );
  }

  Future<void> _connectToDevice(
      BluetoothService service, EpdDevice device) async {
    final connected = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('连接设备'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text('正在连接 ${device.name}...'),
          ],
        ),
      ),
    );

    if (connected == true && mounted) {
      Navigator.of(context).pop();
    }
  }
}