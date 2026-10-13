import 'dart:async';

import 'package:flutter/foundation.dart';

import 'host.dart';
import 'models.dart';
import 'omni.dart';
import 'speech.dart';

String readable(Object error) {
  if (error is FormatException) return error.message;
  if (error is TimeoutException) {
    return error.message ?? '请求超时，结果未知，请先同步历史或查询状态';
  }
  final message = error.toString().replaceFirst(
    RegExp(r'^(Exception|HttpException|FileSystemException):\s*'),
    '',
  );
  return message.length > 500 ? message.substring(0, 500) : message;
}

class ChatController extends ChangeNotifier {
  final Host host;
  final DateTime Function() now;
  final config = AppConfig();
  SessionBook book = SessionBook();
  bool ready = false,
      foreground = true,
      recording = false,
      cancelArmed = false,
      playing = false;
  String connection = '连接家庭 Wi-Fi，随时和家聊聊', error = '', voiceStatus = '';
  int _profile = 0, _playGeneration = 0;
  Session? _recordOwner;
  double _startY = 0;
  DateTime? _recordStarted;
  Future<Object?>? _recordStart;
  Timer? _recordTimer, _saveTimer;
  final Set<String> _generating = {};
  final Map<String, Message> _voiceMessages = {};
  bool _disposed = false;
  ChatController(this.host, {DateTime Function()? now})
    : now = now ?? DateTime.now {
    host.onEvent(_event);
  }
  Session get active => book.active;
  void refresh() {
    if (!_disposed) notifyListeners();
  }

  bool _owns(Session s, int profile) =>
      !_disposed && profile == _profile && identical(book.find(s.id), s);
  bool _needsHistory(Session s) =>
      !s.loaded ||
      !s.identityKnown ||
      s.messages.any((m) => m.data['awaiting_reply'] == true);
  Future<void> initialize() async {
    try {
      final boot = object(await host.call('bootstrap'));
      config.load(boot);
      try {
        book = SessionBook.restore(text(boot['sessions']));
      } catch (_) {
        error = '会话缓存无法读取，可从历史重新打开';
      }
      ready = true;
      refresh();
      await host.call('cleanup', {'state': book.save()});
      if (config.token.isNotEmpty) {
        unawaited(checkConnection());
        unawaited(people().catchError((_) => <Person>[]));
        if (_needsHistory(active)) {
          unawaited(loadHistory(active));
        }
      }
    } catch (e) {
      error = readable(e);
      ready = true;
      refresh();
    }
  }

  void save({bool immediately = false}) {
    _saveTimer?.cancel();
    void write() {
      unawaited(
        host
            .call('saveState', {
              'state': book.save(),
              'voice_mode': config.voiceMode,
            })
            .catchError((Object e) {
              error = '保存失败：${readable(e)}';
              refresh();
              return null;
            }),
      );
    }

    if (immediately) {
      write();
    } else {
      _saveTimer = Timer(const Duration(milliseconds: 250), write);
    }
  }

  Future<Object?> request(
    String path, {
    String method = 'GET',
    Json? body,
    String? id,
  }) => host.call('request', {
    'id': id ?? 'read_${newId()}',
    'path': path,
    'method': method,
    'body': ?body,
  });
  Future<void> checkConnection() async {
    final generation = _profile;
    connection = '正在连接家庭服务…';
    refresh();
    try {
      final status = object(await request('/v1/status'));
      if (_profile != generation || _disposed) return;
      connection =
          '家庭已连接 · 模型${status['llm_configured'] == true ? '已配置' : '未配置'} · 物品${status['isaac_online'] == true ? '在线' : '离线'}';
    } catch (e) {
      if (_profile == generation) connection = readable(e);
    }
    refresh();
  }

