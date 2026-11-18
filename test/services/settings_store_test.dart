import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:epd_controller/services/settings_store.dart';

void main() {
  // 用 MethodChannel 需要一个 binding 才能装 mock handler。
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MemorySettingsStore', () {
    test('初始为空', () async {
      final MemorySettingsStore store = MemorySettingsStore();
      expect(await store.load(), isNull);
      expect(store.saveCount, 0);
    });

    test('保存后能读回，且返回的是副本', () async {
      final MemorySettingsStore store = MemorySettingsStore();
      await store.save(<String, Object?>{'speed': 'fast'});
      expect(store.saveCount, 1);

      final Map<String, Object?>? loaded = await store.load();
      expect(loaded, isNotNull);
      expect(loaded!['speed'], 'fast');

      // 改返回值不应该影响 store 内部
      loaded['speed'] = 'stable';
      expect((await store.load())!['speed'], 'fast');
    });
  });

  group('FileSettingsStore', () {
    const MethodChannel channel =
        MethodChannel(FileSettingsStore.kSettingsChannel);
    late Directory tempDir;
    late List<MethodCall> calls;

    void mockChannel(Directory dir) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall call) async {
        calls.add(call);
        if (call.method == FileSettingsStore.kGetFilesDirMethod) {
          return dir.path;
        }
        throw MissingPluginException('未实现的方法：${call.method}');
      });
    }

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('epd_settings_test');
      calls = <MethodCall>[];
      mockChannel(tempDir);
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('首次读取返回 null（文件不存在）', () async {
      final FileSettingsStore store = FileSettingsStore();
      expect(await store.load(), isNull);
      // 拿过一次目录后应当缓存，不再重复问原生层
      await store.load();
      expect(
        calls.where((MethodCall c) => c.method == FileSettingsStore.kGetFilesDirMethod).length,
        1,
      );
    });

    test('保存后能从文件读回', () async {
      final FileSettingsStore store = FileSettingsStore();
      await store.save(<String, Object?>{'speed': 'fast', 'mtu': 247});

      final File file = File('${tempDir.path}${Platform.pathSeparator}epd_settings.json');
      expect(file.existsSync(), isTrue);
      final Map<String, Object?> onDisk =
          (jsonDecode(file.readAsStringSync()) as Map<Object?, Object?>)
              .map((Object? k, Object? v) => MapEntry<String, Object?>('$k', v));
      expect(onDisk['speed'], 'fast');
      expect(onDisk['mtu'], 247);

      final Map<String, Object?>? loaded = await store.load();
      expect(loaded, isNotNull);
      expect(loaded!['speed'], 'fast');
      expect(loaded['mtu'], 247);
    });

    test('文件内容坏掉时返回 null，不抛异常', () async {
      File('${tempDir.path}${Platform.pathSeparator}epd_settings.json')
          .writeAsStringSync('{ this is not json');
      final FileSettingsStore store = FileSettingsStore();
      expect(await store.load(), isNull);
    });

    test('内容不是对象（例如数组）时返回 null', () async {
      File('${tempDir.path}${Platform.pathSeparator}epd_settings.json')
          .writeAsStringSync('[1, 2, 3]');
      final FileSettingsStore store = FileSettingsStore();
      expect(await store.load(), isNull);
    });
  });
}
