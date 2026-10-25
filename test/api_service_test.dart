import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jio_tv_plus_flutter/services/api_service.dart';

void main() {
  test('sendMobileOtp automatically prefixes +91 and encodes in base64', () async {
    String? capturedBody;
    final mockClient = MockClient((request) async {
      if (request.url.path.contains('loginotp/send')) {
        capturedBody = request.body;
        return http.Response('', 204);
      }
      return http.Response('Not Found', 404);
    });

    final apiService = ApiService(client: mockClient);
    final result = await apiService.sendMobileOtp('6354572515');

    expect(result['success'], isTrue);
    expect(capturedBody, isNotNull);

    final decodedJson = json.decode(capturedBody!);
    final base64Val = decodedJson['number'] as String;
    final rawNumber = utf8.decode(base64.decode(base64Val));

    expect(rawNumber, '+916354572515');
    expect(base64Val, 'KzkxNjM1NDU3MjUxNQ==');
  });
}
