import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:epd_controller/services/app_info.dart';

/// 版本信息与更新日志的单元测试。
///
/// 重点是「`AppVersion.version` 必须与 `pubspec.yaml` 一致」—— 忘了同步时 CI 会红。
void main() {
  group('版本号', () {
    test('与 pubspec.yaml 保持一致', () {
      final File file = File('pubspec.yaml');
      expect(file.existsSync(), isTrue, reason: '测试工作目录应当是工程根目录');
      final String content = file.readAsStringSync();
      final RegExpMatch? match = RegExp(r'^version:\s*(\S+)\s*$', multiLine: true)
          .firstMatch(content);
      expect(match, isNotNull, reason: 'pubspec.yaml 里找不到 version 字段');
      final String raw = match!.group(1)!;
      expect(
        raw,
        '${AppVersion.version}+${AppVersion.buildNumber}',
        reason: '改了 pubspec.yaml 的 version，请同步修改 AppVersion',
      );
    });

    test('fullVersion 拼装正确', () {
      expect(AppVersion.fullVersion, '${AppVersion.version}+${AppVersion.buildNumber}');
    });

    test('作者与仓库信息齐全', () {
      expect(AppVersion.authors, contains('Noyield'));
      expect(AppVersion.repoUrl, startsWith('https://github.com/'));
      expect(AppVersion.latestReleaseApi, endsWith('/releases/latest'));
    });
  });

  group('compareVersions', () {
    test('相等', () {
      expect(AppVersion.compareVersions('0.2.0', '0.2.0'), 0);
      expect(AppVersion.compareVersions('v0.2.0', '0.2.0'), 0);
      expect(AppVersion.compareVersions('0.2', '0.2.0'), 0);
    });

    test('新版本更大', () {
      expect(AppVersion.compareVersions('0.2.1', '0.2.0'), greaterThan(0));
      expect(AppVersion.compareVersions('0.3.0', '0.2.9'), greaterThan(0));
      expect(AppVersion.compareVersions('1.0.0', '0.99.99'), greaterThan(0));
      expect(AppVersion.compareVersions('0.10.0', '0.9.0'), greaterThan(0));
    });

    test('旧版本更小', () {
      expect(AppVersion.compareVersions('0.1.9', '0.2.0'), lessThan(0));
      expect(AppVersion.compareVersions('0.1.0', '0.2.0'), lessThan(0));
    });

    test('忽略构建号与预发布后缀', () {
      expect(AppVersion.compareVersions('0.2.0+3', '0.2.0'), 0);
      expect(AppVersion.compareVersions('0.2.0-rc1', '0.2.0'), 0);
    });
  });

  group('更新日志', () {
    test('最新版本排在最前，且包含当前版本', () {
      expect(kReleaseNotes, isNotEmpty);
      expect(kReleaseNotes.first.version, AppVersion.version);
    });

    test('每个版本都有日期与至少一条要点', () {
      for (final ReleaseNote note in kReleaseNotes) {
        expect(note.date, matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')),
            reason: '${note.version} 的日期格式不对');
        expect(note.highlights, isNotEmpty, reason: '${note.version} 没有要点');
      }
    });

    test('版本号从新到旧排列', () {
      for (int i = 1; i < kReleaseNotes.length; i++) {
        expect(
          AppVersion.compareVersions(
            kReleaseNotes[i - 1].version,
            kReleaseNotes[i].version,
          ),
          greaterThan(0),
          reason: '第 $i 条应当比第 ${i - 1} 条更旧',
        );
      }
    });
  });

  group('UpdateCheckResult', () {
    test('有更新', () {
      const UpdateCheckResult result = UpdateCheckResult(
        currentVersion: '0.2.0',
        latestVersion: '0.3.0',
        releaseName: 'v0.3.0',
        releaseUrl: 'https://example.com',
        publishedAt: '2026-12-01T00:00:00Z',
      );
      expect(result.hasUpdate, isTrue);
      expect(result.isUpToDate, isFalse);
    });

    test('已是最新', () {
      const UpdateCheckResult result = UpdateCheckResult(
        currentVersion: '0.2.0',
        latestVersion: '0.2.0',
      );
      expect(result.hasUpdate, isFalse);
      expect(result.isUpToDate, isTrue);
    });

    test('出错时既不算有更新也不算最新', () {
      const UpdateCheckResult result = UpdateCheckResult(
        currentVersion: '0.2.0',
        error: '网络不可用',
      );
      expect(result.hasUpdate, isFalse);
      expect(result.isUpToDate, isFalse);
    });
  });
}
