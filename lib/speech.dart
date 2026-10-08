import 'dart:math';

import 'models.dart';

// Deterministic fact-preserving normalization, shared by Android and iOS.
class SpeechNumbers {
  static const chars = '0-9零〇一二两三四五六七八九十百千万亿';
  static int digit(String c) =>
      int.tryParse(c) ??
      const {
        '零': 0,
        '〇': 0,
        '一': 1,
        '二': 2,
        '两': 2,
        '三': 3,
        '四': 4,
        '五': 5,
        '六': 6,
        '七': 7,
        '八': 8,
        '九': 9,
      }[c] ??
      -1;
  static String? digits(String value) {
    if (value.isEmpty) return null;
    final buffer = StringBuffer();
    for (final c in value.split('')) {
      final n = digit(c);
      if (n < 0) return null;
      buffer.write(n);
    }
    return buffer.toString();
  }

  static BigInt? integer(String value) {
    final sequence = digits(value);
    if (sequence != null) return BigInt.tryParse(sequence);
    if (RegExp('[0-9]').hasMatch(value)) return null;
    for (final c in ['亿', '万']) {
      final index = value.indexOf(c);
      if (index < 0) continue;
      if (index == 0 || value.indexOf(c, index + 1) >= 0) return null;
      final head = integer(value.substring(0, index)),
          remainder = value.substring(index + 1);
      final tail = remainder.isEmpty ? BigInt.zero : integer(remainder),
          scale = BigInt.from(c == '亿' ? 100000000 : 10000);
      if (head == null ||
          tail == null ||
          head <= BigInt.zero ||
          tail >= scale) {
        return null;
      }
      if (remainder.isNotEmpty &&
          tail < scale ~/ BigInt.from(10) &&
          !remainder.startsWith('零') &&
          !remainder.startsWith('〇')) {
        return null;
      }
      return head * scale + tail;
    }
    var total = 0, pending = -1, last = 10000;
    var zero = false;
    for (final c in value.split('')) {
      final n = digit(c);
      if (n >= 0) {
        if (pending > 0) return null;
        if (n == 0) zero = true;
        pending = n;
        continue;
      }
      final scale = const {'十': 10, '百': 100, '千': 1000}[c] ?? 0;
      if (scale == 0 || scale >= last) return null;
      if (pending < 0) {
        if (scale == 10 && total == 0) {
          pending = 1;
        } else {
          return null;
        }
      }
      if (pending == 0) return null;
      total += pending * scale;
      pending = -1;
      last = scale;
      zero = false;
    }
    if ((pending >= 0 && last >= 100 && !zero) || (pending == 0 && zero)) {
      return null;
    }
    return BigInt.from(total + max(0, pending));
  }

  static String? number(String value) {
    final negative = RegExp(r'^[负−-]').hasMatch(value);
    value = value.replaceFirst(RegExp(r'^[负正+−-]'), '');
    final parts = value.replaceAll('点', '.').split('.');
    if (parts.length > 2) return null;
    final whole = integer(parts.first);
    if (whole == null) return null;
    var fraction = parts.length == 2 ? digits(parts[1]) : '';
    if (fraction == null) return null;
    fraction = fraction.replaceFirst(RegExp(r'0+$'), '');
    return '${negative && (whole != BigInt.zero || fraction.isNotEmpty) ? '-' : ''}$whole${fraction.isEmpty ? '' : '.$fraction'}';
  }

  static String canonical(String value) => value.replaceAllMapped(
    RegExp(
      '(?<![$chars.点])([+\\-−负正]?[$chars]+(?:[.点][0-9零〇一二两三四五六七八九]+)?)(?=\\s*(?:毫升|升|瓶|罐|盒|个|件|项|包|袋|年|月|日|号|天|小时|分钟|秒|摄氏度|度|℃|％|%|元|千克|公斤|克|厘米|毫米|米|瓦|伏|安))',
    ),
    (m) => number(m[1]!) ?? m[1]!,
  );
  static String scale(String value, int factor) {
    final negative = value.startsWith('-');
    value = value.replaceFirst(RegExp(r'^[+-]'), '');
    final parts = value.split('.'), fraction = parts.length > 1 ? parts[1] : '';
    final coefficient =
        BigInt.parse('${parts[0]}$fraction') * BigInt.from(factor);
    var digits = coefficient.toString().padLeft(fraction.length + 1, '0');
    if (fraction.isNotEmpty) {
      digits =
          '${digits.substring(0, digits.length - fraction.length)}.${digits.substring(digits.length - fraction.length)}';
    }
    return number('${negative ? '-' : ''}$digits') ?? value;
  }
}

