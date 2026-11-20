import 'package:flutter_test/flutter_test.dart';

import 'package:epd_controller/services/app_info.dart';
import 'package:epd_controller/services/update_checker.dart';

/// 更新检查的**纯逻辑**部分（不发网络请求）。
void main() {
  group('parseLatestRelease', () {
    test('正常响应解析出 tag / 标题 / 链接 / 发布时间', () {
      const String body = '''
{
  "tag_name": "v0.3.0",
  "name": "EPD Controller 0.3.0",
  "html_url": "https://github.com/Yuzgaf33tref6/EPD_nRF5_Controller/releases/tag/v0.3.0",
  "published_at": "2026-12-01T10:00:00Z"
}''';
      final UpdateCheckResult result = UpdateChecker.parseLatestRelease(body);
      expect(result.error, isNull);
      expect(result.currentVersion, AppVersion.version);
      expect(result.latestVersion, '0.3.0');
      expect(result.releaseName, 'EPD Controller 0.3.0');
      expect(result.releaseUrl, contains('/releases/tag/v0.3.0'));
      expect(result.publishedAt, '2026-12-01T10:00:00Z');
      expect(result.hasUpdate, isTrue);
    });

    test('没有 v 前缀也能解析', () {
      final UpdateCheckResult result = UpdateChecker.parseLatestRelease(
        '{"tag_name": "0.2.1"}',
      );
      expect(result.error, isNull);
      expect(result.latestVersion, '0.2.1');
    });

    test('同版本时算已是最新', () {
      final UpdateCheckResult result = UpdateChecker.parseLatestRelease(
        '{"tag_name": "v${AppVersion.version}"}',
      );
      expect(result.hasUpdate, isFalse);
      expect(result.isUpToDate, isTrue);
    });

    test('不是合法 JSON', () {
      final UpdateCheckResult result =
          UpdateChecker.parseLatestRelease('<html>502</html>');
      expect(result.error, contains('不是合法 JSON'));
    });

    test('JSON 不是对象', () {
      final UpdateCheckResult result =
          UpdateChecker.parseLatestRelease('[1, 2, 3]');
      expect(result.error, contains('不是预期的 JSON 对象'));
    });

    test('缺少 tag_name', () {
      final UpdateCheckResult result =
          UpdateChecker.parseLatestRelease('{"name": "x"}');
      expect(result.error, contains('tag_name'));
    });

    test('tag_name 为空串', () {
      final UpdateCheckResult result =
          UpdateChecker.parseLatestRelease('{"tag_name": "   "}');
      expect(result.error, contains('tag_name'));
    });
  });

  group('describeStatusCode', () {
    test('200 无错误', () {
      expect(UpdateChecker.describeStatusCode(200), isNull);
    });

    test('限流给出提示', () {
      expect(UpdateChecker.describeStatusCode(403), contains('限流'));
      expect(UpdateChecker.describeStatusCode(429), contains('限流'));
    });

    test('其他错误码带上状态码', () {
      expect(UpdateChecker.describeStatusCode(404), contains('404'));
      expect(UpdateChecker.describeStatusCode(500), contains('500'));
    });
  });
}