  Future<List<Person>> people() async {
    final generation = _profile;
    try {
      final members = Person.parse(await request('/v1/personal-sync/people'));
      if (_profile == generation && !_disposed) {
        for (final person in members) {
          book.rememberPerson(person.id, person.name);
        }
        save();
        refresh();
      }
      return members;
    } catch (e) {
      rethrow;
    }
  }

  void choosePerson(Person? person) {
    stopVoice();
    book.choosePerson(person?.id ?? '', person?.name ?? '');
    save();
    refresh();
  }

  void select(String id) {
    if (book.find(id) == null) return;
    stopVoice();
    book.selected = id;
    save();
    refresh();
    if (_needsHistory(active)) unawaited(loadHistory(active));
  }

  void create() {
    stopVoice();
    book.newSession();
    save();
    refresh();
  }

  void close(String id) {
    if (book.selected == id) stopVoice();
    unawaited(host.call('cancel', {'prefix': id}));
    book.close(id);
    save();
    refresh();
    if (_needsHistory(active)) unawaited(loadHistory(active));
  }

  void draft(String value) {
    active.draft = value;
    save();
  }

  void toggleMode() {
    stopVoice();
    config.voiceMode = !config.voiceMode;
    save();
    refresh();
  }

  Future<void> saveConfig(Json values) async {
    final base = AppConfig.validateBase(text(values['base'])),
        token = text(values['token']).trim(),
        key = text(values['aliyun']).trim();
    var workspace = text(values['workspace']).trim();
    if (token.isEmpty ||
        RegExp('[\r\n]').hasMatch(token) ||
        RegExp('[\r\n]').hasMatch(key)) {
      throw const FormatException('请填写有效访问令牌');
    }
    if (workspace.isNotEmpty || key.isNotEmpty) {
      workspace = workspaceId(workspace);
      if (key.isEmpty) throw const FormatException('请填写百炼 API Key，或同时清空语音设置');
    }
    final changed = base != config.base || token != config.token;
    if (changed && book.sessions.any((s) => s.busy)) {
      throw const FormatException('请求正在处理中，请等待完成或关闭会话后更换服务');
    }
    stopVoice();
    if (changed) {
      _profile++;
      await host.call('cancel', {'prefix': ''});
    }
    await host.call('saveConfig', {
      'base': base,
      'token': token,
      'workspace': workspace,
      'aliyun': key,
      'voice_mode': config.voiceMode,
    });
    config.base = base;
    config.token = token;
    config.workspace = workspace;
    config.aliyunKey = key;
    if (changed) book = SessionBook();
    save(immediately: true);
    refresh();
    unawaited(checkConnection());
    unawaited(people().catchError((_) => <Person>[]));
  }

  Future<void> sendText() async {
    if (!active.canSend) return;
    final value = active.draft.trim();
    if (value.isEmpty && active.photos.isEmpty) return;
    if (!_canStartRequest()) return;
    stopVoice();
    await _submit(active, value, 'text');
  }

  bool _canStartRequest() {
    if (config.token.isEmpty) {
      error = '请先在设置中填写家庭服务访问令牌';
      refresh();
      return false;
    }
    if (book.sessions.where((s) => s.busy).length + (recording ? 1 : 0) >= 4) {
      error = '已有 4 个会话正在处理，请等待其中一个完成';
      refresh();
      return false;
    }
    error = '';
    return true;
  }

