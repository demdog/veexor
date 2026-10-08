import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'chat_controller.dart';
import 'models.dart';
import 'settings_page.dart';

const green = Color(0xff1c7360),
    ink = Color(0xff1a2f2e),
    muted = Color(0xff6b7c77),
    canvas = Color(0xfff6f8f4);

class VeexorApp extends StatelessWidget {
  final ChatController controller;
  const VeexorApp({super.key, required this.controller});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Veexor',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: green, surface: canvas),
      scaffoldBackgroundColor: canvas,
      appBarTheme: const AppBarTheme(
        backgroundColor: canvas,
        foregroundColor: ink,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          backgroundColor: const Color(0xffe3ece5),
          foregroundColor: green,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    ),
    home: ChatPage(controller: controller),
  );
}

class ChatPage extends StatefulWidget {
  final ChatController controller;
  const ChatPage({super.key, required this.controller});
  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> with WidgetsBindingObserver {
  ChatController get c => widget.controller;
  final _input = TextEditingController(), _scroll = ScrollController();
  int? _pointer;
  String _session = '';
  int _messageCount = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    c.addListener(_changed);
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    await c.initialize();
    if (!mounted) return;
    await _safe(() async {
      final photo = await c.recoverPhoto();
      if (photo != null && mounted) await _preview(photo);
    });
    if (mounted && c.config.token.isEmpty) _settings();
  }

