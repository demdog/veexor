// Optional local layout preview. Font is loaded for this test only, never bundled.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veexor/app.dart';
import 'package:veexor/chat_controller.dart';
import 'package:veexor/models.dart';

import '../test/fake_host.dart';

void main() {
  final fontPath = Platform.environment['VEEXOR_PREVIEW_FONT'];
  if (fontPath == null) return;
  testWidgets('render portrait layout previews with a local CJK font', (
    tester,
  ) async {
    final font = ByteData.sublistView(File(fontPath).readAsBytesSync());
    final iconPath = Platform.environment['VEEXOR_PREVIEW_ICONS'];
    if (iconPath != null) {
      final icons = FontLoader('MaterialIcons')
        ..addFont(
          SynchronousFuture(
            ByteData.sublistView(File(iconPath).readAsBytesSync()),
          ),
        );
      await tester.runAsync(icons.load);
    }
    for (final family in ['Roboto', 'Ahem', '.SF UI Text', '.SF UI Display']) {
      final loader = FontLoader(family)..addFont(SynchronousFuture(font));
      await tester.runAsync(loader.load);
    }
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 32, bottom: 24);
    addTearDown(tester.view.reset);
    final key = GlobalKey();
    final c = ChatController(FakeHost());
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: VeexorApp(controller: c),
      ),
    );
    await tester.pumpAndSettle();
    final output = Directory(
      Platform.environment['VEEXOR_PREVIEW_OUTPUT'] ??
          '../../work/flutter-preview',
    );
    Future<void> capture(String name) async {
      await tester.runAsync(() async {
        await output.create(recursive: true);
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 2);
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('${output.path}/$name.png')
            .writeAsBytes(png!.buffer.asUint8List());
        image.dispose();
      });
    }

    await capture('empty');
    c.choosePerson(const Person('11111111-1111-4111-8111-111111111111', '爸爸'));
    c.active.title = '家中的饮料';
    c.active.add('user', '家里还剩多少桃子味脉动？');
    c.active.add(
      'assistant',
      '还剩 8 瓶桃子味脉动（600 毫升）。库存记录的有效期是 2026 年 6 月 28 日，已经过期。',
    );
    c.active.add('user', '客厅灯现在开着吗？', 'voice');
    c.active.add('assistant', '客厅灯目前是关闭状态。', 'voice');
    c.refresh();
    await tester.pumpAndSettle();
    await capture('chat');
    await tester.tap(find.text('语音'));
    await tester.pumpAndSettle();
    await capture('voice');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}