class SpeechText {
  static const n = SpeechNumbers.chars;
  static String clock(String? h, String? m, String? s, String original) {
    final hour = int.tryParse(SpeechNumbers.number(h ?? '') ?? ''),
        minute = int.tryParse(SpeechNumbers.number(m ?? '') ?? ''),
        second = s == null ? 0 : int.tryParse(SpeechNumbers.number(s) ?? '');
    if (hour == null ||
        minute == null ||
        second == null ||
        hour > 23 ||
        minute > 59 ||
        second > 59 ||
        hour < 0 ||
        minute < 0 ||
        second < 0) {
      return original;
    }
    return '$hour时$minute分${s == null ? '' : '$second秒'}';
  }

  static String values(String value) {
    value = value.replaceAllMapped(
      RegExp(
        r'(?<![0-9A-Za-z_.,])([+\-−]?[0-9]{1,3}(?:[,，][0-9]{3})+)(?![0-9,，])',
      ),
      (m) => m[1]!.replaceAll(RegExp('[,，]'), ''),
    );
    value = value.replaceAllMapped(
      RegExp(
        r'(?<![0-9A-Za-z_/.-])([0-9]{4})([-/])([0-9]{1,2})\2([0-9]{1,2})(?![0-9A-Za-z_/.-])',
      ),
      (m) {
        final y = int.parse(m[1]!),
            month = int.parse(m[3]!),
            day = int.parse(m[4]!);
        final date = DateTime(y, month, day);
        return y > 0 && date.year == y && date.month == month && date.day == day
            ? '$y年$month月$day日'
            : m[0]!;
      },
    );
    value = value.replaceAllMapped(
      RegExp(
        r'(?<![0-9A-Za-z_/.-])([0-9]{1,2}):([0-9]{2})(?::([0-9]{2}))?(?![0-9A-Za-z_:/])',
      ),
      (m) => clock(m[1], m[2], m[3], m[0]!),
    );
    value = value.replaceAllMapped(
      RegExp(
        '(?<![${n}A-Za-z_.点])([$n]{1,6})(?:点|时)([$n]{1,6})分(?:([$n]{1,6})秒)?(?![$n钟])',
      ),
      (m) => clock(m[1], m[2], m[3], m[0]!),
    );
    return value.replaceAllMapped(
      RegExp(
        '(?<![${n}A-Za-z_/.点])([+\\-−负正]?[$n]+(?:[.点][$n]+)?)\\s*(m[lL]|[lL]|kg|g|cm|mm|m|℃|°[cC]|％|%)(?![A-Za-z0-9_²³])',
        caseSensitive: false,
      ),
      (m) {
        final unit = m[2]!.toLowerCase();
        if (unit == '%' || unit == '％') return '百分之${m[1]}';
        return '${m[1]}${const {'ml': '毫升', 'l': '升', 'kg': '千克', 'g': '克', 'cm': '厘米', 'mm': '毫米', 'm': '米'}[unit] ?? '摄氏度'}';
      },
    );
  }

  static String emphasis(String value) {
    for (var i = 0; i < 2; i++) {
      value = value.replaceAllMapped(
        RegExp(r'(?<![0-9*\\])\*\*(?=\S)(.+?)(?<=\S)\*\*(?![0-9*])'),
        (m) => m[1]!,
      );
      value = value.replaceAllMapped(
        RegExp(
          r'(?<![\p{L}\p{N}_*\\])\*(?=\S)(.+?)(?<=\S)\*(?![\p{L}\p{N}_*])',
          unicode: true,
        ),
        (m) => m[1]!,
      );
    }
    return value;
  }

