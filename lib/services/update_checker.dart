import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'app_info.dart';

/// 更新检查：查询 GitHub 上的最新 release，与当前版本比较。
///
/// 只有用户主动点「检查更新」时才会调用，启动时不联网。
class UpdateChecker {
  UpdateChecker({
    HttpClient Function()? httpClientFactory,
    this.timeout = const Duration(seconds: 12),
    String? apiUrl,
  })  : _httpClientFactory = httpClientFactory ?? HttpClient.new,
        _apiUrl = apiUrl ?? AppVersion.latestReleaseApi;

  final HttpClient Function() _httpClientFactory;
  final Duration timeout;
  final String _apiUrl;

  /// 把 GitHub `/releases/latest` 的响应体解析成 [UpdateCheckResult]。
  ///
  /// 抽成静态方法是为了能在不加网络的前提下单测（见 `test/services/update_checker_test.dart`）。
  static UpdateCheckResult parseLatestRelease(String body) {
    final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException catch (error) {
      return UpdateCheckResult(
        currentVersion: AppVersion.version,
        error: '查询失败：返回内容不是合法 JSON（${error.message}）',
      );
    }
    if (decoded is! Map<String, Object?>) {
      return UpdateCheckResult(
        currentVersion: AppVersion.version,
        error: '查询失败：返回内容不是预期的 JSON 对象',
      );
    }
    final String? tag = decoded['tag_name'] as String?;
    if (tag == null || tag.trim().isEmpty) {
      return UpdateCheckResult(
        currentVersion: AppVersion.version,
        error: '查询失败：没有找到 tag_name',
      );
    }
    final String latest = tag.trim().replaceFirst(RegExp('^[vV]'), '');
    return UpdateCheckResult(
      currentVersion: AppVersion.version,
      latestVersion: latest,
      releaseName: decoded['name'] as String?,
      releaseUrl: decoded['html_url'] as String?,
      publishedAt: decoded['published_at'] as String?,
    );
  }

  /// 把 HTTP 状态码翻译成可读错误（200 之外都算失败）。
  static String? describeStatusCode(int statusCode) {
    if (statusCode == 200) {
      return null;
    }
    if (statusCode == 403 || statusCode == 429) {
      return 'GitHub 接口被限流了（HTTP $statusCode），过一会儿再试';
    }
    return '查询失败：HTTP $statusCode';
  }

  /// 查询最新 release。任何失败都收敛成 [UpdateCheckResult.error]，不抛异常。
  Future<UpdateCheckResult> check() async {
    final HttpClient client = _httpClientFactory()
      ..connectionTimeout = timeout
      ..userAgent = 'EPD-Controller/${AppVersion.fullVersion}';
    try {
      final HttpClientRequest request = await client
          .getUrl(Uri.parse(_apiUrl))
          .timeout(timeout);
      request.headers.set(
        HttpHeaders.acceptHeader,
        'application/vnd.github+json',
      );
      request.headers.set('X-GitHub-Api-Version', '2022-11-28');
      final HttpClientResponse response = await request.close().timeout(timeout);
      final String body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(timeout);
      final String? statusError = describeStatusCode(response.statusCode);
      if (statusError != null) {
        return UpdateCheckResult(
          currentVersion: AppVersion.version,
          error: statusError,
        );
      }
      final UpdateCheckResult parsed = parseLatestRelease(body);
      if (parsed.error == null) {
        debugPrint(
          '[EPD] 更新检查：本地 ${AppVersion.version}，远端 ${parsed.latestVersion}',
        );
      }
      return parsed;
    } catch (error) {
      debugPrint('[EPD] 更新检查失败：$error');
      return UpdateCheckResult(
        currentVersion: AppVersion.version,
        error: _describeNetworkError(error),
      );
    } finally {
      client.close(force: true);
    }
  }

  /// 把网络异常翻译成用户能看懂的话。
  ///
  /// 最常见的两类是：没有网络权限/没有网络（DNS 解析失败）与超时。
  static String _describeNetworkError(Object error) {
    if (error is SocketException) {
      final String message = error.message;
      if (error.osError != null && error.osError!.errorCode == 7) {
        // errno 7 = EAI_NONAME，域名解析不出来。
        return '查询失败：解析不了 api.github.com。'
            '请确认手机能正常上网（Wi-Fi 或移动数据），并且没有被代理/VPN 拦住。';
      }
      if (message.contains('Failed host lookup')) {
        return '查询失败：解析不了 api.github.com，请检查手机网络。';
      }
      return '查询失败：网络连接不上（${error.osError?.message ?? message}）。';
    }
    if (error is TimeoutException) {
      return '查询失败：连接 GitHub 超时。国内网络访问 api.github.com 经常不稳，稍后再试。';
    }
    if (error is HandshakeException) {
      return '查询失败：TLS 握手失败，可能是代理或证书问题。';
    }
    return '查询失败：$error';
  }
}
