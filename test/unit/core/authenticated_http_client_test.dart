import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:obsidrive/core/authenticated_http_client.dart';

/// A mock HTTP client that records requests and returns programmed responses.
class MockInnerClient extends http.BaseClient {
  final List<http.BaseRequest> requests = [];
  int callCount = 0;

  /// Returns the next response from this list for each call.
  /// If the list is exhausted, returns the last response.
  final List<int> statusCodes;
  final Map<int, String> bodies;

  MockInnerClient({this.statusCodes = const [200], Map<int, String>? bodies})
    : bodies = bodies ?? const {};

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    final statusCode = statusCodes[callCount.clamp(0, statusCodes.length - 1)];
    callCount++;
    final body = bodies[statusCode] ?? '';
    return http.StreamedResponse(Stream.value(utf8.encode(body)), statusCode);
  }

  @override
  void close() {}
}

void main() {
  group('AuthenticatedHttpClient', () {
    test('attaches Authorization header to requests', () async {
      final mockClient = MockInnerClient();
      final client = AuthenticatedHttpClient(
        headers: {'Authorization': 'Bearer test-123', 'X-Goog-AuthUser': '0'},
        inner: mockClient,
      );

      final request = http.Request('GET', Uri.parse('https://example.com/api'));
      await client.send(request);

      expect(mockClient.requests.length, 1);
      expect(
        mockClient.requests[0].headers['Authorization'],
        'Bearer test-123',
      );
      expect(mockClient.requests[0].headers['X-Goog-AuthUser'], '0');
      client.close();
    });

    test('passes through successful responses', () async {
      final mockClient = MockInnerClient(
        statusCodes: [200],
        bodies: {200: '{"kind": "drive#file"}'},
      );
      final client = AuthenticatedHttpClient(
        headers: {'Authorization': 'Bearer token'},
        inner: mockClient,
      );

      final request = http.Request('GET', Uri.parse('https://example.com/api'));
      final response = await client.send(request);

      expect(response.statusCode, 200);
      final body = await response.stream.bytesToString();
      expect(body, '{"kind": "drive#file"}');
      client.close();
    });

    test('retries once on 401 with new headers from onAuthError', () async {
      final mockClient = MockInnerClient(
        statusCodes: [401, 200],
        bodies: {
          401: '{"error": "unauthorized"}',
          200: '{"kind": "drive#file"}',
        },
      );

      var refreshCalled = false;
      final client = AuthenticatedHttpClient(
        headers: {'Authorization': 'Bearer expired-token'},
        inner: mockClient,
        onAuthError: () async {
          refreshCalled = true;
          return {'Authorization': 'Bearer fresh-token'};
        },
      );

      final request = http.Request('GET', Uri.parse('https://example.com/api'));
      final response = await client.send(request);

      expect(refreshCalled, isTrue);
      expect(mockClient.callCount, 2);
      expect(mockClient.requests.length, 2);

      // First request used old token
      expect(
        mockClient.requests[0].headers['Authorization'],
        'Bearer expired-token',
      );

      // Retry used new token
      expect(
        mockClient.requests[1].headers['Authorization'],
        'Bearer fresh-token',
      );

      // Final response should be the successful retry
      expect(response.statusCode, 200);
      final body = await response.stream.bytesToString();
      expect(body, '{"kind": "drive#file"}');
      client.close();
    });

    test('returns 401 if retry also fails', () async {
      final mockClient = MockInnerClient(
        statusCodes: [401, 401],
        bodies: {401: '{"error": "unauthorized"}'},
      );

      var refreshCalled = false;
      final client = AuthenticatedHttpClient(
        headers: {'Authorization': 'Bearer expired-token'},
        inner: mockClient,
        onAuthError: () async {
          refreshCalled = true;
          return {'Authorization': 'Bearer fresh-token'};
        },
      );

      final request = http.Request('GET', Uri.parse('https://example.com/api'));
      final response = await client.send(request);

      expect(refreshCalled, isTrue);
      expect(mockClient.callCount, 2);
      expect(response.statusCode, 401);
      client.close();
    });

    test('returns 401 without retry when no onAuthError callback', () async {
      final mockClient = MockInnerClient(
        statusCodes: [401],
        bodies: {401: '{"error": "unauthorized"}'},
      );

      final client = AuthenticatedHttpClient(
        headers: {'Authorization': 'Bearer expired-token'},
        inner: mockClient,
        // No onAuthError callback
      );

      final request = http.Request('GET', Uri.parse('https://example.com/api'));
      final response = await client.send(request);

      expect(mockClient.callCount, 1);
      expect(response.statusCode, 401);
      final body = await response.stream.bytesToString();
      expect(body, '{"error": "unauthorized"}');
      client.close();
    });

    test('returns 401 without retry when onAuthError returns null', () async {
      final mockClient = MockInnerClient(
        statusCodes: [401],
        bodies: {401: '{"error": "unauthorized"}'},
      );

      final client = AuthenticatedHttpClient(
        headers: {'Authorization': 'Bearer expired-token'},
        inner: mockClient,
        onAuthError: () async => null,
      );

      final request = http.Request('GET', Uri.parse('https://example.com/api'));
      final response = await client.send(request);

      expect(mockClient.callCount, 1);
      expect(response.statusCode, 401);
      client.close();
    });

    test('does not retry non-401 errors', () async {
      final mockClient = MockInnerClient(
        statusCodes: [500],
        bodies: {500: '{"error": "internal"}'},
      );

      var refreshCalled = false;
      final client = AuthenticatedHttpClient(
        headers: {'Authorization': 'Bearer token'},
        inner: mockClient,
        onAuthError: () async {
          refreshCalled = true;
          return {'Authorization': 'Bearer new-token'};
        },
      );

      final request = http.Request('GET', Uri.parse('https://example.com/api'));
      final response = await client.send(request);

      expect(refreshCalled, isFalse);
      expect(mockClient.callCount, 1);
      expect(response.statusCode, 500);
      client.close();
    });
  });
}
