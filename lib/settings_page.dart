import 'package:flutter/material.dart';

import 'app.dart' show describe, muted;
import 'chat_controller.dart';
import 'models.dart';

class SettingsPage extends StatefulWidget {
  final ChatController controller;
  final VoidCallback onIdentity, onHistory, onDevices;
  const SettingsPage({
    super.key,
    required this.controller,
    required this.onIdentity,
    required this.onHistory,
    required this.onDevices,
  });
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final TextEditingController base, token, workspace, key;
  bool saving = false;
  String error = '';
  @override
  void initState() {
    super.initState();
    final c = widget.controller.config;
    base = TextEditingController(text: c.base);
    token = TextEditingController(text: c.token);
    workspace = TextEditingController(text: c.workspace);
    key = TextEditingController(text: c.aliyunKey);
  }

  @override
  void dispose() {
    base.dispose();
    token.dispose();
    workspace.dispose();
    key.dispose();
    super.dispose();
  }

  Widget _field(TextEditingController c, String label, {bool secret = false}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: c,
          obscureText: secret,
          autocorrect: !secret,
          enableSuggestions: !secret,
          decoration: InputDecoration(labelText: label),
        ),
      );
  void _open(VoidCallback action) {
    Navigator.pop(context);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      action();
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('连接与语音设置')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            '家庭服务',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          _field(base, '服务根地址'),
          _field(token, '手机 API 访问令牌', secret: true),
          const SizedBox(height: 12),
          const Text(
            '阿里 Omni 语音',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          _field(workspace, '北京地域业务空间 ID'),
          _field(key, '百炼 API Key', secret: true),
          const Text(
            '语音使用阿里云，需要家庭 Wi-Fi 能访问互联网。按住录音，松开发送，上划取消。文字发文字回，语音发语音回。',
            style: TextStyle(color: muted, fontSize: 13),
          ),
          if (error.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(error, style: const TextStyle(color: Colors.red)),
            ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: saving
                ? null
                : () async {
                    setState(() => saving = true);
                    try {
                      await widget.controller.saveConfig({
                        'base': base.text,
                        'token': token.text,
                        'workspace': workspace.text,
                        'aliyun': key.text,
                      });
                      if (context.mounted) Navigator.pop(context);
                    } catch (e) {
                      if (mounted) setState(() => error = readable(e));
                    } finally {
                      if (mounted) setState(() => saving = false);
                    }
                  },
            child: Text(saving ? '正在保存…' : '保存'),
          ),
          const SizedBox(height: 12),
          ListTile(
            leading: const Icon(Icons.person_outline),
            title: const Text('选择自己的身份'),
            onTap: () => _open(widget.onIdentity),
          ),
          ListTile(
            leading: const Icon(Icons.history),
            title: const Text('历史会话'),
            onTap: () => _open(widget.onHistory),
          ),
          ListTile(
            leading: const Icon(Icons.lightbulb_outline),
            title: const Text('电器查询'),
            onTap: () => _open(widget.onDevices),
          ),
          const Padding(
            padding: EdgeInsets.only(top: 16),
            child: Text(
              'Veexor 2.0.1\n关闭会话仅移除本机标签；服务端历史仍保留。',
              style: TextStyle(color: muted, fontSize: 12),
            ),
          ),
        ],
      ),
    ),
  );
}

class DevicesPage extends StatefulWidget {
  final ChatController controller;
  const DevicesPage({super.key, required this.controller});
  @override
  State<DevicesPage> createState() => _DevicesPageState();
}

class _DevicesPageState extends State<DevicesPage> {
  final query = TextEditingController(),
      area = TextEditingController(),
      domain = TextEditingController();
  List<Json> devices = [];
  String error = '';
  bool loading = false;
  @override
  void dispose() {
    query.dispose();
    area.dispose();
    domain.dispose();
    super.dispose();
  }

  Future<void> _query() async {
    setState(() {
      loading = true;
      error = '';
    });
    try {
      final result = await widget.controller.request(
        '/v1/home-assistant/entities?limit=200&query=${Uri.encodeQueryComponent(query.text)}&area=${Uri.encodeQueryComponent(area.text)}&domain=${Uri.encodeQueryComponent(domain.text)}',
      );
      final list = rows(result, ['entities', 'devices', 'items', 'results']);
      if (mounted) setState(() => devices = list);
    } catch (e) {
      if (mounted) setState(() => error = readable(e));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _control(Json device, String action) async {
    final value = TextEditingController();
    final send = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认设备操作'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${describe(device)}\n动作：$action'),
            const SizedBox(height: 12),
            TextField(
              controller: value,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              ),
              decoration: const InputDecoration(labelText: '可选数值：温度或 0–100'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('发送指令'),
          ),
        ],
      ),
    );
    final number = value.text.trim();
    value.dispose();
    if (send != true) return;
    try {
      final parsed = number.isEmpty ? null : double.tryParse(number);
      if (number.isNotEmpty && (parsed == null || !parsed.isFinite)) {
        throw const FormatException('请输入有效数值');
      }
      final result = object(
        await widget.controller.request(
          '/v1/home-assistant/control',
          method: 'POST',
          body: {
            'target': text(device['entity_id']),
            'action': action,
            'value': ?parsed,
          },
        ),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result['command_sent'] == true
                  ? '指令已发送，实际状态可能延迟；请查询确认'
                  : result['needs_clarification'] == true
                  ? '需要明确设备，请在聊天中补充'
                  : '已收到操作结果，请查询实际状态',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) setState(() => error = readable(e));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('家中电器')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          TextField(
            controller: query,
            decoration: const InputDecoration(labelText: '名称，例如客厅灯'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: area,
            decoration: const InputDecoration(labelText: '区域（可留空）'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: domain,
            decoration: const InputDecoration(
              labelText: '类型，例如 light / switch',
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: loading ? null : _query,
            child: Text(loading ? '查询中…' : '查询实时设备'),
          ),
          if (error.isNotEmpty)
            Text(error, style: const TextStyle(color: Colors.red)),
          for (final device in devices)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(describe(device)),
                    Wrap(
                      children: [
                        for (final raw
                            in device['actions'] is List
                                ? device['actions'] as List
                                : [])
                          if (text(device['entity_id']).isNotEmpty)
                            TextButton(
                              onPressed: () => _control(
                                device,
                                raw is Map
                                    ? text(raw['action'] ?? raw['name'])
                                    : text(raw),
                              ),
                              child: Text(
                                raw is Map
                                    ? text(raw['action'] ?? raw['name'])
                                    : text(raw),
                              ),
                            ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
