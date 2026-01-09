import 'dart:typed_data';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image/image.dart' as img;
import '../utils/dither_algorithms.dart';
import '../services/bluetooth_service.dart';

class ImageEditorScreen extends StatefulWidget {
  final BluetoothService? bt;
  const ImageEditorScreen({super.key, this.bt});

  @override
  State<ImageEditorScreen> createState() => _ImageEditorScreenState();
}

class _ImageEditorScreenState extends State<ImageEditorScreen> {
  Uint8List? originalBytes;
  Uint8List? processedBytes;
  String ditherMode = 'sixColor';
  String ditherAlg = 'floydSteinberg';
  double ditherStrength = 1.0;
  double ditherContrast = 1.2;

  Future<void> pickImage() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image);
    if (result == null) return;
    Uint8List bytes;
    if (result.files.single.bytes != null) {
      bytes = result.files.single.bytes!;
    } else if (result.files.single.path != null) {
      bytes = await File(result.files.single.path!).readAsBytes();
    } else {
      return;
    }
    setState(() {
      originalBytes = bytes;
      processedBytes = null;
    });
  }

  Future<void> applyDither() async {
    if (originalBytes == null) return;
    // decode image
    final image = img.decodeImage(originalBytes!);
    if (image == null) return;
    final rgba = image.getBytes(); // RGBA
    final width = image.width;
    final height = image.height;

    // apply contrast adjustment
    final adjusted = Uint8List.fromList(rgba);
    for (int i = 0; i < adjusted.length; i += 4) {
      adjusted[i] = _adjustContrastByte(adjusted[i], ditherContrast);
      adjusted[i + 1] = _adjustContrastByte(adjusted[i + 1], ditherContrast);
      adjusted[i + 2] = _adjustContrastByte(adjusted[i + 2], ditherContrast);
    }

    final out = DitherAlgorithms.processImageRGBA(adjusted, width, height,
        strength: ditherStrength, mode: ditherMode, alg: ditherAlg);

    setState(() {
      processedBytes = out;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('图片编辑器')),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            Row(
              children: [
                ElevatedButton(onPressed: pickImage, child: const Text('选择图片')),
                const SizedBox(width: 8),
                ElevatedButton(onPressed: applyDither, child: const Text('应用抖动')),
                const SizedBox(width: 12),
                ElevatedButton(
                    onPressed: () {
                      if (processedBytes != null) {
                        File('${Directory.systemTemp.path}/epd_processed.png').writeAsBytesSync(processedBytes!);
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已保存到临时目录')));
                      }
                    },
                    child: const Text('保存预览')),
                const SizedBox(width: 8),
                ElevatedButton(
                    onPressed: processedBytes != null && widget.bt != null ? () => _sendToDevice() : null,
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                    child: const Text('发送到设备')),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                DropdownButton<String>(
                  value: ditherMode,
                  items: const [
                    DropdownMenuItem(value: 'blackWhiteColor', child: Text('双色 (黑白)')),
                    DropdownMenuItem(value: 'threeColor', child: Text('三色 (黑白红)')),
                    DropdownMenuItem(value: 'fourColor', child: Text('四色 (黑白红黄)')),
                    DropdownMenuItem(value: 'sixColor', child: Text('六色')),
                  ],
                  onChanged: (v) => setState(() => ditherMode = v!),
                ),
                DropdownButton<String>(
                  value: ditherAlg,
                  items: const [
                    DropdownMenuItem(value: 'floydSteinberg', child: Text('Floyd-Steinberg')),
                    DropdownMenuItem(value: 'atkinson', child: Text('Atkinson')),
                    DropdownMenuItem(value: 'stucki', child: Text('Stucki')),
                    DropdownMenuItem(value: 'jarvis', child: Text('Jarvis')),
                    DropdownMenuItem(value: 'none', child: Text('无')),
                  ],
                  onChanged: (v) => setState(() => ditherAlg = v!),
                ),
                SizedBox(
                  width: 200,
                  child: Row(
                    children: [
                      const Text('强度'),
                      Expanded(
                        child: Slider(
                          value: ditherStrength,
                          min: 0,
                          max: 5,
                          divisions: 50,
                          label: ditherStrength.toStringAsFixed(2),
                          onChanged: (v) => setState(() => ditherStrength = v),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  width: 200,
                  child: Row(
                    children: [
                      const Text('对比度'),
                      Expanded(
                        child: Slider(
                          value: ditherContrast,
                          min: 0.5,
                          max: 2.0,
                          divisions: 15,
                          label: ditherContrast.toStringAsFixed(2),
                          onChanged: (v) => setState(() => ditherContrast = v),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    if (originalBytes != null) ...[
                      const Text('原图'),
                      Image.memory(originalBytes!),
                    ],
                    if (processedBytes != null) ...[
                      const SizedBox(height: 12),
                      const Text('处理后（RGBA raw -> PNG preview）'),
                      Image.memory(processedBytes!),
                    ]
                  ],
                ),
              ),
            )
          ],
        ),
      ),
    );
  }

  int _adjustContrastByte(int v, double factor) {
    final d = ((v - 128) * factor + 128).round();
    if (d < 0) return 0;
    if (d > 255) return 255;
    return d;
  }

  Future<void> _sendToDevice() async {
    if (processedBytes == null || widget.bt == null) return;
    final ok = await widget.bt!.writeImageChunks(
      processedBytes!,
      mtu: 256,
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ok ? '✓ 发送成功' : '✗ 发送失败')),
      );
    }
  }
}