  Future<void> _submit(
    Session session,
    String value,
    String kind, [
    Message? existing,
  ]) async {
    final profile = _profile, person = session.personId;
    var conversation = session.serverId;
    if (!session.identityKnown) return;
    if (value.isEmpty && session.photos.isNotEmpty) value = '请识别照片中的物品。';
    if (value.length > 4000) {
      session.busy = false;
      session.notice = '内容最多 4000 字符，请分段发送';
      save();
      refresh();
      return;
    }
    final photos = session.photos
        .map((p) => Map<String, dynamic>.from(p))
        .toList();
    final message = existing ?? session.add('user', value, kind);
    message.data['content'] = value;
    message.data['content_parts'] = localParts(value, photos);
    if (existing == null) session.draft = '';
    session.photos = [];
    session.busy = true;
    session.notice = '正在等待回复…';
    if (session.title == '新会话') {
      session.title = String.fromCharCodes(value.runes.take(10));
    }
    save(immediately: true);
    refresh();
    var submitted = false;
    try {
      for (var i = 0; i < photos.length; i++) {
        if (!_owns(session, profile)) return;
        session.notice = '正在上传照片 ${i + 1}/${photos.length}…';
        refresh();
        if (!validImage(text(photos[i]['image_id']))) {
          final uploaded = object(
            await host.call('upload', {
              'id': '${session.id}_upload_$i',
              'image_file': text(photos[i]['image_file']),
            }),
          );
          if (!validImage(text(uploaded['image_id']))) {
            throw const FormatException('照片上传编号无效');
          }
          photos[i]['image_id'] = uploaded['image_id'];
        }
        if (!_owns(session, profile)) return;
        message.data['content_parts'] = localParts(value, photos);
        save();
      }
      if (!_owns(session, profile)) return;
      if (conversation.isEmpty) {
        session.notice = '正在创建会话…';
        refresh();
        final created = object(
          await request(
            '/v1/conversations',
            method: 'POST',
            id: '${session.id}_create',
          ),
        );
        if (!_owns(session, profile)) return;
        conversation = text(created['conversation_id'] ?? created['id']);
        if (!RegExp(r'^chat_[a-f0-9]{32}$').hasMatch(conversation)) {
          throw const FormatException('无法取得会话编号，聊天尚未发送');
        }
        session.serverId = conversation;
        // Persist the recovery address before a side-effecting chat is submitted.
        await host.call('saveState', {
          'state': book.save(),
          'voice_mode': config.voiceMode,
        });
        if (!_owns(session, profile)) return;
      }
      final body = chatRequest(value, photos, conversation, person);
      message.data['awaiting_reply'] = true;
      await host.call('saveState', {
        'state': book.save(),
        'voice_mode': config.voiceMode,
      });
      if (!_owns(session, profile)) return;
      submitted = true;
      session.notice = photos.isEmpty ? '正在等待回复…' : '正在识别照片并回答…';
      refresh();
      final reply = object(
        await request(
          '/v1/chat',
          method: 'POST',
          body: body,
          id: '${session.id}_chat',
        ),
      );
      if (!_owns(session, profile)) return;
      if (text(reply['conversation_id']).isEmpty ||
          reply['answer'] is! String) {
        throw const FormatException('回答结构无法识别，请先同步历史确认结果');
      }
      session.serverId = text(reply['conversation_id']);
      session.busy = false;
      session.notice = '';
      message.data.remove('voice_status');
      message.data.remove('awaiting_reply');
      final answer = session.add('assistant', text(reply['answer']), kind);
      for (final field in ['items', 'devices', 'scene_tasks']) {
        if (reply[field] is List) answer.data[field] = reply[field];
      }
      save(immediately: true);
      refresh();
      if (kind == 'voice') {
        unawaited(generateAudio(session, answer, autoplay: true));
      }
    } catch (e) {
      if (!_owns(session, profile)) return;
      session.busy = false;
      session.notice = submitted
          ? '${readable(e)}；结果需从历史确认，未自动重发。'
          : readable(e);
      if (!submitted) {
        message.data.remove('awaiting_reply');
        if (existing == null && session.draft.isEmpty) session.draft = value;
        session.notice = '聊天尚未发送。${readable(e)}';
      }
      if (!submitted && photos.isNotEmpty) {
        session.photos = photos;
        if (session.draft.isEmpty) session.draft = value;
        session.notice = '照片上传未完成，聊天尚未发送。${readable(e)}';
      }
      if (kind == 'voice') message.data['voice_status'] = session.notice;
      save(immediately: true);
      refresh();
      if (submitted && session.serverId.isNotEmpty) {
        await loadHistory(session, pending: message, failure: readable(e));
      }
    }
  }