  static String forReading(String value) {
    final output = <String>[];
    var fence = '';
    for (var line
        in value.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n')) {
      final edge = RegExp(r'^ {0,3}(`{3,}|~{3,})([^`~]*)$').firstMatch(line);
      if (edge != null &&
          (fence.isEmpty ||
              edge[1]![0] == fence[0] &&
                  edge[1]!.length >= fence.length &&
                  edge[2]!.trim().isEmpty)) {
        fence = fence.isEmpty ? edge[1]! : '';
        output.add('');
        continue;
      }
      if (fence.isEmpty) {
        if (RegExp(r'^ {0,3}#{1,6}[ \t]+').hasMatch(line)) {
          line = line
              .replaceFirst(RegExp(r'^ {0,3}#{1,6}[ \t]+'), '')
              .replaceFirst(RegExp(r'[ \t]+#+[ \t]*$'), '');
        }
        line = line.replaceFirst(
          RegExp('^[ \\t]*[>*+\\-][ \\t]+(?=[^$n])'),
          '',
        );
        line = line.replaceFirstMapped(
          RegExp(r'^[ \t]*([0-9]{1,3})[.)][ \t]+'),
          (m) => '第${m[1]}项，',
        );
        if (RegExp(r'^[ \t]*(?:-{3,}|\*{3,}|_{3,})[ \t]*$').hasMatch(line)) {
          line = '';
        }
        final buffer = StringBuffer();
        var offset = 0;
        for (final match in RegExp(r'(`+)(.+?)\1').allMatches(line)) {
          buffer.write(emphasis(line.substring(offset, match.start)));
          buffer.write(match[2]);
          offset = match.end;
        }
        buffer.write(emphasis(line.substring(offset)));
        line = buffer.toString();
      }
      output.add(line);
    }
    return values(output.join('\n')).replaceAll(RegExp('[（）()]'), '，');
  }

  static String normalized(String value) {
    value = values(value.toLowerCase());
    value = value.replaceAllMapped(
      RegExp('([+\\-−负正]?)百分之([+\\-−负正]?)([$n]+(?:[.点][$n]+)?)(?![$n.点])'),
      (m) {
        if (m[1]!.isNotEmpty && m[2]!.isNotEmpty) return m[0]!;
        final number = SpeechNumbers.number('${m[1]}${m[2]}${m[3]}');
        return number == null ? m[0]! : '$number%';
      },
    );
    value = SpeechNumbers.canonical(value);
    value = value.replaceAllMapped(
      RegExp(
        r'(?<![0-9A-Za-z_/.-])([+\-]?[0-9]+(?:\.[0-9]+)?)(毫升|升|千克|公斤|克|厘米|毫米|米)(?![A-Za-z0-9_²³])',
      ),
      (m) {
        final unit = m[2]!,
            factor = ['升', '千克', '公斤', '米'].contains(unit)
                ? 1000
                : unit == '厘米'
                ? 10
                : 1;
        final base = ['升', '毫升'].contains(unit)
            ? '毫升'
            : ['千克', '公斤', '克'].contains(unit)
            ? '克'
            : '毫米';
        return '${SpeechNumbers.scale(m[1]!, factor)}$base';
      },
    );
    value = value.replaceAllMapped(
      RegExp(r'([0-9]{4}年[0-9]{1,2}月[0-9]{1,2})号'),
      (m) => '${m[1]}日',
    );
    value = value
        .replaceAll(RegExp(r'(?<![0-9])[,，;；:：、]|[,，;；:：、](?![0-9])'), '')
        .replaceAll('，', ',')
        .replaceAll('；', ';')
        .replaceAll('：', ':');
    return value
        .replaceAll(RegExp('[。!！?？“”"‘’\'（）()\\p{Z}\\s]', unicode: true), '')
        .replaceAll(RegExp(r'(?<![0-9])\.|\.(?![0-9])'), '');
  }

