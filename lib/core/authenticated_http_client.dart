import 'dart:convert';

// ignore: depend_on_referenced_packages
import 'package:http/http.dart' as http;

/// Shared authenticated HTTP client that attaches auth headers to all requests.
///
/// Supports optional [onAuthError] callback for 401 retry logic.
/// When a 401 is received, the callback is invoked to obtain fresh auth headers,
/// the request is retried once with the new headers.
///
/// Accepts an optional [inner] client for testing; defaults to [http.Client].
class AuthenticatedHttpClient extends http.BaseClient {
  AuthenticatedHttpClient({
    required Map<String, String> headers,
    Future<Map<String, String>?> Function()? onAuthError,
    http.Client? inner,
  }) : _headers = Map<String, String>.from(headers),
       _onAuthError = onAuthError,
       _inner = inner ?? http.Client();

  final Map<String, String> _headers;
  final Future<Map<String, String>?> Function()? _onAuthError;
  final http.Client _inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    request.headers.addAll(_headers);

    final response = await _inner.send(request);

    if (response.statusCode == 401) {
      final bodyBytes = await response.stream.toBytes();
      final body = utf8.decode(bodyBytes);

      // Try token refresh via callback
      if (_onAuthError != null) {
        final newHeaders = await _onAuthError!();
        if (newHeaders != null) {
          _headers.clear();
          _headers.addAll(newHeaders);

          // Clone the request for retry
          final retryRequest = _cloneRequest(request);
          retryRequest.headers.addAll(_headers);

          final retryResponse = await _inner.send(retryRequest);

          return retryResponse;
        }
      }

      // Reconstruct the original response with the body we already consumed
      return http.StreamedResponse(
        Stream.value(bodyBytes),
        response.statusCode,
        headers: response.headers,
        isRedirect: response.isRedirect,
        reasonPhrase: response.reasonPhrase,
      );
    }

    return response;
  }

  /// Clone a [http.BaseRequest] so it can be sent again after a 401.
  http.BaseRequest _cloneRequest(http.BaseRequest original) {
    final clone = http.Request(original.method, original.url);
    clone.headers.addAll(original.headers);
    if (original is http.Request) {
      clone.bodyBytes = original.bodyBytes;
    } else if (original.contentLength != null && original.contentLength! >= 0) {
      clone.contentLength = original.contentLength;
    }
    return clone;
  }

  @override
  void close() {
    _inner.close();
    super.close();
  }
}