  Future<void> loadHistory(
    Session session, {
    Message? pending,
    String? failure,
  }) async {
    if (session.busy || session.serverId.isEmpty) return;
    pending ??= session.messages
        .where((m) => m.data['awaiting_reply'] == true)
        .lastOrNull;
    if (pending != null) failure ??= '上次回答接收未完成';
    final profile = _profile;
    session.busy = true;
    session.notice = pending == null
        ? '正在同步历史…'
        : '${failure ?? '结果未知'}；正在查询历史，未自动重发。';
    refresh();
    try {
      final all = <Json>[];
      Object? metadata;
      for (var offset = 0; offset < 1000; offset += 100) {
        final result = await request(
          '/v1/conversations/${Uri.encodeComponent(session.serverId)}?limit=100&offset=$offset',
          id: '${session.id}_history',
        );
        if (!_owns(session, profile)) return;
        if (offset == 0) metadata = result;
        final page = rows(result, ['messages', 'history', 'items']);
        all.addAll(page);
        if (page.length < 100) break;
        if (offset == 900) throw const FormatException('对话超过 1000 条，请开启新会话');
      }
      if (pending != null && all.isEmpty) {
        session.notice = '${failure ?? '结果未知'}；服务端暂未保存回答，请稍后同步历史，未自动重发。';
        return;
      }
      final meta = object(metadata), nested = object(meta['conversation']);
      if (meta.containsKey('person_id') ||
          nested.containsKey('person_id') ||
          !session.identityKnown) {
        book.applyIdentity(session, metadata);
      }
      book.replaceHistory(session, all);
      if (pending != null &&
          !session.messages.any((m) => m.id == pending!.id)) {
        session.messages.add(pending);
        if (session.messages.length > 200) {
          session.messages.removeRange(0, session.messages.length - 200);
        }
      }
      if (pending != null) {
        final index = session.messages.indexWhere((m) => m.id == pending!.id);
        if (index >= 0 &&
            index + 1 < session.messages.length &&
            session.messages[index + 1].role == 'assistant') {
          session.messages[index].data.remove('awaiting_reply');
          session.messages[index].data.remove('voice_status');
          session.messages[index + 1].data['kind'] = pending.kind;
        }
      }
      session.loaded = true;
      session.notice = session.identityKnown
          ? (all.length > 200 ? '已显示最近 200 条消息' : '')
          : '此历史未返回身份。可查看消息；请选择身份开启新会话。';
      if (pending != null) {
        session.notice = '${failure ?? '结果未知'}；已同步历史，请核对回答，未自动重发。';
      }
    } catch (e) {
      if (_owns(session, profile)) {
        session.notice = pending == null
            ? readable(e)
            : '${failure ?? '结果未知'}；历史恢复失败：${readable(e)}。请稍后同步历史，未自动重发。';
      }
    } finally {
      if (_owns(session, profile)) {
        session.busy = false;
        save();
        refresh();
      }
    }
  }

  Future<Json?> camera() async {
    final owner = active, profile = _profile;
    if (!owner.canSend || owner.photos.length >= 4) {
      throw const FormatException('请先完成当前请求，或移除照片；每次最多 4 张');
    }
    stopVoice();
    save(immediately: true);
    final result = object(await host.call('camera', {'owner': owner.id}));
    if (result.isEmpty) return null;
    if (!_owns(owner, profile)) {
      await discardPhoto(result);
      return null;
    }
    return result;
  }

  Future<Json?> recoverPhoto() async {
    final result = object(await host.call('recoverPhoto'));
    return result.isEmpty ? null : result;
  }

