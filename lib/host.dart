import 'models.dart';

abstract class Host {
  Future<Object?> call(String method, [Json arguments = const {}]);
  void onEvent(void Function(Json) listener);
}

class AppConfig {
  String base = 'http://192.168.31.68:8001',
      token = '',
      workspace = '',
      aliyunKey = '',
      filesDir = '';
  bool voiceMode = false;
  bool get voiceReady =>
      token.isNotEmpty && workspace.isNotEmpty && aliyunKey.isNotEmpty;
  Json toJson() => {
    'base': base,
    'token': token,
    'workspace': workspace,
    'aliyun': aliyunKey,
    'voice_mode': voiceMode,
  };
  void load(Json value) {
    if (text(value['base']).isNotEmpty) base = text(value['base']);
    token = text(value['token']);
    workspace = text(value['workspace']);
    aliyunKey = text(value['aliyun']);
    filesDir = text(value['files_dir']);
    voiceMode = value['voice_mode'] == true;
  }

  static String validateBase(String value) {
    value = value.trim().replaceFirst(RegExp(r'/+$'), '');
    final uri = Uri.tryParse(value);
    if (uri == null ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        uri.path.isNotEmpty) {
      throw const FormatException('请填写家庭服务根地址，例如 http://192.168.31.68:8001');
    }
    return value;
  }
}
