import 'dart:async';

import 'package:veexor/host.dart';
import 'package:veexor/models.dart';

class FakeHost implements Host {
  final List<(String, Json)> calls = [];
  Future<Object?> Function(String, Json)? handler;
  void Function(Json)? listener;
  String saved = '';
  Json boot = {
    'base': 'http://192.168.31.68:8001',
    'token': 'test-token',
    'workspace': 'test-space',
    'aliyun': 'test-key',
    'files_dir': '/test',
    'sessions': '',
  };
  @override
  void onEvent(void Function(Json) listener) {
    this.listener = listener;
  }

  @override
  Future<Object?> call(String method, [Json arguments = const {}]) async {
    calls.add((method, arguments));
    if (handler != null) {
      final result = await handler!(method, arguments);
      if (result != unhandled) return result;
    }
    switch (method) {
      case 'bootstrap':
        return boot;
      case 'saveState':
        saved = text(arguments['state']);
        return null;
      case 'request':
        if (arguments['path'] == '/v1/conversations' &&
            arguments['method'] == 'POST') {
          return {'conversation_id': 'chat_${newId().replaceAll('-', '')}'};
        }
        if (arguments['path'] == '/v1/status') {
          return {'llm_configured': true, 'isaac_online': true};
        }
        if (arguments['path'] == '/v1/personal-sync/people') {
          return {'people': []};
        }
        return {};
      case 'recordStart':
        return true;
      case 'recordStop':
        return {
          'audio_file': 'input_test.pcm',
          'sample_rate': 16000,
          'duration_ms': 600,
        };
      case 'transcribe':
        return '我的日程';
      case 'synthesize':
        return {
          'audio_file': 'reply_test.pcm',
          'sample_rate': 24000,
          'duration_ms': 1200,
        };
      default:
        return null;
    }
  }

  int count(String method) => calls.where((call) => call.$1 == method).length;
}

const unhandled = Object();
