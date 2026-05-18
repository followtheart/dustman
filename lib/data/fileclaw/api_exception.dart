/// FileClaw / dustman-cloud API 错误模型。
///
/// HTTP 4xx 由 dustman-cloud 返回的 FastAPI 错误结构：
/// `{"detail": "..." }` —— 我们把 detail 提到 message。
/// 5xx / 网络异常用 [ApiException.network]。
class ApiException implements Exception {
  ApiException({
    required this.statusCode,
    required this.message,
    this.kind = ApiErrorKind.server,
  });

  factory ApiException.network(String message) => ApiException(
        statusCode: 0,
        message: message,
        kind: ApiErrorKind.network,
      );

  factory ApiException.offline() =>
      ApiException.network('cannot reach the server');

  final int statusCode;
  final String message;
  final ApiErrorKind kind;

  bool get isAuth => statusCode == 401 || statusCode == 403;
  bool get isRateLimited => statusCode == 429;
  bool get isConflict => statusCode == 409;
  bool get isClient => statusCode >= 400 && statusCode < 500;

  @override
  String toString() => 'ApiException($statusCode, $kind): $message';
}

enum ApiErrorKind { network, server }
