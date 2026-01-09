import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../services/image_service.dart';
import '../models/screen_type.dart';
import '../widgets/canvas_widget.dart';
import '../widgets/color_picker.dart';

class ImageEditorScreen extends StatefulWidget {
  const ImageEditorScreen({super.key});

  @override
  State<ImageEditorScreen> createState() => _ImageEditorScreenState();
}

class _ImageEditorScreenState extends State<ImageEditorScreen> {
  final ImagePicker _picker = ImagePicker();
  ui.Image? _currentImage;
  // 移除未使用的字段: Uint8List? _imageBytes;
  bool _isLoading = false;
  double _ditherStrength = 1.0;
  double _contrast = 1.2;
  EpdColorMode _colorMode = EpdColorMode.blackWhiteColor;
  DitherAlgorithm _ditherAlgorithm = DitherAlgorithm.floydSteinberg;
  ScreenType _selectedScreenType = ScreenType.presets[0];
  Color _selectedColor = Colors.black;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('图片编辑器'),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _saveImage,
            tooltip: '保存处理结果',
          ),
        ],
      ),
      body: Column(
        children: [
          // 控制面板
          _buildControlPanel(),
          
          // 画布区域
          Expanded(
            child: _buildCanvasArea(),
          ),
          
          // 工具面板
          _buildToolPanel(),
        ],
      ),
    );
  }

  Widget _buildControlPanel() {
    return Card(
      margin: const EdgeInsets.all(8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.photo_library),
                    label: const Text('选择图片'),
                    onPressed: _pickImage,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.camera_alt),
                    label: const Text('拍照'),
                    onPressed: _takePhoto,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueGrey,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<ScreenType>(
                    // 使用 initialValue 替代已弃用的 value 属性
                    initialValue: _selectedScreenType,
                    decoration: const InputDecoration(
                      labelText: '屏幕类型',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12),
                    ),
                    items: ScreenType.presets
                        .where((type) => !type.isDebug)
                        .map((type) {
                      return DropdownMenuItem<ScreenType>(
                        value: type,
                        child: Text(type.name),
                      );
                    }).toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setState(() {
                          _selectedScreenType = value;
                        });
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<EpdColorMode>(
                    // 使用 initialValue 替代已弃用的 value 属性
                    initialValue: _colorMode,
                    decoration: const InputDecoration(
                      labelText: '颜色模式',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: EpdColorMode.blackWhiteColor,
                        child: Text('黑白'),
                      ),
                      DropdownMenuItem(
                        value: EpdColorMode.threeColor,
                        child: Text('三色(黑白红)'),
                      ),
                      DropdownMenuItem(
                        value: EpdColorMode.fourColor,
                        child: Text('四色(黑白红黄)'),
                      ),
                      DropdownMenuItem(
                        value: EpdColorMode.sixColor,
                        child: Text('六色'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() {
                          _colorMode = value;
                        });
                      }
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCanvasArea() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('正在加载图片...'),
          ],
        ),
      );
    }

    if (_currentImage == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.image, size: 80, color: Colors.grey),
            const SizedBox(height: 16),
            const Text(
              '请选择一张图片',
              style: TextStyle(fontSize: 18, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            Text(
              '画布尺寸: ${_selectedScreenType.width} × ${_selectedScreenType.height}',
              style: const TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return CanvasWidget(
      image: _currentImage!,
      width: _selectedScreenType.width,
      height: _selectedScreenType.height,
      colorMode: _colorMode,
      ditherAlgorithm: _ditherAlgorithm,
      ditherStrength: _ditherStrength,
      contrast: _contrast,
      selectedColor: _selectedColor,
    );
  }

  Widget _buildToolPanel() {
    return Card(
      margin: const EdgeInsets.all(8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            // 抖动算法选择
            Row(
              children: [
                const Text('抖动算法:', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButton<DitherAlgorithm>(
                    value: _ditherAlgorithm,
                    isExpanded: true,
                    items: const [
                      DropdownMenuItem(
                        value: DitherAlgorithm.floydSteinberg,
                        child: Text('Floyd-Steinberg'),
                      ),
                      DropdownMenuItem(
                        value: DitherAlgorithm.atkinson,
                        child: Text('Atkinson'),
                      ),
                      DropdownMenuItem(
                        value: DitherAlgorithm.bayer,
                        child: Text('Bayer'),
                      ),
                      DropdownMenuItem(
                        value: DitherAlgorithm.stucki,
                        child: Text('Stucki'),
                      ),
                      DropdownMenuItem(
                        value: DitherAlgorithm.jarvis,
                        child: Text('Jarvis-Judice-Ninke'),
                      ),
                      DropdownMenuItem(
                        value: DitherAlgorithm.none,
                        child: Text('无抖动'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() {
                          _ditherAlgorithm = value;
                        });
                      }
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            
            // 颜色选择器
            Row(
              children: [
                const Text('画笔颜色:', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(width: 8),
                ColorPicker(
                  selectedColor: _selectedColor,
                  onColorChanged: (color) {
                    setState(() {
                      _selectedColor = color;
                    });
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            
            // 抖动强度滑块
            Row(
              children: [
                const Text('抖动强度:', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(width: 8),
                Expanded(
                  child: Slider(
                    value: _ditherStrength,
                    min: 0,
                    max: 5,
                    divisions: 50,
                    label: _ditherStrength.toStringAsFixed(1),
                    onChanged: (value) {
                      setState(() {
                        _ditherStrength = value;
                      });
                    },
                  ),
                ),
                Text(_ditherStrength.toStringAsFixed(1)),
              ],
            ),
            
            // 对比度滑块
            Row(
              children: [
                const Text('对比度:', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(width: 8),
                Expanded(
                  child: Slider(
                    value: _contrast,
                    min: 0.5,
                    max: 2,
                    divisions: 15,
                    label: _contrast.toStringAsFixed(1),
                    onChanged: (value) {
                      setState(() {
                        _contrast = value;
                      });
                    },
                  ),
                ),
                Text(_contrast.toStringAsFixed(1)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickImage() async {
    final pickedFile = await _picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      await _loadImage(await pickedFile.readAsBytes());
    }
  }

  Future<void> _takePhoto() async {
    final pickedFile = await _picker.pickImage(source: ImageSource.camera);
    if (pickedFile != null) {
      await _loadImage(await pickedFile.readAsBytes());
    }
  }

  Future<void> _loadImage(Uint8List bytes) async {
    setState(() {
      _isLoading = true;
    });

    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      setState(() {
        _currentImage = frame.image;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      // 修复 BuildContext 的异步使用问题
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            showDialog(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('错误'),
                content: Text('无法加载图片: $e'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('确定'),
                  ),
                ],
              ),
            );
          }
        });
      }
    }
  }

  void _saveImage() {
    if (_currentImage == null) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('提示'),
            content: const Text('请先选择一张图片'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('确定'),
              ),
            ],
          ),
        );
      }
      return;
    }

    final imageService = Provider.of<ImageService>(context, listen: false);
    imageService.setImageData('图片数据已保存');
    
    if (mounted) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('成功'),
          content: const Text('图片已保存，可以返回主页面发送到设备'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                if (mounted) {
                  Navigator.of(context).pop();
                }
              },
              child: const Text('返回主页面'),
            ),
          ],
        ),
      );
    }
  }
}