  Future<void> attachPhoto(Json photo, {String? owner}) async {
    final session =
        book.find(owner ?? text(photo['owner'])) ??
        (owner == null && !photo.containsKey('owner') ? active : null);
    if (session == null || !session.canSend) {
      throw const FormatException('原会话已关闭或正在处理，请稍后添加照片');
    }
    if (session.photos.length >= 4) throw const FormatException('每次最多 4 张照片');
    if (!validPhoto(text(photo['image_file'])) &&
        !validImage(text(photo['image_id']))) {
      throw const FormatException('照片不可用');
    }
    session.photos.add({
      for (final key in ['image_file', 'image_id', 'mime_type'])
        if (photo.containsKey(key)) key: photo[key],
    });
    save(immediately: true);
    refresh();
    await host.call('photoHandled');
  }

  Future<void> discardPhoto(Json photo) async {
    if (validPhoto(text(photo['image_file']))) {
      await host.call('deletePhoto', photo);
    }
    await host.call('photoHandled');
  }

  void removePhoto(Session session, Json photo) {
    if (session.busy) return;
    session.photos.remove(photo);
    save();
    refresh();
  }

  Future<void> beginHold(double y) async {
    if (recording || !active.canSend) return;
    if (!_canStartRequest()) return;
    if (!config.voiceReady) throw const FormatException('请先配置家庭服务和阿里 Omni 语音');
    stopVoice();
    final owner = active, profile = _profile;
    _recordOwner = owner;
    recording = true;
    cancelArmed = false;
    _startY = y;
    _recordStarted = now();
    voiceStatus = '正在录音 · 上划取消，松开发送';
    refresh();
    _recordStart = host.call('recordStart');
    Object? accepted;
    try {
      accepted = await _recordStart;
    } catch (_) {
      if (_recordOwner == owner) stopVoice();
      rethrow;
    }
    if (_recordOwner != owner || !_owns(owner, profile)) return;
    if (accepted != true) {
      recording = false;
      _recordOwner = null;
      voiceStatus = '请允许麦克风权限后重新按住说话';
      refresh();
      return;
    }
    _recordTimer = Timer(
      const Duration(seconds: 30),
      () => finishHold(_startY - (cancelArmed ? 64 : 0)),
    );
  }

  void moveHold(double y) {
    if (!recording) return;
    cancelArmed = _startY - y >= 64;
    voiceStatus = cancelArmed ? '松开手指，取消发送' : '正在录音 · 上划取消，松开发送';
    refresh();
  }

  Future<void> finishHold(double y, {bool cancelled = false}) async {
    final owner = _recordOwner;
    if (owner == null || !recording) return;
    final profile = _profile,
        elapsed = now().difference(_recordStarted!).inMilliseconds;
    final send = !cancelled && _startY - y < 64 && elapsed >= 300;
    recording = false;
    _recordOwner = null;
    _recordTimer?.cancel();
    if (!send) {
      await host.call('recordCancel');
      voiceStatus = elapsed < 300 && !cancelled ? '说话时间太短' : '已取消发送';
      refresh();
      return;
    }
    owner.busy = true;
    owner.notice = '正在识别语音…';
    voiceStatus = '正在发送语音…';
    refresh();
    try {
      final audio = object(await host.call('recordStop'));
      if (!_owns(owner, profile)) return;
      if (audio.isEmpty) throw const FormatException('请允许麦克风权限后重新按住说话');
      final message = owner.add('user', '', 'voice');
      message.data.addAll(audio);
      message.data['voice_status'] = '正在识别…';
      save(immediately: true);
      refresh();
      final id = '${owner.id}_${message.id}';
      _voiceMessages[id] = message;
      try {
        final utterance = text(
          await host.call('transcribe', {
            'id': id,
            'audio_file': text(audio['audio_file']),
          }),
        );
        if (_owns(owner, profile)) {
          owner.busy = false;
          await _submit(owner, utterance, 'voice', message);
        }
      } catch (e) {
        if (_owns(owner, profile)) {
          owner.busy = false;
          owner.notice = readable(e);
          message.data['voice_status'] = readable(e);
          save();
          refresh();
        }
      } finally {
        _voiceMessages.remove(id);
      }
    } catch (e) {
      if (_owns(owner, profile)) {
        owner.busy = false;
        owner.notice = readable(e);
        save();
        refresh();
      }
    }
  }

