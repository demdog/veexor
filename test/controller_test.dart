import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:veexor/chat_controller.dart';
import 'package:veexor/models.dart';
import 'package:veexor/speech.dart';

import 'fake_host.dart';

const alice = '11111111-1111-4111-8111-111111111111',
    bob = '22222222-2222-4222-8222-222222222222';
void main() {
  late FakeHost host;
  late ChatController c;
  late DateTime time;
  setUp(() async {
    host = FakeHost();
    time = DateTime(2026, 10, 8);
    c = ChatController(host, now: () => time);
    await c.initialize();
    await Future<void>.delayed(Duration.zero);
    host.calls.clear();
  });
  tearDown(() => c.dispose());
  test('first chat persists a precreated recovery ID before posting', () async {
    const id = 'chat_11111111111111111111111111111111';
    host.handler = (method, args) async {
      if (method == 'request' && args['path'] == '/v1/conversations') {
        return {'conversation_id': id};
      }
      if (method == 'request' && args['path'] == '/v1/chat') {
        final saved = SessionBook.restore(host.saved);
        expect(saved.active.serverId, id);
        expect(saved.active.messages.last.data['awaiting_reply'], true);
        expect(object(args['body'])['conversation_id'], id);
        expect(object(args['body']).containsKey('new_conversation'), false);
        return {'conversation_id': id, 'answer': '建模完成'};
      }
      return unhandled;
    };
    c.active.draft = '建模桌子';
    await c.sendText();
    expect(c.active.messages.last.content, '建模完成');
    expect(c.active.messages.first.data.containsKey('awaiting_reply'), false);
  });
  test(
    'lost response recovers completed answer by GET without reposting',
    () async {
      host.handler = (method, args) async {
        if (method == 'request' && args['path'] == '/v1/chat') {
          throw TimeoutException('等待回答超时');
        }
        if (method == 'request' &&
            text(args['path']).startsWith('/v1/conversations/')) {
          return {
            'person_id': null,
            'messages': [
              {'role': 'user', 'content': '建模桌子'},
              {'role': 'assistant', 'content': '桌子建模完成'},
            ],
          };
        }
        return unhandled;
      };
      c.active.draft = '建模桌子';
      await c.sendText();
      expect(c.active.messages.last.content, '桌子建模完成');
      expect(c.active.messages.first.data.containsKey('awaiting_reply'), false);
      expect(c.active.notice, contains('未自动重发'));
      expect(
        host.calls
            .where(
              (call) => call.$1 == 'request' && call.$2['path'] == '/v1/chat',
            )
            .length,
        1,
      );
    },
  );
  test('empty history preserves pending message and identity, then recovers after restart', () async {
    var complete = false;
    host.handler = (method, args) async {
      if (method == 'request' && args['path'] == '/v1/chat') {
        throw TimeoutException('等待回答超时');
      }
      if (method == 'request' &&
          text(args['path']).startsWith('/v1/conversations/')) {
        return {
          'person_id': complete ? alice : null,
          'messages': complete
              ? [
                  {'role': 'user', 'content': '建模桌子'},
                  {'role': 'assistant', 'content': '完成'},
                ]
              : [],
        };
      }
      return unhandled;
    };
    c.choosePerson(const Person(alice, '爸爸'));
    c.active.draft = '建模桌子';
    await c.sendText();
    expect(c.active.messages.length, 1);
    expect(c.active.personId, alice);
    expect(c.active.messages.last.data['awaiting_reply'], true);
    host.boot['sessions'] = c.book.save();
    c.dispose();
    complete = true;
    c = ChatController(host);
    await c.initialize();
    await Future<void>.delayed(Duration.zero);
    expect(c.active.messages.last.content, '完成');
    expect(
      host.calls
          .where(
            (call) => call.$1 == 'request' && call.$2['path'] == '/v1/chat',
          )
          .length,
      1,
    );
  });
  test(
    'conversation creation failure keeps draft and never submits chat',
    () async {
      host.handler = (method, args) async {
        if (method == 'request' && args['path'] == '/v1/conversations') {
          throw TimeoutException('连接服务超时');
        }
        return unhandled;
      };
      c.active.draft = '添加库存';
      await c.sendText();
      expect(c.active.draft, '添加库存');
      expect(c.active.serverId, '');
      expect(c.active.notice, contains('聊天尚未发送'));
      expect(
        host.calls.where(
          (call) => call.$1 == 'request' && call.$2['path'] == '/v1/chat',
        ),
        isEmpty,
      );
    },
  );
  test(
    'fifth household request keeps its draft while four sessions are busy',
    () async {
      for (var i = 0; i < 4; i++) {
        c.active.busy = true;
        c.create();
      }
      c.active.draft = '第五个请求';
      await c.sendText();
      expect(c.active.draft, '第五个请求');
      expect(c.active.messages, isEmpty);
      expect(host.count('request'), 0);
      expect(c.error, contains('4 个会话'));
      await c.beginHold(300);
      expect(host.count('recordStart'), 0);
    },
  );
  test(
    'playback failure does not recursively regenerate paid speech',
    () async {
      host.handler = (method, args) async {
        if (method == 'play') throw const FormatException('播放失败');
        return unhandled;
      };
      final message = c.active.add('assistant', '还剩8瓶', 'voice');
      message.data['audio_file'] = 'reply_test.pcm';
      await c.play(c.active, message);
      expect(host.count('play'), 1);
      expect(host.count('synthesize'), 0);
      expect(message.data.containsKey('audio_file'), false);
      expect(message.data['voice_status'], contains('重试'));
    },
  );
  test(
    'concurrent replies stay with original sessions and captured UUIDs',
    () async {
      final a = Completer<Object?>(), b = Completer<Object?>();
      host.handler = (method, args) async {
        if (method == 'request' && args['path'] == '/v1/chat') {
          return text(object(args['body'])['person_id']) == alice
              ? a.future
              : b.future;
        }
        return unhandled;
      };
      c.choosePerson(const Person(alice, '爸爸'));
      final first = c.active;
      first.draft = '爸爸的问题';
      final sendA = c.sendText();
      c.choosePerson(const Person(bob, '妈妈'));
      final second = c.active;
      second.draft = '妈妈的问题';
      final sendB = c.sendText();
      b.complete({'conversation_id': 'chat_b', 'answer': '妈妈的回答'});
      await sendB;
      a.complete({'conversation_id': 'chat_a', 'answer': '爸爸的回答'});
      await sendA;
      expect(first.messages.last.content, '爸爸的回答');
      expect(second.messages.last.content, '妈妈的回答');
      expect(first.personId, alice);
      expect(second.personId, bob);
      expect(host.count('synthesize'), 0);
    },
  );
  test(
    'closed sessions discard late replies without affecting active chat',
    () async {
      final reply = Completer<Object?>();
      host.handler = (method, args) async =>
          method == 'request' && args['path'] == '/v1/chat'
          ? reply.future
          : unhandled;
      c.active.draft = '问题';
      final original = c.active;
      final sending = c.sendText();
      c.create();
      final current = c.active;
      c.close(original.id);
      reply.complete({'conversation_id': 'old', 'answer': '迟到回答'});
      await sending;
      expect(current.messages, isEmpty);
      expect(c.book.find(original.id), null);
      expect(host.count('cancel'), 1);
    },
  );
  test(
    'failed photo upload restores draft and never submits household chat',
    () async {
      host.handler = (method, args) async {
        if (method == 'upload') throw const FormatException('上传失败');
        return unhandled;
      };
      c.active.draft = '照片问题';
      c.active.photos = [
        {'image_file': 'photo_test.jpg'},
      ];
      await c.sendText();
      expect(c.active.photos.length, 1);
      expect(c.active.draft, '照片问题');
      expect(
        host.calls.where(
          (r) => r.$1 == 'request' && r.$2['path'] == '/v1/chat',
        ),
        isEmpty,
      );
      expect(c.active.busy, false);
    },
  );
  test(
    'chat timeout after upload is not retried or restored as an unsent photo',
    () async {
      host.handler = (method, args) async {
        if (method == 'upload') return {'image_id': 'img_${'a' * 32}'};
        if (method == 'request' && args['path'] == '/v1/chat') {
          throw TimeoutException('结果未知');
        }
        return unhandled;
      };
      c.active.draft = '登记照片';
      c.active.photos = [
        {'image_file': 'photo_test.jpg'},
      ];
      await c.sendText();
      expect(c.active.photos, isEmpty);
      expect(c.active.notice, contains('结果未知'));
      expect(
        host.calls
            .where((r) => r.$1 == 'request' && r.$2['path'] == '/v1/chat')
            .length,
        1,
      );
    },
  );
  test(
    'slide cancellation, including release without move, sends nothing',
    () async {
      await c.beginHold(300);
      time = time.add(const Duration(seconds: 1));
      await c.finishHold(230);
      expect(host.count('recordCancel'), 1);
      expect(host.count('recordStop'), 0);
      expect(host.count('transcribe'), 0);
      expect(c.active.messages, isEmpty);
    },
  );
  test(
    'short press and background interruption cancel without uploading',
    () async {
      await c.beginHold(300);
      time = time.add(const Duration(milliseconds: 100));
      await c.finishHold(300);
      expect(host.count('transcribe'), 0);
      await c.beginHold(300);
      c.background();
      await Future<void>.delayed(Duration.zero);
      expect(c.recording, false);
      expect(host.count('recordCancel'), 2);
      expect(c.active.messages, isEmpty);
    },
  );
  test(
    'voice release transcribes, sends UUID once and returns voice',
    () async {
      host.handler = (method, args) async {
        if (method == 'request' && args['path'] == '/v1/chat') {
          return {'conversation_id': 'chat_a', 'answer': '今天没有日程'};
        }
        return unhandled;
      };
      c.choosePerson(const Person(alice, '爸爸'));
      await c.beginHold(300);
      time = time.add(const Duration(seconds: 1));
      await c.finishHold(300);
      await Future<void>.delayed(Duration.zero);
      expect(host.count('transcribe'), 1);
      expect(c.active.messages.first.kind, 'voice');
      expect(c.active.messages.last.kind, 'voice');
      expect(host.count('synthesize'), 1);
      final turn = host.calls.singleWhere(
        (r) => r.$1 == 'request' && r.$2['path'] == '/v1/chat',
      );
      expect(object(turn.$2['body'])['person_id'], alice);
    },
  );
  test('new voice response never autoplays after session switch', () async {
    final audio = Completer<Object?>();
    host.handler = (method, args) async {
      if (method == 'synthesize') return audio.future;
      return unhandled;
    };
    final original = c.active,
        message = original.add('assistant', '语音回答', 'voice');
    final synthesis = c.generateAudio(original, message, autoplay: true);
    c.create();
    audio.complete({'audio_file': 'reply_a.pcm', 'sample_rate': 24000});
    await synthesis;
    expect(host.count('play'), 0);
    expect(message.data['audio_file'], 'reply_a.pcm');
  });
  test('failed voice verification retains readable differences without repeating chat', () async {
    host.handler = (method, args) async {
      if (method == 'synthesize') throw SpeechMismatch('还剩8瓶', '还剩9瓶');
      return unhandled;
    };
    final message = c.active.add('assistant', '还剩8瓶', 'voice');
    await c.generateAudio(c.active, message, autoplay: true);
    expect(message.data['speech_expected'], '还剩8瓶');
    expect(message.data['speech_actual'], '还剩9瓶');
    expect(message.data.containsKey('audio_file'), false);
    expect(host.count('request'), 0);
    expect(host.count('play'), 0);
  });
  test('stale directory result is ignored after changing service', () async {
    final members = Completer<Object?>();
    var delayed = true;
    host.handler = (method, args) async {
      if (method == 'request' &&
          args['path'] == '/v1/personal-sync/people' &&
          delayed) {
        return members.future;
      }
      return unhandled;
    };
    final reading = c.people();
    delayed = false;
    await c.saveConfig({
      'base': 'http://192.168.31.69:8001',
      'token': 'new-token',
      'workspace': '',
      'aliyun': '',
    });
    members.complete({
      'people': [
        {'person_id': alice, 'name': '旧服务成员'},
      ],
    });
    await reading;
    expect(c.book.names.containsKey(alice), false);
  });
  test('microphone permission does not auto-send a recording', () async {
    host.handler = (method, args) async =>
        method == 'recordStart' ? false : unhandled;
    await c.beginHold(300);
    time = time.add(const Duration(seconds: 1));
    await c.finishHold(300);
    expect(c.recording, false);
    expect(host.count('recordStop'), 0);
    expect(c.active.messages, isEmpty);
  });
}
