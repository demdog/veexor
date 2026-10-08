import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:veexor/models.dart';

const alice = '11111111-1111-4111-8111-111111111111',
    bob = '22222222-2222-4222-8222-222222222222';
final imageA = 'img_${'a' * 32}', imageB = 'img_${'b' * 32}';
void main() {
  test('server titles, explicit null and legacy name fields', () {
    final people = Person.parse({
      'people': [
        {'person_id': alice, 'name': ' 爸爸 '},
        {'person_id': bob, 'name': null, 'display_name': '旧名称'},
        {'id': '名字', 'name': '非法'},
      ],
    });
    expect(people.length, 2);
    expect(people.first.name, '爸爸');
    expect(people.last.name, '');
    expect(people.last.label, '称谓未同步');
    expect(
      Person.parse([
        {'id': alice, 'display_name': '妈妈'},
      ]).first.name,
      '妈妈',
    );
    expect(
      () => Person.parse({
        'people': [
          {'id': '名字'},
        ],
      }),
      throwsFormatException,
    );
  });
  test('text and photo requests carry UUID and exclude local metadata', () {
    final body = chatRequest(
      '识别',
      [
        {'image_id': imageA, 'image_file': 'photo_a.jpg'},
      ],
      '',
      alice,
    );
    expect(body['person_id'], alice);
    expect(body['new_conversation'], true);
    expect((body['content'] as List)[1], {'type': 'image', 'image_id': imageA});
    expect(
      chatRequest(
        '',
        [
          {'image_id': imageA},
        ],
        'chat_a',
        '',
      )['content'][0]['text'],
      '请识别照片中的物品。',
    );
    expect(chatRequest('你好', [], 'chat_a', '').containsKey('person_id'), false);
    expect(() => chatRequest('你好', [], '', '爸爸'), throwsFormatException);
    expect(() => chatRequest('a' * 4001, [], '', ''), throwsFormatException);
  });
  test('switching an established identity preserves old drafts and photos', () {
    final book = SessionBook();
    final first = book.choosePerson(alice, '爸爸');
    first.serverId = 'chat_a';
    first.busy = true;
    first.draft = '原草稿';
    first.photos = [
      {'image_file': 'photo_a.jpg'},
    ];
    first.add('user', '你好');
    final second = book.choosePerson(bob, '妈妈');
    expect(identical(first, second), false);
    expect(first.personId, alice);
    expect(first.draft, '原草稿');
    expect(first.photos.length, 1);
    expect(second.messages, isEmpty);
    expect(second.personId, bob);
    book.rememberPerson(alice, '父亲');
    expect(first.personName, '父亲');
    expect(first.serverId, 'chat_a');
    expect(first.busy, true);
  });
  test('unused drafts can bind identity and same-person title changes retain context', () {
    final book = SessionBook();
    final draft = book.active;
    draft.draft = '文字';
    draft.photos = [
      {'image_file': 'photo_a.jpg'},
    ];
    expect(identical(book.choosePerson(alice, '爸爸'), draft), true);
    draft.serverId = 'chat_a';
    expect(identical(book.choosePerson(alice, '父亲'), draft), true);
    expect(draft.draft, '文字');
    expect(draft.photos.length, 1);
    expect(draft.personName, '父亲');
  });
  test(
    '1.12 JSON migrates voice, photos, titles, UUIDs and interrupted state',
    () {
      final raw = jsonEncode({
        'selected': 'a',
        'person_id': alice,
        'person_name': '爸爸',
        'person_names': {alice: '爸爸', bob: '妈妈'},
        'sessions': [
          {
            'id': 'a',
            'server_id': 'chat_a',
            'person_id': alice,
            'person_name': '旧名称',
            'identity_known': true,
            'busy': true,
            'loaded': true,
            'draft': '草稿',
            'photos': [
              {'image_file': 'photo_a.jpg'},
            ],
            'messages': [
              {
                'role': 'assistant',
                'content': '回答',
                'kind': 'voice',
                'audio_file': 'reply_a.pcm',
                'sample_rate': 24000,
                'duration_ms': 1000,
                'speech_expected': '正文',
                'speech_actual': '差异',
              },
            ],
          },
        ],
      });
      final book = SessionBook.restore(raw);
      expect(book.active.personName, '爸爸');
      expect(book.active.busy, false);
      expect(book.active.notice, contains('结果未知'));
      expect(book.active.draft, '草稿');
      expect(book.active.photos.length, 1);
      expect(book.active.messages.first.data['audio_file'], 'reply_a.pcm');
      final restored = SessionBook.restore(book.save());
      expect(restored.active.messages.first.data['speech_actual'], '差异');
      expect(restored.names[bob], '妈妈');
    },
  );
  test('new sessions inherit confirmed identity and empty server title clears old name', () {
    final book = SessionBook();
    book.choosePerson(alice, '爸爸');
    book.newSession();
    expect(book.active.personId, alice);
    book.rememberPerson(alice, '');
    expect(book.active.identityLabel, '称谓未同步');
    final history = book.open('old', '历史');
    book.applyIdentity(history, {
      'conversation': {'person_id': alice, 'person_name': '旧称谓'},
    });
    expect(history.personName, '');
    book.close(history.id);
    expect(SessionBook.restore(book.save()).names[alice], '');
  });
  test('unknown histories do not inherit current person or allow sending', () {
    final book = SessionBook();
    book.choosePerson(alice, '爸爸');
    final history = book.open('unknown', '历史');
    expect(history.personId, '');
    expect(history.canSend, false);
    book.applyIdentity(history, {'messages': []});
    expect(history.identityKnown, false);
    book.applyIdentity(history, {'person_id': bob});
    expect(history.personId, bob);
    expect(history.identityKnown, true);
    expect(book.defaultPersonId, alice);
    expect(
      () => book.applyIdentity(history, {'person_id': '妈妈'}),
      throwsFormatException,
    );
  });
  test(
    'history matching distinguishes photos and retains local audio once',
    () {
      final book = SessionBook(), session = Session();
      final first = session.add('user', '这是什么', 'voice');
      first.data.addAll({
        'audio_file': 'input_a.pcm',
        'content_parts': localParts('这是什么', [
          {'image_id': imageA, 'image_file': 'photo_a.jpg'},
        ]),
      });
      final second = session.add('user', '这是什么');
      second.data['content_parts'] = localParts('这是什么', [
        {'image_id': imageB, 'image_file': 'photo_b.jpg'},
      ]);
      book.replaceHistory(session, [
        {
          'role': 'user',
          'content': '这是什么',
          'content_parts': localParts('这是什么', [
            {'image_id': imageB},
          ]),
        },
        {
          'role': 'user',
          'content': '这是什么',
          'content_parts': localParts('这是什么', [
            {'image_id': imageA},
          ]),
        },
      ]);
      expect(session.messages.first.kind, 'text');
      expect(session.messages.last.data['audio_file'], 'input_a.pcm');
      expect(session.messages.last.images.first['image_file'], 'photo_a.jpg');
    },
  );
  test(
    'UUID, image ID and local filename validation prevent path confusion',
    () {
      expect(validPerson(newId()), true);
      expect(validImage(imageA), true);
      expect(validImage('$imageA/other'), false);
      expect(validPhoto('../photo_a.jpg'), false);
      expect(validPhoto('photo_a.jpg'), true);
      expect(
        () => chatRequest(
          '图片',
          List.generate(5, (_) => {'image_id': imageA}),
          '',
          '',
        ),
        throwsFormatException,
      );
    },
  );
}