  static bool matchesPrepared(String expected, String actual) =>
      normalized(expected).isNotEmpty &&
      normalized(expected) == normalized(actual);
  static bool matches(String expected, String actual) =>
      matchesPrepared(forReading(expected), forReading(actual));
  static List<String> chunks(String value) {
    final result = <String>[];
    while (value.length > 600) {
      var cut = 600;
      if (value.codeUnitAt(cut - 1) >= 0xd800 &&
          value.codeUnitAt(cut - 1) <= 0xdbff) {
        cut--;
      }
      for (var i = cut - 1; i >= 300; i--) {
        if ('。！？\n；.!?'.contains(value[i])) {
          cut = i + 1;
          break;
        }
      }
      result.add(value.substring(0, cut));
      value = value.substring(cut);
    }
    if (value.isNotEmpty) result.add(value);
    return result;
  }
}

class _AudioPart {
  String value = '';
  bool complete = false;
}

class SpeechResponse {
  final Map<int, _AudioPart> _parts = {};
  String responseId = '', status = '';
  bool finished = false, tool = false;
  _AudioPart _part(int output, int content) {
    if (output < 0 || content < 0) throw const FormatException('语音片段编号无效');
    return _parts.putIfAbsent((output << 32) | content, _AudioPart.new);
  }

  void _complete(_AudioPart part, String value) {
    if (value.trim().isNotEmpty) {
      part.value = value;
      part.complete = true;
    }
  }

  bool isTool(Json value) => [
    'function_call',
    'mcp_call',
    'mcp_approval_request',
  ].contains(value['type']);
  bool accept(Json event) {
    final type = text(event['type']),
        response = object(event['response']),
        id = text(event['response_id'] ?? response['id']);
    if (!type.startsWith('response.') || finished || id.isEmpty) return false;
    if (responseId.isEmpty) responseId = id;
    if (id != responseId) return false;
    final output = event['output_index'] is int
            ? event['output_index'] as int
            : 0,
        content = event['content_index'] is int
            ? event['content_index'] as int
            : 0;
    if (type == 'response.audio.delta') _part(output, content);
    if (type == 'response.audio_transcript.delta') {
      final p = _part(output, content);
      if (!p.complete) p.value += text(event['delta']);
    }
    if (type == 'response.audio_transcript.done') {
      _complete(_part(output, content), text(event['transcript']));
    }
    if (type == 'response.content_part.done' &&
        object(event['part'])['type'] == 'audio') {
      _complete(
        _part(output, content),
        text(object(event['part'])['transcript']),
      );
    }
    if (type == 'response.output_item.added') {
      tool |= isTool(object(event['item']));
    }
    if (type == 'response.done') {
      status = text(response['status']);
      finished = true;
      final required = <int>{};
      final outputs = objects(response['output']);
      for (var i = 0; i < outputs.length; i++) {
        final item = outputs[i];
        tool |= isTool(item);
        if (item['type'] != 'message' || item['role'] != 'assistant') continue;
        final contents = objects(item['content']);
        for (var j = 0; j < contents.length; j++) {
          if (contents[j]['type'] == 'audio') {
            required.add((i << 32) | j);
            _complete(_part(i, j), text(contents[j]['transcript']));
          }
        }
      }
      if (required.isNotEmpty) {
        _parts.removeWhere((key, _) => !required.contains(key));
      }
    }
    return true;
  }

  bool get completed => finished && status == 'completed';
  String get transcript {
    final keys = _parts.keys.toList()..sort();
    if (keys.any((key) => _parts[key]!.value.trim().isEmpty)) return '';
    return keys.map((key) => _parts[key]!.value).join(' ');
  }
}

class SpeechMismatch implements Exception {
  final String expected, actual;
  SpeechMismatch(String expected, String actual)
    : expected = expected.substring(0, min(2000, expected.length)),
      actual = actual.substring(0, min(2000, actual.length));
  @override
  String toString() => '语音内容未能与原文核对，未播放；可查看差异或点按语音重新生成';
}
