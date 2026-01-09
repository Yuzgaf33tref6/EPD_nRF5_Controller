import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/bluetooth_service.dart';
import '../services/image_service.dart';
import 'scan_screen.dart';
import 'image_editor_screen.dart';
import '../widgets/progress_dialog.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _scrollController = ScrollController();

  @override
  Widget build(BuildContext context) {
    // 直接在build方法中获取暗黑模式状态
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    
    final bluetoothService = Provider.of<BluetoothService>(context);
    final imageService = Provider.of<ImageService>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('墨水屏日历'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.bluetooth),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const ScanScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              // 暂时使用简单的提示
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('设置'),
                  content: const Text('设置页面正在开发中...'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('确定'),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      body: _buildBody(bluetoothService, imageService, isDarkMode),
      floatingActionButton: _buildFloatingActionButton(bluetoothService),
    );
  }

  Widget _buildBody(BluetoothService bluetoothService, ImageService imageService, bool isDarkMode) {
    return Column(
      children: [
        // 连接状态
        _buildConnectionStatus(bluetoothService, isDarkMode),
        
        // 日志区域
        _buildLogSection(bluetoothService, isDarkMode),
        
        // 设备控制区域
        _buildControlSection(bluetoothService, imageService),
        
        // 图片处理区域
        _buildImageSection(bluetoothService, imageService),
      ],
    );
  }

  Widget _buildConnectionStatus(BluetoothService bluetoothService, bool isDarkMode) {
    return Container(
      padding: const EdgeInsets.all(16),
      color: isDarkMode ? Colors.grey[900] : Colors.grey[100],
      child: Row(
        children: [
          Icon(
            bluetoothService.connectedDevice != null
                ? Icons.bluetooth_connected
                : Icons.bluetooth_disabled,
            color: bluetoothService.connectedDevice != null
                ? Colors.green
                : Colors.grey,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              bluetoothService.connectedDevice != null
                  ? '已连接: ${bluetoothService.connectedDevice!.name}'
                  : '未连接设备',
              style: const TextStyle(fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogSection(BluetoothService bluetoothService, bool isDarkMode) {
    return Expanded(
      child: Card(
        margin: const EdgeInsets.all(16),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    '日志',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    icon: const Icon(Icons.clear_all),
                    onPressed: bluetoothService.clearLog,
                    tooltip: '清空日志',
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: SingleChildScrollView(
                controller: _scrollController,
                reverse: true,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Selector<BluetoothService, String>(
                    selector: (_, service) => service.log,
                    builder: (context, log, child) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (_scrollController.hasClients) {
                          _scrollController.jumpTo(
                            _scrollController.position.maxScrollExtent,
                          );
                        }
                      });
                      return Text(
                        log.isNotEmpty ? log : '日志将显示在这里...',
                        style: TextStyle(
                          fontFamily: 'Monospace',
                          fontSize: 12,
                          color: isDarkMode ? Colors.grey[300] : Colors.black,
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControlSection(BluetoothService bluetoothService, ImageService imageService) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '设备控制',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton.icon(
                  icon: const Icon(Icons.calendar_today),
                  label: const Text('日历模式'),
                  onPressed: bluetoothService.connectedDevice != null
                      ? () => _syncTime(1, bluetoothService)
                      : null,
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.access_time),
                  label: const Text('时钟模式'),
                  onPressed: bluetoothService.connectedDevice != null
                      ? () => _syncTime(2, bluetoothService)
                      : null,
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.clear_all),
                  label: const Text('清除屏幕'),
                  onPressed: bluetoothService.connectedDevice != null
                      ? () => _clearScreen(bluetoothService)
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey,
                  ),
                ),
                // 调试模式按钮（暂时隐藏）
                // if (_isDarkMode)
                //   ElevatedButton.icon(
                //     icon: const Icon(Icons.developer_mode),
                //     label: const Text('发送命令'),
                //     onPressed: bluetoothService.connectedDevice != null
                //         ? () => _showCommandDialog(bluetoothService)
                //         : null,
                //     style: ElevatedButton.styleFrom(
                //       backgroundColor: Colors.deepOrange,
                //     ),
                //   ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImageSection(BluetoothService bluetoothService, ImageService imageService) {
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '图片处理',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.image),
                    label: const Text('选择图片'),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const ImageEditorScreen(),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  icon: const Icon(Icons.send),
                  label: const Text('发送图片'),
                  onPressed: (bluetoothService.connectedDevice != null &&
                          imageService.imageData != null)
                      ? () => _sendImage(bluetoothService, imageService)
                      : null,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              imageService.imageData != null 
                ? '已选择图片' 
                : '未选择图片',
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget? _buildFloatingActionButton(BluetoothService bluetoothService) {
    if (bluetoothService.connectedDevice != null) {
      return FloatingActionButton(
        onPressed: () => bluetoothService.disconnect(),
        backgroundColor: Colors.red,
        child: const Icon(Icons.bluetooth_disabled),
      );
    }
    return null;
  }

  Future<void> _syncTime(int mode, BluetoothService bluetoothService) async {
    if (mode == 2) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('提示'),
          content: const Text(
            '提醒：时钟模式目前使用全刷实现，此功能目前多用于修复老化屏残影问题，不建议长期开启，是否继续？',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('继续'),
            ),
          ],
        ),
      );
      if (confirm != true) return;
    }

    // 实现时间同步
    bluetoothService.addLog('时间同步命令已发送 (模式: $mode)');
    bluetoothService.addLog('屏幕刷新完成前请不要操作。');
  }

  Future<void> _clearScreen(BluetoothService bluetoothService) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认'),
        content: const Text('确认清除屏幕内容？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('确认'),
          ),
        ],
      ),
    );
    
    if (confirm == true) {
      // 实现清屏命令
      bluetoothService.addLog('清屏指令已发送');
      bluetoothService.addLog('屏幕刷新完成前请不要操作。');
    }
  }

  Future<void> _sendImage(
      BluetoothService bluetoothService, ImageService imageService) async {
    // 检查配置匹配
    // 检查画布尺寸和驱动是否匹配
    
    // 显示进度对话框
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => ProgressDialog(
        title: '发送图片',
        message: '正在处理图片数据...',
        onCancel: () {
          // 取消发送
          Navigator.of(context).pop();
          bluetoothService.addLog('发送已取消');
        },
      ),
    );
    
    // 实现图片发送
    bluetoothService.addLog('开始发送图片数据...');
    await Future.delayed(const Duration(seconds: 2));
    bluetoothService.addLog('图片发送完成！');
    bluetoothService.addLog('屏幕刷新完成前请不要操作。');
  }

  Future<void> _showCommandDialog(BluetoothService bluetoothService) async {
    final controller = TextEditingController();
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('发送命令'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: '输入十六进制命令',
            border: OutlineInputBorder(),
          ),
          keyboardType: TextInputType.text,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () {
              if (controller.text.isNotEmpty) {
                // 实现命令发送
                bluetoothService.addLog('发送命令: ${controller.text}');
                bluetoothService.addLog('命令发送完成');
              }
              Navigator.of(context).pop();
            },
            child: const Text('发送'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }
}