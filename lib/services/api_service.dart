import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/constants/constants.dart';

/// Base HTTP client for all API interactions.
///
/// Centralises headers, token injection, and timeout handling so that
/// individual service classes only need to call `get`, `post`, etc.
class ApiService {
  final http.Client _client;
  String? _authToken;

  ApiService({http.Client? client}) : _client = client ?? http.Client();

  // ─── Auth ───────────────────────────────────────────────────
  void setToken(String token) => _authToken = token;
  void clearToken() => _authToken = null;

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (_authToken != null) 'Authorization': 'Bearer $_authToken',
      };

  // ─── GET ────────────────────────────────────────────────────
  Future<http.Response> get(String endpoint,
      {Map<String, String>? queryParams}) {
    final uri = Uri.parse('${AppConstants.baseUrl}$endpoint')
        .replace(queryParameters: queryParams);
    return _client.get(uri, headers: _headers).timeout(AppConstants.apiTimeout);
  }

  // ─── POST ───────────────────────────────────────────────────
  Future<http.Response> post(String endpoint, {Map<String, dynamic>? body}) {
    final uri = Uri.parse('${AppConstants.baseUrl}$endpoint');
    return _client
        .post(uri, headers: _headers, body: jsonEncode(body))
        .timeout(AppConstants.apiTimeout);
  }

  // ─── PUT ────────────────────────────────────────────────────
  Future<http.Response> put(String endpoint, {Map<String, dynamic>? body}) {
    final uri = Uri.parse('${AppConstants.baseUrl}$endpoint');
    return _client
        .put(uri, headers: _headers, body: jsonEncode(body))
        .timeout(AppConstants.apiTimeout);
  }

  // ─── DELETE ─────────────────────────────────────────────────
  Future<http.Response> delete(String endpoint) {
    final uri = Uri.parse('${AppConstants.baseUrl}$endpoint');
    return _client
        .delete(uri, headers: _headers)
        .timeout(AppConstants.apiTimeout);
  }

  // ─── Multipart ──────────────────────────────────────────────
  Future<http.StreamedResponse> uploadFile(
    String endpoint,
    String filePath,
    String fieldName,
  ) async {
    final uri = Uri.parse('${AppConstants.baseUrl}$endpoint');
    final request = http.MultipartRequest('POST', uri)
      ..headers.addAll(_headers)
      ..files.add(await http.MultipartFile.fromPath(fieldName, filePath));
    return request.send().timeout(AppConstants.apiTimeout);
  }

  void dispose() => _client.close();
}
