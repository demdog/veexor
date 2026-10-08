import 'dart:convert';
import 'dart:math';

typedef Json = Map<String, dynamic>;
Json object(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : {};
String text(Object? value) => value is String ? value : '';
List<Json> objects(Object? value) =>
    value is List ? value.whereType<Map>().map(object).toList() : [];
List<Json> rows(Object? value, List<String> keys) {
  if (value is List) return objects(value);
  final root = object(value);
  for (final key in keys) {
    if (root[key] is List) return objects(root[key]);
  }
  throw const FormatException('服务未返回可识别的列表');
}

final _random = Random.secure();
String newId() {
  final bytes = List.generate(16, (_) => _random.nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

bool validPerson(String id) => RegExp(
  r'^[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}$',
).hasMatch(id);
bool validImage(String id) => RegExp(r'^img_[a-f0-9]{32}$').hasMatch(id);
bool validPhoto(String name) => RegExp(
  r'^(photo_[A-Za-z0-9_-]+\.jpg|remote_[a-f0-9]{32}_img_[a-f0-9]{32}\.img)$',
).hasMatch(name);

class Person {
  final String id, name;
  const Person(this.id, this.name);
  static List<Person> parse(Object? value) {
    final source = rows(value, ['people', 'persons', 'items']);
    final result = <String, Person>{};
    for (final row in source) {
      final id = text(row['person_id'] ?? row['id']).toLowerCase();
      if (!validPerson(id)) continue;
      final name = text(
        row.containsKey('name') ? row['name'] : row['display_name'],
      ).trim();
      result.putIfAbsent(id, () => Person(id, name));
    }
    if (source.isNotEmpty && result.isEmpty) {
      throw const FormatException('没有有效成员，请检查家庭服务同步');
    }
    return result.values.toList();
  }

  String get label => name.isEmpty ? '称谓未同步' : name;
}

class Message {
  final Json data;
  Message(this.data) {
    data.putIfAbsent('message_id', newId);
  }
  factory Message.create(String role, String content, String kind) =>
      Message({'role': role, 'content': content, 'kind': kind});
  String get id => text(data['message_id']);
  String get role => text(data['role']);
  String get content => text(data['content']);
  String get kind => text(data['kind']).isEmpty ? 'text' : text(data['kind']);
  List<Json> get images =>
      objects(data['content_parts'])
          .where((p) => p['type'] == 'image')
          .toList();
}

class Session {
  final String id;
  String serverId = '',
      title = '新会话',
      draft = '',
      notice = '',
      personId = '',
      personName = '';
  bool busy = false, loaded = true, identityKnown = true;
  List<Json> photos = [];
  final List<Message> messages = [];
  Session([String? id]) : id = id ?? newId();
  bool get canSend => !busy && loaded && identityKnown;
  String get identityLabel => !identityKnown
      ? '待确认'
      : personId.isEmpty
      ? '未选择'
      : personName.isEmpty
      ? '称谓未同步'
      : personName;
  Message add(String role, String content, [String kind = 'text']) {
    final message = Message.create(role, content, kind);
    messages.add(message);
    if (messages.length > 200) messages.removeRange(0, messages.length - 200);
    return message;
  }

  Json toJson() => {
    'id': id,
    'server_id': serverId,
    'title': title,
    'draft': draft,
    'notice': notice,
    'person_id': personId,
    'person_name': personName,
    'identity_known': identityKnown,
    'busy': busy,
    'loaded': loaded,
    'photos': photos,
    'messages': messages.map((m) => m.data).toList(),
  };
  factory Session.fromJson(Json row) {
    final s = Session(text(row['id']).isEmpty ? null : text(row['id']));
    s.serverId = text(row['server_id']);
    s.title = text(row['title']).isEmpty ? '新会话' : text(row['title']);
    s.draft = text(row['draft']);
    s.loaded = row['loaded'] != false;
    final id = text(row['person_id']).toLowerCase();
    s.personId = validPerson(id) ? id : '';
    s.personName = s.personId.isEmpty ? '' : text(row['person_name']);
    s.identityKnown = row.containsKey('person_id')
        ? (id.isEmpty || validPerson(id)) && row['identity_known'] != false
        : s.serverId.isEmpty;
    s.notice = row['busy'] == true
        ? '上次请求未完成，结果未知。请同步历史；涉及电器时先查询状态。'
        : text(row['notice']);
    s.photos = objects(row['photos'])
        .where(
          (p) =>
              validPhoto(text(p['image_file'])) ||
              validImage(text(p['image_id'])),
        )
        .take(4)
        .toList();
    final history = objects(row['messages']);
    s.messages.addAll(
      history.skip(max(0, history.length - 200)).map(Message.new),
    );
    return s;
  }
}

class SessionBook {
  final List<Session> sessions = [];
  final Map<String, String> names = {};
  String selected = '', defaultPersonId = '', defaultPersonName = '';
  SessionBook() {
    create();
  }
  Session? find(String id) {
    for (final s in sessions) {
      if (s.id == id) return s;
    }
    return null;
  }

  Session get active => find(selected) ?? sessions.first;
  Session create() {
    final s = Session()
      ..personId = defaultPersonId
      ..personName = defaultPersonName;
    sessions.add(s);
    selected = s.id;
    return s;
  }

  void rememberPerson(String id, String name) {
    if (!validPerson(id)) throw const FormatException('成员身份编号无效');
    id = id.toLowerCase();
    names[id] = name.trim();
    if (defaultPersonId == id) defaultPersonName = names[id]!;
    for (final s in sessions) {
      if (s.personId == id) s.personName = names[id]!;
    }
  }

  Session choosePerson(String id, String name) {
    if (id.isNotEmpty && !validPerson(id)) {
      throw const FormatException('成员身份编号无效');
    }
    id = id.toLowerCase();
    if (id.isNotEmpty) rememberPerson(id, name);
    defaultPersonId = id;
    defaultPersonName = names[id] ?? '';
    final current = active;
    if (current.identityKnown && current.personId == id) {
      current.personName = defaultPersonName;
      return current;
    }
    if (current.busy ||
        current.serverId.isNotEmpty ||
        current.messages.isNotEmpty ||
        !current.identityKnown) {
      return create();
    }
    current.personId = id;
    current.personName = defaultPersonName;
    return current;
  }

  void newSession() {
    if (active.identityKnown) {
      defaultPersonId = active.personId;
      defaultPersonName = active.personName;
    }
    create();
  }

  void close(String id) {
    final index = sessions.indexWhere((s) => s.id == id);
    if (index < 0) return;
    sessions.removeAt(index);
    if (sessions.isEmpty) {
      create();
      return;
    }
    if (selected == id) selected = sessions[min(index, sessions.length - 1)].id;
  }

  Session open(String id, String title) {
    for (final s in sessions) {
      if (s.serverId == id) {
        selected = s.id;
        return s;
      }
    }
    return create()
      ..serverId = id
      ..title = title
      ..loaded = false
      ..identityKnown = false
      ..personId = ''
      ..personName = '';
  }

  void applyIdentity(Session session, Object? value) {
    var root = object(value);
    if (!root.containsKey('person_id')) root = object(root['conversation']);
    if (!root.containsKey('person_id')) {
      session.identityKnown = false;
      return;
    }
    final id = text(root['person_id']).toLowerCase();
    if (id.isNotEmpty && !validPerson(id)) {
      throw const FormatException('历史会话的身份无效');
    }
    if (id.isNotEmpty && !names.containsKey(id)) {
      rememberPerson(id, text(root['person_name']));
    }
    session.personId = id;
    session.personName = names[id] ?? '';
    session.identityKnown = true;
  }

  void replaceHistory(Session session, List<Json> history) {
    final old = List<Message>.of(session.messages);
    final fresh = <Message>[];
    for (final row in history) {
      if (row['role'] != 'user' && row['role'] != 'assistant') continue;
      final message = Message({
        ...row,
        'content': text(row['content'] ?? row['message'] ?? row['answer']),
      });
      final index = old.indexWhere(
        (m) =>
            m.role == message.role &&
            m.content == message.content &&
            sameImages(m, message),
      );
      if (index >= 0) {
        final previous = old.removeAt(index);
        for (final key in [
          'kind',
          'message_id',
          'audio_file',
          'sample_rate',
          'duration_ms',
          'voice_status',
          'speech_expected',
          'speech_actual',
        ]) {
          if (previous.data.containsKey(key)) {
            message.data[key] = previous.data[key];
          }
        }
        final photos = message.images, previousPhotos = previous.images;
        for (var i = 0; i < photos.length; i++) {
          if (validPhoto(text(previousPhotos[i]['image_file']))) {
            photos[i]['image_file'] = previousPhotos[i]['image_file'];
          }
        }
        message.data['content_parts'] = localParts(message.content, photos);
      }
      fresh.add(message);
    }
    session.messages
      ..clear()
      ..addAll(fresh.skip(max(0, fresh.length - 200)));
  }

  String save() => jsonEncode({
    'selected': selected,
    'person_id': defaultPersonId,
    'person_name': defaultPersonName,
    'person_names': names,
    'sessions': sessions.map((s) => s.toJson()).toList(),
  });
  factory SessionBook.restore(String raw) {
    final book = SessionBook();
    if (raw.isEmpty) return book;
    final root = object(jsonDecode(raw));
    final list = objects(root['sessions']);
    if (root['sessions'] is! List) throw const FormatException('会话缓存结构无效');
    book.sessions.clear();
    for (final entry in object(root['person_names']).entries) {
      if (validPerson(entry.key)) {
        book.names[entry.key.toLowerCase()] = text(entry.value);
      }
    }
    final defaultId = text(root['person_id']).toLowerCase();
    if (validPerson(defaultId)) {
      book.defaultPersonId = defaultId;
      book.names.putIfAbsent(defaultId, () => text(root['person_name']));
    }
    for (final row in list) {
      final s = Session.fromJson(row);
      book.sessions.add(s);
      if (s.personId.isNotEmpty) {
        book.names.putIfAbsent(s.personId, () => s.personName);
      }
    }
    for (final s in book.sessions) {
      s.personName = book.names[s.personId] ?? '';
    }
    book.defaultPersonName = book.names[defaultId] ?? '';
    book.selected = text(root['selected']);
    if (book.sessions.isEmpty) {
      book.create();
    } else if (book.find(book.selected) == null) {
      book.selected = book.sessions.first.id;
    }
    return book;
  }
}

bool sameImages(Message a, Message b) {
  final left = a.images, right = b.images;
  if (left.length != right.length) return false;
  for (var i = 0; i < left.length; i++) {
    if (!validImage(text(left[i]['image_id'])) ||
        left[i]['image_id'] != right[i]['image_id']) {
      return false;
    }
  }
  return true;
}

List<Json> localParts(String value, List<Json> photos) => [
  {'type': 'text', 'text': value},
  ...photos.map((p) => {...p, 'type': 'image'}),
];
Json chatRequest(
  String value,
  List<Json> photos,
  String conversation,
  String person,
) {
  if (value.trim().isEmpty) {
    if (photos.isEmpty) throw const FormatException('请输入文字或添加照片');
    value = '请识别照片中的物品。';
  }
  if (value.length > 4000) throw const FormatException('文字最多 4000 字符');
  if (photos.length > 4) throw const FormatException('每次最多 4 张照片');
  if (person.isNotEmpty && !validPerson(person)) {
    throw const FormatException('成员身份编号无效');
  }
  for (final photo in photos) {
    if (!validImage(text(photo['image_id']))) {
      throw const FormatException('照片上传编号无效');
    }
  }
  return {
    'content': [
      {'type': 'text', 'text': value},
      ...photos.map((p) => {'type': 'image', 'image_id': p['image_id']}),
    ],
    if (conversation.isEmpty)
      'new_conversation': true
    else
      'conversation_id': conversation,
    if (person.isNotEmpty) 'person_id': person,
  };
}