  void _changed() {
    if (!mounted) return;
    final changed = _session != c.active.id;
    if (changed || _input.text != c.active.draft) {
      _input.value = TextEditingValue(
        text: c.active.draft,
        selection: TextSelection.collapsed(offset: c.active.draft.length),
      );
    }
    final count = c.active.messages.length;
    final toBottom =
        changed ||
        count != _messageCount &&
            (!_scroll.hasClients || _scroll.position.extentAfter < 180);
    _session = c.active.id;
    _messageCount = count;
    setState(() {});
    if (toBottom) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scroll.hasClients) {
          _scroll.jumpTo(_scroll.position.maxScrollExtent);
        }
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      c.foreground = true;
    } else {
      _pointer = null;
      c.background();
    }
  }

  void _toast(String value) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(value)));
    }
  }

  Future<void> _safe(Future<void> Function() job) async {
    try {
      await job();
    } catch (e) {
      _toast(readable(e));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    c.removeListener(_changed);
    c.dispose();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = c.active;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Column(
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Veexor',
                      style: TextStyle(
                        fontSize: 27,
                        fontWeight: FontWeight.w700,
                        color: ink,
                      ),
                    ),
                  ),
                  IconButton(
                    key: const Key('camera'),
                    tooltip: '拍照',
                    onPressed: c.ready ? () => _safe(_camera) : null,
                    icon: const Icon(Icons.camera_alt_outlined),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: '设置',
                    onPressed: c.ready ? _settings : null,
                    icon: const Icon(Icons.tune),
                  ),
                ],
              ),
              Row(
                children: [
                  SizedBox(
                    width: 150,
                    child: TextButton(
                      onPressed: c.ready ? _identities : null,
                      child: Row(
                        children: [
                          Flexible(
                            child: Text(
                              '身份：${s.identityLabel}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const Icon(Icons.keyboard_arrow_down, size: 18),
                        ],
                      ),
                    ),
                  ),
                  Expanded(
                    child: InkWell(
                      onTap: () => _safe(c.checkConnection),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          c.connection,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: muted, fontSize: 11),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(
                height: 56,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final session in c.book.sessions)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: session.id == s.id
                                  ? const Color(0xffddede5)
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 120,
                                  child: TextButton(
                                    key: Key('session_${session.id}'),
                                    onPressed: () => c.select(session.id),
                                    child: Text(
                                      '${session.busy ? '… ' : ''}${session.title}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  tooltip: '关闭${session.title}',
                                  onPressed: () => _close(session),
                                  style: IconButton.styleFrom(
                                    backgroundColor: Colors.transparent,
                                    minimumSize: const Size(40, 44),
                                  ),
                                  icon: const Icon(Icons.close, size: 17),
                                ),
                              ],
                            ),
                          ),
                        ),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: SizedBox(
                          width: 56,
                          child: TextButton(
                            key: const Key('new_session'),
                            onPressed: c.create,
                            child: const Text(
                              '+',
                              style: TextStyle(fontSize: 28),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (c.error.isNotEmpty)
                MaterialBanner(
                  content: Text(c.error),
                  actions: [
                    TextButton(
                      onPressed: () {
                        c.error = '';
                        c.refresh();
                      },
                      child: const Text('关闭'),
                    ),
                  ],
                ),
              if (s.notice.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      s.notice,
                      style: const TextStyle(fontSize: 12, color: muted),
                    ),
                  ),
                ),
              if (!c.ready) const LinearProgressIndicator(),
              Expanded(
                child: ListView.builder(
                  key: ValueKey('messages_${s.id}'),
                  controller: _scroll,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: s.messages.length,
                  itemBuilder: (_, i) => MessageTile(
                    key: ValueKey(s.messages[i].id),
                    controller: c,
                    session: s,
                    message: s.messages[i],
                    onPhoto: _viewPhoto,
                    onError: _toast,
                  ),
                ),
              ),
              if (s.photos.isNotEmpty)
                SizedBox(
                  height: 106,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      for (final photo in s.photos)
                        Row(
                          children: [
                            PhotoTile(
                              controller: c,
                              photo: photo,
                              onTap: () => _viewPhoto(photo),
                            ),
                            IconButton(
                              tooltip: '移除待发照片',
                              onPressed: s.busy
                                  ? null
                                  : () => c.removePhoto(s, photo),
                              style: IconButton.styleFrom(
                                backgroundColor: Colors.transparent,
                              ),
                              icon: const Icon(Icons.close, size: 18),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              if (c.voiceStatus.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Text(
                    c.voiceStatus,
                    style: TextStyle(
                      color: c.cancelArmed && c.recording ? Colors.red : green,
                      fontSize: 12,
                    ),
                  ),
                ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  SizedBox(
                    width: 58,
                    child: TextButton(
                      onPressed: () {
                        FocusScope.of(context).unfocus();
                        c.toggleMode();
                      },
                      child: Text(c.config.voiceMode ? '键盘' : '语音'),
                    ),
                  ),
                  if (c.config.voiceMode)
                    Expanded(child: _hold(s))
                  else ...[
                    Expanded(
                      child: TextField(
                        key: const Key('chat_input'),
                        controller: _input,
                        onChanged: c.draft,
                        minLines: 1,
                        maxLines: 4,
                        maxLength: 4000,
                        buildCounter: (
                          _, {
                          required currentLength,
                          required isFocused,
                          maxLength,
                        }) => null,
                        textInputAction: TextInputAction.newline,
                        decoration: InputDecoration(
                          hintText: s.photos.isEmpty ? '发消息、找物品…' : '问问照片中的物品…',
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    SizedBox(
                      width: 66,
                      child: FilledButton(
                        key: const Key('send'),
                        onPressed: c.ready && s.canSend
                            ? () => _safe(c.sendText)
                            : null,
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 13,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(s.busy ? '等待' : '发送'),
                      ),
                    ),
                  ],
                ],
              ),
              if (c.playing)
                TextButton.icon(
                  onPressed: c.stopVoice,
                  icon: const Icon(Icons.stop),
                  label: const Text('停止播放'),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _hold(Session s) => Semantics(
    label: '按住录音，松开发送，上划取消',
    child: Listener(
      key: const Key('hold_to_talk'),
      onPointerDown: (event) {
        if (!s.canSend) return;
        if (_pointer != null) {
          _pointer = null;
          unawaited(
            _safe(() => c.finishHold(event.position.dy, cancelled: true)),
          );
          return;
        }
        _pointer = event.pointer;
        unawaited(
          _safe(() async {
            try {
              await c.beginHold(event.position.dy);
            } catch (_) {
              c.stopVoice();
              rethrow;
            }
          }),
        );
      },
      onPointerMove: (event) {
        if (_pointer == event.pointer) c.moveHold(event.position.dy);
      },
      onPointerUp: (event) {
        if (_pointer == event.pointer) {
          _pointer = null;
          unawaited(_safe(() => c.finishHold(event.position.dy)));
        }
      },
      onPointerCancel: (event) {
        if (_pointer == event.pointer) {
          _pointer = null;
          unawaited(
            _safe(() => c.finishHold(event.position.dy, cancelled: true)),
          );
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        height: 52,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: c.recording
              ? (c.cancelArmed
                    ? const Color(0xfff6dbd7)
                    : const Color(0xffc9e5d5))
              : const Color(0xffe3ece5),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          c.recording
              ? (c.cancelArmed ? '松开 取消' : '松开 发送')
              : s.busy
              ? '正在处理…'
              : '按住 说话',
          style: TextStyle(
            color: s.canSend ? green : muted,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    ),
  );
  Future<void> _close(Session session) async {
    if (session.busy) {
      final yes = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('关闭正在处理的会话？'),
          content: const Text('关闭手机会话不能撤销服务端已收到的动作。涉及电器时，请先查询实际状态。历史仍可重新打开。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('保留'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('关闭会话'),
            ),
          ],
        ),
      );
      if (yes != true) return;
    }
    c.close(session.id);
  }

  void _settings() {
    c.stopVoice();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SettingsPage(
          controller: c,
          onIdentity: _identities,
          onHistory: _history,
          onDevices: _devices,
        ),
      ),
    );
  }

  Future<void> _identities() async {
    c.stopVoice();
    var future = c.people();
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('选择自己的身份'),
          content: SizedBox(
            width: 360,
            child: FutureBuilder<List<Person>>(
              future: future,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const SizedBox(
                    height: 100,
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (snapshot.hasError) {
                  return Text('暂时无法读取成员。${readable(snapshot.error!)}');
                }
                final people = snapshot.data ?? [];
                return SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        '选择本人，用于个人记忆与日程。切换身份会开启新会话，原会话保留。',
                        style: TextStyle(color: muted, fontSize: 13),
                      ),
                      const SizedBox(height: 8),
                      for (final person in people)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(person.label),
                          subtitle:
                              person.name.isEmpty ||
                                  people
                                          .where((p) => p.name == person.name)
                                          .length >
                                      1
                              ? Text('编号 ${person.id.substring(0, 8)}')
                              : null,
                          trailing:
                              c.active.identityKnown &&
                                  c.active.personId == person.id
                              ? const Icon(Icons.check, color: green)
                              : null,
                          onTap: () {
                            c.choosePerson(person);
                            Navigator.pop(context);
                          },
                        ),
                      if (people.isEmpty)
                        const Text('还没有已同步成员。请在家庭服务连接 GPS App 同步空间后刷新。'),
                      if (people.any((p) => p.name.isEmpty))
                        const Text(
                          '部分称谓尚未同步，请在 GPS App 同步人员资料后刷新。',
                          style: TextStyle(color: muted, fontSize: 12),
                        ),
                      TextButton(
                        onPressed: () {
                          c.choosePerson(null);
                          Navigator.pop(context);
                        },
                        child: const Text('不使用个人身份'),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => setState(() => future = c.people()),
              child: const Text('刷新成员'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('关闭'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _camera() async {
    final photo = await c.camera();
    if (photo != null && mounted) await _preview(photo);
  }

  Future<void> _preview(Json photo) async {
    final decision = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('照片预览'),
        content: SizedBox(
          width: 360,
          height: 320,
          child: PhotoTile(controller: c, photo: photo, large: true),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'retake'),
            child: const Text('重拍'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'cancel'),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, 'add'),
            child: const Text('添加照片'),
          ),
        ],
      ),
    );
    if (decision == 'add') {
      await c.attachPhoto(photo);
    } else {
      await c.discardPhoto(photo);
      if (decision == 'retake' && mounted) await _camera();
    }
  }

  Future<void> _viewPhoto(Json photo) async {
    c.stopVoice();
    final add = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('查看照片'),
        content: SizedBox(
          width: 380,
          height: 360,
          child: InteractiveViewer(
            child: PhotoTile(controller: c, photo: photo, large: true),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('添加到当前会话'),
          ),
        ],
      ),
    );
    if (add == true) {
      await _safe(() => c.attachPhoto(photo, owner: c.active.id));
    }
  }

  Future<void> _history() async {
    c.stopVoice();
    var offset = 0;
    var future = c.request('/v1/conversations?limit=50&offset=0');
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('历史会话'),
          content: SizedBox(
            width: 360,
            child: FutureBuilder<Object?>(
              future: future,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const SizedBox(
                    height: 100,
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (snapshot.hasError) return Text(readable(snapshot.error!));
                List<Json> list;
                try {
                  list = rows(snapshot.data, [
                    'conversations',
                    'items',
                    'results',
                  ]);
                } catch (e) {
                  return Text(readable(e));
                }
                return SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final row in list)
                        ListTile(
                          title: Text(
                            text(row['title']).isEmpty
                                ? '历史会话'
                                : text(row['title']),
                          ),
                          onTap: () {
                            final id = text(
                              row['conversation_id'] ?? row['id'],
                            );
                            if (id.isEmpty) return;
                            c.book.open(
                              id,
                              text(row['title']).isEmpty
                                  ? '历史会话'
                                  : text(row['title']),
                            );
                            c.save();
                            c.refresh();
                            Navigator.pop(context);
                            unawaited(c.loadHistory(c.active));
                          },
                        ),
                      if (list.isEmpty) const Text('暂无更多历史会话'),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          if (offset > 0)
                            TextButton(
                              onPressed: () => setState(() {
                                offset -= 50;
                                future = c.request(
                                  '/v1/conversations?limit=50&offset=$offset',
                                );
                              }),
                              child: const Text('上一页'),
                            ),
                          if (list.length == 50)
                            TextButton(
                              onPressed: () => setState(() {
                                offset += 50;
                                future = c.request(
                                  '/v1/conversations?limit=50&offset=$offset',
                                );
                              }),
                              child: const Text('下一页'),
                            ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          actions: [
            if (c.active.serverId.isNotEmpty)
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  unawaited(c.loadHistory(c.active));
                },
                child: const Text('同步当前会话'),
              ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('关闭'),
            ),
          ],
        ),
      ),
    );
  }

  void _devices() {
    Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => DevicesPage(controller: c)),
    );
  }
}

class PhotoTile extends StatefulWidget {
  final ChatController controller;
  final Json photo;
  final bool large;
  final VoidCallback? onTap;
  const PhotoTile({
    super.key,
    required this.controller,
    required this.photo,
    this.large = false,
    this.onTap,
  });
  @override
  State<PhotoTile> createState() => _PhotoTileState();
}

class _PhotoTileState extends State<PhotoTile> {
  late Future<Object?> future;
  @override
  void initState() {
    super.initState();
    future = widget.controller.host.call('photoPath', widget.photo);
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: widget.onTap,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: widget.large ? double.infinity : 88,
        height: widget.large ? double.infinity : 88,
        child: FutureBuilder<Object?>(
          future: future,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return InkWell(
                onTap: () => setState(
                  () => future = widget.controller.host.call(
                    'photoPath',
                    widget.photo,
                  ),
                ),
                child: const Center(
                  child: Text(
                    '加载失败\n点按重试',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: muted),
                  ),
                ),
              );
            }
            if (snapshot.data is String) {
              return Image.file(
                File(snapshot.data as String),
                fit: widget.large ? BoxFit.contain : BoxFit.cover,
                cacheWidth: widget.large ? 1280 : 256,
                errorBuilder: (_, error, stack) =>
                    const Center(child: Text('照片不可用')),
              );
            }
            return const Center(
              child: CircularProgressIndicator(strokeWidth: 2),
            );
          },
        ),
      ),
    ),
  );
}

