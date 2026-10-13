import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veexor/http_policy.dart';

void main() {
  test('answer timeout is 390 seconds, distinct from connect and upload', () {
    expect(homeAnswerTimeout.inSeconds, 390);
    expect(homeConnectTimeout.inSeconds, 8);
    expect(homeSendTimeout.inSeconds, 30);
  });
  test('connection, send and receive timeouts have distinct messages', () {
    for (final entry in {
      DioExceptionType.connectionTimeout: '连接服务超时',
      DioExceptionType.sendTimeout: '发送请求超时',
      DioExceptionType.receiveTimeout: '等待回答超时',
    }.entries) {
      final error = householdFailure(
        DioException(
          requestOptions: RequestOptions(path: '/v1/chat'),
          type: entry.key,
        ),
      );
      expect(error, isA<TimeoutException>());
      expect(error.toString(), contains(entry.value));
      expect(error.toString(), isNot(contains('无法连接服务')));
    }
  });
}
