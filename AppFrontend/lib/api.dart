import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';

class ApiException implements Exception {
  final String message;
  final bool network; // true = could not reach hub
  ApiException(this.message, {this.network = false});
  @override
  String toString() => message;
}

class Api {
  final String baseUrl;
  Api(this.baseUrl);

  static const _timeout = Duration(seconds: 8);

  Uri _u(String path, [Map<String, String>? q]) {
    final b = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    return Uri.parse('$b/api/v1$path').replace(queryParameters: q);
  }

  dynamic _decode(http.Response r) {
    dynamic body;
    try {
      body = r.body.isEmpty ? null : jsonDecode(utf8.decode(r.bodyBytes));
    } catch (_) {
      body = null;
    }
    if (r.statusCode >= 200 && r.statusCode < 300) return body;
    String msg = 'HTTP ${r.statusCode}';
    if (body is Map && body['error'] is Map) {
      msg = (body['error']['message'] ?? msg).toString();
    }
    throw ApiException(msg);
  }

  Future<dynamic> _send(Future<http.Response> Function() f) async {
    try {
      return _decode(await f().timeout(_timeout));
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Cannot reach hub ($e)', network: true);
    }
  }

  Future<Map<String, dynamic>> health() async =>
      (await _send(() => http.get(_u('/health')))) as Map<String, dynamic>;

  /// Submit many reports (offline sync). Returns id -> result (created|duplicate|rejected).
  Future<Map<String, String>> submitBatch(List<Map<String, dynamic>> reports) async {
    final data = await _send(() => http.post(
          _u('/reports/batch'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'reports': reports}),
        ));
    final out = <String, String>{};
    for (final r in (data['results'] as List)) {
      out[(r['id'] ?? '').toString()] = (r['result'] ?? '').toString();
    }
    return out;
  }

  /// Returns (server_time, items). Pass back server_time as `since` next time.
  Future<(String, List<Report>)> listReports({String? since}) async {
    final data = await _send(() => http.get(_u('/reports', since == null ? null : {'since': since})));
    final items = (data['items'] as List)
        .map((e) => Report.fromJson(e as Map<String, dynamic>))
        .toList();
    return (data['server_time'] as String, items);
  }

  Future<List<Resource>> listResources() async {
    final data = await _send(() => http.get(_u('/resources')));
    return (data as List).map((e) => Resource.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> addResource(Map<String, dynamic> body) async {
    await _send(() => http.post(
          _u('/resources'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(body),
        ));
  }

  Future<List<Place>> listLocations() async {
    final data = await _send(() => http.get(_u('/locations')));
    return (data as List).map((e) => Place.fromJson(e as Map<String, dynamic>)).toList();
  }
}