String describe(Json row) {
  final parts = <String>[];
  for (final key in [
    'name',
    'friendly_name',
    'label',
    'state',
    'quantity',
    'unit',
    'location',
    'area',
    'expires_at',
    'expiry_date',
    'description',
  ]) {
    final value = row[key];
    if (value is String && value.isNotEmpty || value is num) {
      parts.add('$value');
    }
  }
  return parts.isEmpty ? '查看回答中的相关信息' : parts.join(' · ');
}

class MessageTile extends StatefulWidget {
  final ChatController controller;
  final Session session;
  final Message message;
  final Future<void> Function(Json) onPhoto;
  final void Function(String) onError;
  const MessageTile({
    super.key,
    required this.controller,
    required this.session,
    required this.message,
    required this.onPhoto,
    required this.onError,
  });
  @override
  State<MessageTile> createState() => _MessageTileState();
}

class _MessageTileState extends State<MessageTile> {
  bool expanded = false;
  @override
  Widget build(BuildContext context) {
    final m = widget.message,
        user = m.role == 'user',
        voice = m.kind == 'voice';
    final duration = m.data['duration_ms'] is num
        ? ((m.data['duration_ms'] as num) / 1000).ceil()
        : 0;
    return Padding(
      padding: EdgeInsets.fromLTRB(user ? 28 : 0, 6, user ? 0 : 20, 6),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: user ? const Color(0xffdfefe7) : Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              user ? '我' : 'Veexor',
              style: const TextStyle(fontSize: 12, color: muted),
            ),
            const SizedBox(height: 5),
            if (m.images.isNotEmpty)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final photo in m.images)
                    PhotoTile(
                      controller: widget.controller,
                      photo: photo,
                      onTap: () => widget.onPhoto(photo),
                    ),
                ],
              ),
            if (voice) ...[
              TextButton.icon(
                onPressed: () => widget.controller.play(widget.session, m),
                icon: const Icon(Icons.play_arrow),
                label: Text(
                  duration > 0
                      ? '$duration 秒'
                      : user
                      ? '语音消息'
                      : '语音回复',
                ),
              ),
              if (m.content.isNotEmpty)
                TextButton(
                  onPressed: () => setState(() => expanded = !expanded),
                  child: Text(expanded ? '收起文字' : '查看文字'),
                ),
              if (expanded && m.content.isNotEmpty)
                SelectableText(
                  m.content,
                  style: const TextStyle(fontSize: 16, color: ink),
                ),
              if (text(m.data['voice_status']).isNotEmpty)
                Text(
                  text(m.data['voice_status']),
                  style: const TextStyle(fontSize: 12, color: muted),
                ),
              if (m.data.containsKey('speech_expected'))
                TextButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('语音差异'),
                      content: SingleChildScrollView(
                        child: SelectableText(
                          '应朗读：\n${text(m.data['speech_expected'])}\n\n语音返回：\n${text(m.data['speech_actual'])}',
                        ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('关闭'),
                        ),
                      ],
                    ),
                  ),
                  child: const Text('查看语音差异'),
                ),
            ] else
              SelectableText(
                m.content,
                style: const TextStyle(fontSize: 16, height: 1.5, color: ink),
              ),
            for (final field in ['items', 'devices'])
              if (objects(m.data[field]).isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  field == 'items' ? '相关物品' : '相关电器',
                  style: const TextStyle(color: green, fontSize: 12),
                ),
                for (final row in objects(m.data[field]))
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      describe(row),
                      style: const TextStyle(fontSize: 13, color: ink),
                    ),
                  ),
              ],
            for (final task in objects(m.data['scene_tasks'])) _task(task),
          ],
        ),
      ),
    );
  }

  Widget _task(Json task) {
    final state = text(task['status'] ?? task['state']),
        id = text(task['task_id'] ?? task['id']);
    final status =
        const {
          'queued': '排队中',
          'running': '处理中',
          'completed': '已完成',
          'failed': '失败',
        }[state] ??
        state;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Text(
          '${text(task['name'] ?? task['type']).isEmpty ? '场景任务' : text(task['name'] ?? task['type'])} · $status',
          style: const TextStyle(fontSize: 13, color: ink),
        ),
        if (text(task['message'] ?? task['detail']).isNotEmpty)
          Text(
            text(task['message'] ?? task['detail']),
            style: const TextStyle(fontSize: 12, color: muted),
          ),
        if (id.isNotEmpty && id.length <= 128)
          TextButton(
            onPressed: () async {
              try {
                final result = object(
                  await widget.controller.request(
                    '/v1/twin/tasks/${Uri.encodeComponent(id)}',
                  ),
                );
                if (!mounted) return;
                final updated = object(result['task']).isEmpty
                    ? result
                    : object(result['task']);
                final tasks = objects(widget.message.data['scene_tasks']);
                final index = tasks.indexWhere(
                  (row) => text(row['task_id'] ?? row['id']) == id,
                );
                if (index >= 0) {
                  tasks[index] = updated;
                  widget.message.data['scene_tasks'] = tasks;
                  widget.controller.save();
                  widget.controller.refresh();
                }
              } catch (e) {
                widget.onError(readable(e));
              }
            },
            child: const Text('更新任务状态'),
          ),
      ],
    );
  }
}