  Future<void> generateAudio(
    Session session,
    Message message, {
    bool autoplay = false,
  }) async {
    final id = '${session.id}_${message.id}',
        profile = _profile,
        playGeneration = _playGeneration;
    if (_generating.contains(id)) return;
    if (!config.voiceReady) {
      message.data['voice_status'] = '请配置阿里 Omni 后播放语音回复';
      refresh();
      return;
    }
    _generating.add(id);
    _voiceMessages[id] = message;
    message.data['voice_status'] = '正在生成语音回复…';
    refresh();
    try {
      final audio = object(
        await host.call('synthesize', {'id': id, 'text': message.content}),
      );
      if (!_owns(session, profile) || !session.messages.contains(message)) {
        return;
      }
      message.data.addAll(audio);
      for (final field in [
        'voice_status',
        'speech_expected',
        'speech_actual',
      ]) {
        message.data.remove(field);
      }
      save();
      refresh();
      if (autoplay &&
          foreground &&
          book.selected == session.id &&
          !recording &&
          !playing &&
          playGeneration == _playGeneration) {
        await play(session, message);
      }
    } catch (e) {
      if (_owns(session, profile) && session.messages.contains(message)) {
        message.data['voice_status'] = readable(e);
        if (e is SpeechMismatch) {
          message.data['speech_expected'] = e.expected;
          message.data['speech_actual'] = e.actual;
        }
        save();
        refresh();
      }
    } finally {
      _generating.remove(id);
      _voiceMessages.remove(id);
    }
  }

  Future<void> play(Session session, Message message) async {
    stopVoice();
    final generation = _playGeneration;
    if (text(message.data['audio_file']).isEmpty) {
      if (message.role == 'assistant') {
        await generateAudio(session, message, autoplay: true);
      } else {
        voiceStatus = '原始录音已不可用';
        refresh();
      }
      return;
    }
    try {
      await host.call('play', {
        'id': message.id,
        'audio_file': message.data['audio_file'],
        'sample_rate': message.data['sample_rate'] ?? 24000,
      });
      if (generation == _playGeneration) {
        playing = true;
        voiceStatus = '正在播放语音…';
        refresh();
      }
    } catch (e) {
      voiceStatus = readable(e);
      if (message.role == 'assistant') {
        message.data.remove('audio_file');
        message.data['voice_status'] = '播放失败，请点语音重试：${readable(e)}';
        save();
      }
      refresh();
    }
  }

  void stopVoice() {
    _playGeneration++;
    playing = false;
    unawaited(host.call('stopPlayback').catchError((_) => null));
    if (recording || _recordOwner != null) {
      recording = false;
      _recordOwner = null;
      _recordTimer?.cancel();
      unawaited(host.call('recordCancel').catchError((_) => null));
    }
    voiceStatus = '';
    refresh();
  }

  void background() {
    foreground = false;
    stopVoice();
    save(immediately: true);
  }

  void _event(Json event) {
    if (event['type'] == 'voice_state') {
      final message = _voiceMessages[text(event['id'])];
      if (message != null) {
        message.data['voice_status'] = text(event['state']);
        refresh();
      }
    }
    if (event['type'] == 'playback_done') {
      playing = false;
      voiceStatus = '';
      refresh();
    }
    if (event['type'] == 'recording_interrupted') {
      stopVoice();
      voiceStatus = '录音被系统中断，已取消发送';
      refresh();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _recordTimer?.cancel();
    _saveTimer?.cancel();
    unawaited(host.call('dispose'));
    super.dispose();
  }
}
