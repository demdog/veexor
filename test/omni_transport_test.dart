import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:veexor/models.dart';
import 'package:veexor/omni.dart';
import 'package:veexor/speech.dart';

class LocalOmni {
  late HttpServer server;
  final sockets = <WebSocket>[];
  final events = <Json>[];
  void Function(WebSocket socket, Json event, int connection)? respond;
  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final socket = await WebSocketTransformer.upgrade(request);
      sockets.add(socket);
      final connection = sockets.length;
      socket.listen((value) {
        final event = object(jsonDecode(value as String));
        events.add(event);
        if (event['type'] == 'session.update') {
          send(socket, {'type': 'session.updated'});
        } else {
          respond?.call(socket, event, connection);
        }
      });
    });
  }

  Future<WebSocket> connect(
    String url,
    Map<String, String> headers,
    HttpClient client,
  ) async {
    expect(url, startsWith('wss://test-space.cn-beijing.maas.aliyuncs.com/'));
    expect(headers['Authorization'], 'Bearer test-key');
    return WebSocket.connect(
      'ws://127.0.0.1:${server.port}/',
      customClient: client,
    );
  }

  void send(WebSocket socket, Json event) => socket.add(jsonEncode(event));

  void answer(WebSocket socket, String transcript, {bool tool = false}) {
    send(socket, {
      'type': 'response.created',
      'response': {'id': 'r'},
    });
    send(socket, {
      'type': 'response.audio.delta',
      'response_id': 'r',
      'output_index': 0,
      'content_index': 0,
      'delta': base64Encode([1, 0, 2, 0]),
    });
    send(socket, {
      'type': 'response.audio_transcript.done',
      'response_id': 'r',
      'output_index': 0,
      'content_index': 0,
      'transcript': transcript,
    });
    send(socket, {
      'type': 'response.done',
      'response': {
        'id': 'r',
        'status': 'completed',
        'output': [
          {
            'type': 'message',
            'role': 'assistant',
            'content': [
              {'type': 'audio', 'transcript': transcript},
            ],
          },
          if (tool) {'type': 'function_call'},
        ],
      },
    });
  }

  Future<void> close() async {
    for (final socket in sockets) {
      await socket.close();
    }
    await server.close(force: true);
  }
}

void main() {
  late LocalOmni server;
  late Directory directory;
  late Omni client;
  setUp(() async {
    server = LocalOmni();
    await server.start();
    directory = await Directory.systemTemp.createTemp('veexor_omni_test_');
    client = Omni('test-key', 'test-space', (_) {}, connector: server.connect);
  });
  tearDown(() async {
    client.close();
    await server.close();
    await directory.delete(recursive: true);
  });
  test('STT uploads PCM but accepts only input transcription', () async {
    server.respond = (socket, event, _) {
      if (event['type'] == 'response.create') {
        server.send(socket, {
          'type': 'response.text.done',
          'text': '不要使用模型生成的回答',
        });
        server.send(socket, {
          'type': 'conversation.item.input_audio_transcription.completed',
          'transcript': '不要打开客厅灯',
        });
      }
    };
    final input = File('${directory.path}/input.pcm');
    await input.writeAsBytes(Uint8List(9600));
    expect(await client.transcribe(input), '不要打开客厅灯');
    final uploaded = server.events.where(
      (e) => e['type'] == 'input_audio_buffer.append',
    );
    expect(uploaded.length, 3);
    expect(
      uploaded
          .map((e) => base64Decode(text(e['audio'])).length)
          .reduce((a, b) => a + b),
      9600,
    );
    expect(
      server.events
          .where((e) => e['type'] == 'input_audio_buffer.commit')
          .length,
      1,
    );
  });
  test(
    'TTS retries only one mismatched segment and writes verified audio',
    () async {
      server.respond = (socket, event, connection) {
        if (event['type'] == 'response.create') {
          server.answer(socket, connection == 1 ? '还剩九瓶，六百毫升。' : '还剩八瓶，六百毫升。');
        }
      };
      final output = File('${directory.path}/reply.pcm');
      await client.synthesize('还剩 8 瓶（600 毫升）。', output);
      expect(server.sockets.length, 2);
      expect(await output.readAsBytes(), [1, 0, 2, 0]);
      final readings = server.events.where(
        (e) => e['type'] == 'conversation.item.create',
      );
      expect(readings.length, 2);
      expect(jsonEncode(readings.last), contains('重新逐字朗读'));
    },
  );
  test(
    'persistent mismatch deletes partial audio after exactly two attempts',
    () async {
      server.respond = (socket, event, _) {
        if (event['type'] == 'response.create') server.answer(socket, '还剩九瓶');
      };
      final output = File('${directory.path}/reply.pcm');
      await expectLater(
        client.synthesize('还剩8瓶', output),
        throwsA(isA<SpeechMismatch>()),
      );
      expect(server.sockets.length, 2);
      expect(await output.exists(), false);
    },
  );
  test('tool responses are rejected without retrying TTS', () async {
    server.respond = (socket, event, _) {
      if (event['type'] == 'response.create') {
        server.answer(socket, '打开灯', tool: true);
      }
    };
    final output = File('${directory.path}/reply.pcm');
    await expectLater(
      client.synthesize('打开灯', output),
      throwsA(isA<FormatException>()),
    );
    expect(server.sockets.length, 1);
    expect(await output.exists(), false);
  });
  test(
    'cancellation interrupts pending response and discards output',
    () async {
      final pending = Completer<void>();
      server.respond = (socket, event, _) {
        if (event['type'] == 'response.create') pending.complete();
      };
      final output = File('${directory.path}/reply.pcm');
      final verified = expectLater(
        client.synthesize('还剩8瓶', output),
        throwsA(isA<HttpException>()),
      );
      await pending.future;
      client.close();
      await verified;
      expect(server.sockets.length, 1);
      expect(await output.exists(), false);
    },
  );
}
