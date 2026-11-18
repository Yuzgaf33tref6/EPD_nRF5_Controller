import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

/// 设置持久化的抽象。
///
/// 之所以不用 `shared_preferences`：那个插件要求 AGP 8.13.1 / Kotlin 2.3.0，
/// 比本项目（AGP 8.11.1 / Kotlin 2.2.20）高，有编译不过的风险。
/// 这里改成「往 App 私有目录写一个 JSON 文件」，Android 侧只需要一个
/// MethodChannel 把 `filesDir` 告诉 Dart，零第三方依赖。
abstract class SettingsStore {
  /// 读取已保存的设置；文件不存在或内容坏了都返回 null（不抛异常）。
  Future<Map<String, Object?>?> load();

  /// 覆盖保存一份设置。
  Future<void> save(Map<String, Object?> data);
}

/// 内存实现：单元测试与 widget 测试用，不碰文件系统。
class MemorySettingsStore implements SettingsStore {
  MemorySettingsStore([Map<String, Object?>? initial])
      : _data = initial == null ? null : Map<String, Object?>.from(initial);

  Map<String, Object?>? _data;

  /// 累计保存次数，测试用来断言「改设置确实会写出去」。
  int saveCount = 0;

  /// 最近一次保存的内容。
  Map<String, Object?>? get data =>
      _data == null ? null : Map<String, Object?>.from(_data!);

  @override
  Future<Map<String, Object?>?> load() async => data;

  @override
  Future<void> save(Map<String, Object?> data) async {
    _data = Map<String, Object?>.from(data);
    saveCount++;
  }
}

/// 写进 App 私有目录的 JSON 文件实现。
class FileSettingsStore implements SettingsStore {
  FileSettingsStore({
    MethodChannel channel = const MethodChannel(kSettingsChannel),
    this.fileName = 'epd_settings.json',
  }) : _channel = channel;

  /// 与 Android 侧 `MainActivity` 约定的通道名。
  static const String kSettingsChannel = 'epd_controller/storage';

  /// 与 Android 侧约定的方法名，返回 App 私有目录的绝对路径。
  static const String kGetFilesDirMethod = 'getFilesDir';

  final MethodChannel _channel;
  final String fileName;

  File? _cachedFile;

  Future<File> _file() async {
    final File? cached = _cachedFile;
    if (cached != null) {
      return cached;
    }
    final String? dir = await _channel.invokeMethod<String>(kGetFilesDirMethod);
    if (dir == null || dir.isEmpty) {
      throw StateError('拿不到 App 私有目录（$kGetFilesDirMethod 返回空）');
    }
    final File file = File('$dir${Platform.pathSeparator}$fileName');
    _cachedFile = file;
    return file;
  }

  @override
  Future<Map<String, Object?>?> load() async {
    try {
      final File file = await _file();
      if (!file.existsSync()) {
        return null;
      }
      final Object? decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) {
        return null;
      }
      return decoded.map(
        (Object? key, Object? value) => MapEntry<String, Object?>('$key', value),
      );
    } catch (_) {
      // 读不出来就当没有设置，绝不因为设置文件而崩。
      return null;
    }
  }

  @override
  Future<void> save(Map<String, Object?> data) async {
    final File file = await _file();
    // 先写临时文件再改名，避免写到一半掉电留下半个 JSON。
    final File tmp = File('${file.path}.tmp');
    await tmp.writeAsString(jsonEncode(data), flush: true);
    await tmp.rename(file.path);
  }
}
