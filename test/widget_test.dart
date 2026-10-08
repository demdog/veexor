import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veexor/app.dart';
import 'package:veexor/chat_controller.dart';
import 'package:veexor/models.dart';

import 'fake_host.dart';

void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets('portrait chat and keyboard fit on $platform', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final host = FakeHost();
      final c = ChatController(host);
      await tester.pumpWidget(VeexorApp(controller: c));
      await tester.pumpAndSettle();
      expect(find.text('Veexor'), findsOneWidget);
      expect(find.text('+'), findsOneWidget);
      expect(find.byTooltip('拍照'), findsOneWidget);
      expect(find.text('历史'), findsNothing);
      expect(find.text('建议对话'), findsNothing);
      expect(tester.takeException(), isNull);
      tester.view.viewInsets = const FakeViewPadding(bottom: 310);
      addTearDown(tester.view.resetViewInsets);
      await tester.pump();
      expect(
        tester.getBottomRight(find.byKey(const Key('send'))).dy,
        lessThanOrEqualTo(534),
      );
      expect(tester.takeException(), isNull);
      await tester.enterText(find.byKey(const Key('chat_input')), 'A 的草稿');
      await tester.tap(find.byKey(const Key('new_session')));
      await tester.pump();
      expect(c.book.sessions.length, 2);
      expect(c.book.sessions.first.draft, 'A 的草稿');
      expect(c.active.draft, '');
      await tester.tap(find.byKey(Key('session_${c.book.sessions.first.id}')));
      await tester.pump();
      expect(find.text('A 的草稿'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(
        host.calls.where(
          (r) => r.$1 == 'request' && r.$2['path'] == '/v1/chat',
        ),
        isEmpty,
      );
      debugDefaultTargetPlatformOverride = null;
    });
  }
  testWidgets('server appellation picker selects person and + is last tab', (
    tester,
  ) async {
    final host = FakeHost();
    host.handler = (method, args) async =>
        method == 'request' && args['path'] == '/v1/personal-sync/people'
        ? {
            'people': [
              {
                'person_id': '11111111-1111-4111-8111-111111111111',
                'name': '爸爸',
              },
            ],
          }
        : unhandled;
    final c = ChatController(host);
    await tester.pumpWidget(VeexorApp(controller: c));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('身份：'));
    await tester.pumpAndSettle();
    expect(find.text('爸爸'), findsOneWidget);
    await tester.tap(find.text('爸爸'));
    await tester.pumpAndSettle();
    expect(find.text('身份：爸爸'), findsOneWidget);
    expect(
      tester.getTopLeft(find.byKey(const Key('new_session'))).dx,
      greaterThan(
        tester.getTopLeft(find.byKey(Key('session_${c.active.id}'))).dx,
      ),
    );
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
  testWidgets('voice answer shows readable transcript and mismatch details', (
    tester,
  ) async {
    final c = ChatController(FakeHost());
    await tester.pumpWidget(VeexorApp(controller: c));
    await tester.pumpAndSettle();
    final message = Message.create('assistant', '还剩8瓶（600毫升）', 'voice');
    message.data.addAll({'speech_expected': '还剩8瓶', 'speech_actual': '还剩9瓶'});
    c.active.messages.add(message);
    c.refresh();
    await tester.pumpAndSettle();
    expect(find.text('还剩8瓶（600毫升）'), findsNothing);
    await tester.tap(find.text('查看文字'));
    await tester.pump();
    expect(find.text('还剩8瓶（600毫升）'), findsOneWidget);
    await tester.tap(find.text('查看语音差异'));
    await tester.pumpAndSettle();
    expect(find.textContaining('还剩9瓶'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}
