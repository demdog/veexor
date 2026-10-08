import 'package:flutter_test/flutter_test.dart';
import 'package:veexor/speech.dart';
import 'package:veexor/omni.dart';

void main() {
  const answer = '还剩 8 瓶桃子味脉动（600 毫升）。库存记录的有效期是 2026 年 6 月 28 日，已经过期。';
  const spoken = '还剩八瓶桃子味脉动，六百毫升。库存记录的有效期是二零二六年六月二十八日，已经过期。';
  test('reported parentheses and equivalent quantities remain faithful', () {
    expect(SpeechText.matches(answer, spoken), true);
    expect(
      SpeechText.matches(answer, spoken.replaceFirst('二零二六年', '两千零二十六年')),
      true,
    );
    for (final changed in [
      spoken.replaceFirst('八瓶', '九瓶'),
      spoken.replaceFirst('六百毫升', '五百毫升'),
      spoken.replaceFirst('二零二六年', '二零二七年'),
      spoken.replaceFirst('六月', '七月'),
      spoken.replaceFirst('二十八日', '二十九日'),
      spoken.replaceFirst('已经过期', '尚未过期'),
      spoken.replaceFirst('，六百毫升', ''),
    ]) {
      expect(SpeechText.matches(answer, changed), false, reason: changed);
    }
  });
  test('formatted stock date and units are equivalent', () {
    const source = '## 库存\n- 桃子味脉动：**8瓶**（600mL）。\n- 有效期：2026-06-28，**已经过期**。';
    const read = '库存。桃子味脉动，八瓶，六百毫升。有效期二零二六年六月二十八日，已经过期。';
    expect(SpeechText.matches(source, read), true);
    expect(SpeechText.matches(source, read.replaceFirst('八瓶', '九瓶')), false);
  });
  test('exact decimal measurements, percentage and signs', () {
    expect(
      SpeechText.matches('温度26.5℃，湿度50%，重量2kg', '温度二十六点五摄氏度，湿度百分之五十，重量两千克'),
      true,
    );
    expect(SpeechText.matches('容量600mL', '容量零点六升'), true);
    expect(SpeechText.matches('容量600mL', '容量六升'), false);
    expect(SpeechText.matches('温度为-5.5度', '温度为负五点五度'), true);
    expect(SpeechText.matches('温度为26.50度', '温度为二十六点五度'), true);
    expect(SpeechText.matches('温度-5度', '温度5度'), false);
    expect(SpeechText.matches('温度- 5度', '温度5度'), false);
    expect(SpeechText.matches('湿度50%', '湿度百分之五'), false);
  });
  test('ambiguous shorthand is not guessed', () {
    for (final pair in [
      ('650', '六百五'),
      ('605', '六百五'),
      ('110', '十百'),
      ('600', '六百零'),
    ]) {
      expect(SpeechText.matches('容量为${pair.$1}毫升', '容量为${pair.$2}毫升'), false);
    }
    expect(SpeechText.matches('容量为605毫升', '容量为六百零五毫升'), true);
    expect(SpeechText.matches('库存为10002瓶', '库存为一万二瓶'), false);
    expect(SpeechText.matches('库存为10002瓶', '库存为一万零二瓶'), true);
  });
  test('ordered lists keep indices and order', () {
    const source = '1. 牛奶还剩2盒。\n2. 脉动还剩8瓶。';
    expect(SpeechText.matches(source, '第一项，牛奶还剩两盒。第二项，脉动还剩八瓶。'), true);
    expect(SpeechText.matches(source, '第一项，脉动还剩八瓶。第二项，牛奶还剩两盒。'), false);
  });
  test('dates clocks and numeric separators retain exact values', () {
    expect(
      SpeechText.matches('提醒时间：2026/10/07 14:30', '提醒时间，二零二六年十月七日，十四点三十分'),
      true,
    );
    expect(SpeechText.matches('提醒时间14:30', '提醒时间十四点四十分'), false);
    expect(SpeechText.matches('日期2026-02-30', '日期2026年3月2日'), false);
    expect(SpeechText.matches('编号1,2', '编号12'), false);
    expect(SpeechText.matches('容量1,000毫升', '容量一升'), true);
  });
  test('literal code, device identifiers and arithmetic are retained', () {
    expect(
      SpeechText.matches(
        '设备 `light.living_room_2` **未关闭**。',
        '设备light.living_room_2未关闭。',
      ),
      true,
    );
    expect(
      SpeechText.matches(
        '设备 `light.living_room_2` 未关闭',
        '设备light.living_room_3未关闭',
      ),
      false,
    );
    expect(SpeechText.matches('结果2*3*4', '结果234'), false);
    final prepared = SpeechText.forReading('标记 `**原样内容**`。\n代码`1. foo`。\n符号 #');
    expect(prepared, contains('**原样内容**'));
    expect(prepared, contains('1. foo'));
    expect(prepared, endsWith('符号 #'));
    expect(SpeechText.matchesPrepared('标记 **原样内容**', '标记原样内容'), false);
  });
  test('speech chunks preserve all characters and emoji boundaries', () {
    final source = ('正文。😀' * 250);
    final parts = SpeechText.chunks(source);
    expect(parts.join(), source);
    expect(parts.every((p) => p.length <= 600), true);
    expect(parts.every((p) => !p.endsWith(String.fromCharCode(0xd83d))), true);
  });
  test('Omni configuration is shared, tool-free and workspace validated', () {
    expect(
      workspaceId('https://test-space.cn-beijing.maas.aliyuncs.com/path'),
      'test-space',
    );
    expect(() => workspaceId('other.host.example'), throwsFormatException);
    expect(omniConfig(true)['session']['tools'], isEmpty);
    expect(
      omniConfig(false)['session']['input_audio_transcription']['model'],
      'qwen3-asr-flash-realtime',
    );
  });
  test('audio final transcript replaces only its own indexed part', () {
    final response = SpeechResponse();
    response.accept({
      'type': 'response.audio_transcript.delta',
      'response_id': 'r',
      'output_index': 0,
      'content_index': 0,
      'delta': '前半段',
    });
    response.accept({
      'type': 'response.audio_transcript.done',
      'response_id': 'r',
      'output_index': 1,
      'content_index': 0,
      'transcript': '后半段',
    });
    response.accept({
      'type': 'response.done',
      'response': {
        'id': 'r',
        'status': 'completed',
        'output': [
          {
            'type': 'message',
            'role': 'assistant',
            'content': [
              {'type': 'audio', 'transcript': '正确前半段'},
            ],
          },
          {
            'type': 'message',
            'role': 'assistant',
            'content': [
              {'type': 'audio', 'transcript': '正确后半段'},
            ],
          },
        ],
      },
    });
    expect(response.completed, true);
    expect(response.transcript, '正确前半段 正确后半段');
  });
  test('foreign responses, independent text, missing audio transcript are rejected', () {
    final response = SpeechResponse();
    response.accept({
      'type': 'response.audio.delta',
      'response_id': 'r',
      'output_index': 0,
      'content_index': 0,
    });
    expect(
      response.accept({
        'type': 'response.audio_transcript.done',
        'response_id': 'other',
        'transcript': '假的',
      }),
      false,
    );
    response.accept({
      'type': 'response.done',
      'response': {
        'id': 'r',
        'status': 'completed',
        'output': [
          {
            'type': 'message',
            'role': 'assistant',
            'content': [
              {'type': 'audio'},
              {'type': 'text', 'text': '正文'},
            ],
          },
        ],
      },
    });
    expect(response.transcript, '');
    expect(response.completed, true);
  });
  test('tool calls and incomplete responses are distinguished', () {
    final response = SpeechResponse();
    response.accept({
      'type': 'response.output_item.added',
      'response_id': 'r',
      'item': {'type': 'function_call'},
    });
    response.accept({
      'type': 'response.done',
      'response': {'id': 'r', 'status': 'incomplete'},
    });
    expect(response.tool, true);
    expect(response.completed, false);
  });
}
