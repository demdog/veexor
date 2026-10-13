import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'host.dart';
import 'http_policy.dart';
import 'models.dart';
import 'omni.dart';

Uint8List wavBytes(Uint8List pcm, int sampleRate) {
  final bytes = Uint8List(44 + pcm.length),
      header = ByteData.sublistView(bytes);
  void ascii(int start, String value) {
    bytes.setRange(start, start + value.length, asciiEncode(value));
  }

  ascii(0, 'RIFF');
  header.setUint32(4, 36 + pcm.length, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  header.setUint32(16, 16, Endian.little);
  header.setUint16(20, 1, Endian.little);
  header.setUint16(22, 1, Endian.little);
  header.setUint32(24, sampleRate, Endian.little);
  header.setUint32(28, sampleRate * 2, Endian.little);
  header.setUint16(32, 2, Endian.little);
  header.setUint16(34, 16, Endian.little);
  ascii(36, 'data');
  header.setUint32(40, pcm.length, Endian.little);
  bytes.setRange(44, bytes.length, pcm);
  return bytes;
}

List<int> asciiEncode(String value) => ascii.encode(value);

class MobileHost implements Host {
  static const _legacy = MethodChannel('cn.home.chat/legacy');
  final _secure = const FlutterSecureStorage();
  final _recorder = AudioRecorder(),
      _player = AudioPlayer(),
      _picker = ImagePicker();
  final Map<String, CancelToken> _requests = {};
  final Map<String, Omni> _voices = {};
  final _config = AppConfig();
  late Directory _root;
  late SharedPreferences _prefs;
  void Function(Json)? _listener;
  Future<void> _writes = Future.value();
  Future<bool>? _starting;
  int _recordEpoch = 0;
  bool _recording = false;
  String _playId = '';
  MobileHost() {
    _player.onPlayerComplete.listen((_) {
      _emit({'type': 'playback_done', 'id': _playId});
      _playId = '';
    });
    _recorder.onStateChanged().listen((state) {
      if (state == RecordState.pause && _recording) {
        _emit({'type': 'recording_interrupted'});
      }
    });
  }
  void _emit(Json value) => _listener?.call(value);
  @override
  void onEvent(void Function(Json) listener) {
    _listener = listener;
  }

  String get _namespace => sha256
      .convert(utf8.encode('${_config.base}\u0000${_config.token}'))
      .toString()
      .substring(0, 32);
  File _photo(String name) {
    if (!validPhoto(name)) throw const FormatException('照片文件无效');
    return File('${_root.path}/photos/$name');
  }

  File _audio(String name) {
    if (!RegExp(r'^(input_|reply_)[A-Za-z0-9_.-]+\.pcm$').hasMatch(name)) {
      throw const FormatException('语音文件无效');
    }
    return File('${_root.path}/voice/$name');
  }

  @override
  Future<Object?> call(String method, [Json arguments = const {}]) async {
    switch (method) {
      case 'bootstrap':
        return _bootstrap();
      case 'saveState':
        final snapshot = text(arguments['state']);
        _writes = _writes.catchError((_) {}).then((_) async {
          final temporary = File('${_root.path}/sessions.tmp');
          await temporary.writeAsString(snapshot, flush: true);
          await temporary.rename('${_root.path}/sessions.json');
          await _prefs.setBool('voice_mode', arguments['voice_mode'] == true);
        });
        await _writes;
        return null;
      case 'saveConfig':
        await _secure.write(key: 'home_token', value: text(arguments['token']));
        await _secure.write(
          key: 'aliyun_key',
          value: text(arguments['aliyun']),
        );
        await _prefs.setString('base', text(arguments['base']));
        await _prefs.setString('workspace', text(arguments['workspace']));
        _config.load({...arguments, 'files_dir': _root.path});
        return null;
      case 'request':
        return _request(arguments);
      case 'upload':
        return _request({
          ...arguments,
          'path': '/v1/images',
          'method': 'POST',
          'upload': true,
        });
      case 'photoPath':
        return _photoPath(arguments);
      case 'camera':
        await _prefs.setString('pending_photo_owner', text(arguments['owner']));
        await _prefs.setString('pending_photo_profile', _namespace);
        final photo = await _picker.pickImage(
          source: ImageSource.camera,
          maxWidth: 1600,
          maxHeight: 1600,
          imageQuality: 85,
          requestFullMetadata: false,
        );
        if (photo == null) {
          await _clearCamera();
          return null;
        }
        return _preparePhoto(photo.path);
      case 'recoverPhoto':
        final saved = _prefs.getString('recovered_photo');
        if (saved != null) return object(jsonDecode(saved));
        if (!Platform.isAndroid) return null;
        final lost = await _picker.retrieveLostData();
        if (lost.exception != null) throw lost.exception!;
        if (lost.files?.isNotEmpty == true) {
          return _preparePhoto(lost.files!.first.path);
        }
        await _clearCamera();
        return null;
      case 'photoHandled':
        await _clearCamera();
        return null;
      case 'deletePhoto':
        final file = _photo(text(arguments['image_file']));
        if (await file.exists()) await file.delete();
        return null;
      case 'recordStart':
        _starting = _startRecord();
        return _starting;
      case 'recordCancel':
        _recordEpoch++;
        await _starting?.catchError((_) => false);
        _recording = false;
        await _recorder.cancel();
        return null;
      case 'recordStop':
        if (await _starting != true) return null;
        _recording = false;
        final path = await _recorder.stop();
        if (path == null) throw const FormatException('录音未能保存');
        final file = File(path), length = await File(path).length();
        if (length < 9600 || length > 1000000 || length.isOdd) {
          await file.delete();
          throw const FormatException('说话时间过短或录音格式无效');
        }
        return {
          'audio_file': path.split(Platform.pathSeparator).last,
          'sample_rate': 16000,
          'duration_ms': length * 1000 ~/ 32000,
        };
      case 'transcribe':
        final id = text(arguments['id']);
        await _ensureWifi();
        final voice = Omni(
          _config.aliyunKey,
          _config.workspace,
          (state) => _emit({'type': 'voice_state', 'id': id, 'state': state}),
        );
        _voices[id] = voice;
        try {
          return await voice.transcribe(_audio(text(arguments['audio_file'])));
        } finally {
          _voices.remove(id);
          voice.close();
        }
      case 'synthesize':
        final id = text(arguments['id']);
        await _ensureWifi();
        final output = _audio('reply_${newId()}.pcm');
        final voice = Omni(
          _config.aliyunKey,
          _config.workspace,
          (state) => _emit({'type': 'voice_state', 'id': id, 'state': state}),
        );
        _voices[id] = voice;
        try {
          await voice.synthesize(text(arguments['text']), output);
          return {
            'audio_file': output.uri.pathSegments.last,
            'sample_rate': 24000,
            'duration_ms': await output.length() * 1000 ~/ 48000,
          };
        } finally {
          _voices.remove(id);
          voice.close();
        }
      case 'play':
        final file = _audio(text(arguments['audio_file'])),
            rate = arguments['sample_rate'] == 16000 ? 16000 : 24000;
        final pcm = await file.readAsBytes();
        if (pcm.isEmpty || pcm.length.isOdd) {
          throw const FormatException('原始录音不可用');
        }
        final wav = File('${file.path}.wav');
        await wav.writeAsBytes(wavBytes(pcm, rate), flush: true);
        await _player.stop();
        _playId = text(arguments['id']);
        await _player.setAudioContext(
          AudioContext(
            android: const AudioContextAndroid(
              contentType: AndroidContentType.speech,
              audioFocus: AndroidAudioFocus.gainTransient,
            ),
            iOS: AudioContextIOS(category: AVAudioSessionCategory.playback),
          ),
        );
        await _player.play(DeviceFileSource(wav.path));
        return null;
      case 'stopPlayback':
        await _player.stop();
        _playId = '';
        return null;
      case 'cancel':
        final prefix = text(arguments['prefix']);
        for (final entry in _requests.entries.toList()) {
          if (entry.key.startsWith(prefix)) {
            entry.value.cancel('请求已停止，服务端结果需另行查询');
          }
        }
        for (final entry in _voices.entries.toList()) {
          if (entry.key.startsWith(prefix)) entry.value.close();
        }
        return null;
      case 'cleanup':
        await _cleanup(text(arguments['state']));
        return null;
      case 'dispose':
        for (final token in _requests.values) {
          token.cancel();
        }
        for (final voice in _voices.values) {
          voice.close();
        }
        await _recorder.dispose();
        await _player.dispose();
        return null;
      default:
        throw UnsupportedError(method);
    }
  }

  Future<Json> _bootstrap() async {
    _prefs = await SharedPreferences.getInstance();
    _root = Directory(
      '${(await getApplicationSupportDirectory()).path}/veexor',
    );
    await Directory('${_root.path}/voice').create(recursive: true);
    await Directory('${_root.path}/photos').create(recursive: true);
    final stateFile = File('${_root.path}/sessions.json');
    if (Platform.isAndroid &&
        !await stateFile.exists() &&
        _prefs.getBool('legacy_imported') != true) {
      final legacy = object(await _legacy.invokeMethod<Object?>('readLegacy'));
      if (text(legacy['sessions']).isNotEmpty) {
        SessionBook.restore(text(legacy['sessions']));
      }
      for (final directory in ['voice', 'photos']) {
        final source = Directory('${text(legacy['files_dir'])}/$directory');
        if (text(legacy['files_dir']).isNotEmpty && await source.exists()) {
          await for (final file in source.list(followLinks: false)) {
            if (file is File) {
              final name = file.uri.pathSegments.last;
              if (RegExp(r'^[A-Za-z0-9_.-]+$').hasMatch(name)) {
                await file.copy('${_root.path}/$directory/$name');
              }
            }
          }
        }
      }
      if (text(legacy['token']).isNotEmpty) {
        await _secure.write(key: 'home_token', value: text(legacy['token']));
      }
      if (text(legacy['aliyun']).isNotEmpty) {
        await _secure.write(key: 'aliyun_key', value: text(legacy['aliyun']));
      }
      if (text(legacy['base']).isNotEmpty) {
        await _prefs.setString('base', text(legacy['base']));
      }
      await _prefs.setString('workspace', text(legacy['workspace']));
      await _prefs.setBool('voice_mode', legacy['voice_mode'] == true);
      if (text(legacy['sessions']).isNotEmpty) {
        await stateFile.writeAsString(text(legacy['sessions']), flush: true);
      }
      await _prefs.setBool('legacy_imported', true);
    }
    final result = <String, dynamic>{
      'base': _prefs.getString('base') ?? 'http://192.168.31.68:8001',
      'workspace': _prefs.getString('workspace') ?? '',
      'token': await _secure.read(key: 'home_token') ?? '',
      'aliyun': await _secure.read(key: 'aliyun_key') ?? '',
      'voice_mode': _prefs.getBool('voice_mode') ?? false,
      'files_dir': _root.path,
      'sessions': await stateFile.exists()
          ? await stateFile.readAsString()
          : '',
    };
    _config.load(result);
    return result;
  }

  Future<void> _ensureWifi() async {
    if (!(await Connectivity().checkConnectivity()).contains(
      ConnectivityResult.wifi,
    )) {
      throw const HttpException('请连接家中的 Wi-Fi 后再使用');
    }
    if (Platform.isAndroid &&
        await _legacy.invokeMethod<bool>('bindWifi') != true) {
      throw const HttpException('无法使用家庭 Wi-Fi，请重新连接');
    }
  }

  Future<Object?> _request(Json args) async {
    final base = _config.base,
        token = _config.token,
        id = text(args['id']),
        path = text(args['path']);
    if (token.isEmpty) throw const FormatException('请先在设置中填写家庭访问令牌');
    if (!path.startsWith('/') ||
        path.startsWith('//') ||
        path.contains('://')) {
      throw const FormatException('接口地址无效');
    }
    final cancel = CancelToken();
    _requests[id] = cancel;
    try {
      await _ensureWifi();
      if (cancel.isCancelled) throw const HttpException('请求已停止，服务端结果需另行查询');
      final dio = Dio(
        BaseOptions(
          baseUrl: base,
          headers: {
            'Authorization': 'Bearer $token',
            'Accept': 'application/json',
          },
          connectTimeout: homeConnectTimeout,
          receiveTimeout: homeAnswerTimeout,
          sendTimeout: homeSendTimeout,
          followRedirects: false,
        ),
      );
      try {
        Object? body = args['body'];
        if (args['upload'] == true) {
          final file = _photo(text(args['image_file'])),
              length = await _photo(text(args['image_file'])).length();
          if (length == 0 || length > 8 * 1024 * 1024) {
            throw const FormatException('照片无效或超过 8 MiB');
          }
          body = FormData.fromMap({
            'file': await MultipartFile.fromFile(
              file.path,
              filename: 'photo.jpg',
              contentType: DioMediaType('image', 'jpeg'),
            ),
          });
        }
        final response = await dio.request<List<int>>(
          path,
          data: body,
          options: Options(
            method: text(args['method']).isEmpty ? 'GET' : text(args['method']),
            responseType: ResponseType.bytes,
          ),
          cancelToken: cancel,
        );
        final bytes = response.data ?? [];
        if (bytes.length > 8 * 1024 * 1024) {
          throw const FormatException('服务返回内容过大');
        }
        if (args['download'] == true) return Uint8List.fromList(bytes);
        if (bytes.length > 4 * 1024 * 1024) {
          throw const FormatException('返回内容过大');
        }
        return jsonDecode(utf8.decode(bytes));
      } on DioException catch (error) {
        throw householdFailure(error);
      } finally {
        dio.close(force: true);
      }
    } finally {
      if (_requests[id] == cancel) _requests.remove(id);
    }
  }

  Future<String> _photoPath(Json photo) async {
    final name = text(photo['image_file']), id = text(photo['image_id']);
    if (validPhoto(name) && await _photo(name).exists()) {
      return _photo(name).path;
    }
    if (!validImage(id)) throw const FormatException('原始照片已不可用');
    final file = _photo('remote_${_namespace}_$id.img');
    if (await file.exists()) return file.path;
    final bytes = await _request({
      'id': 'photo_${newId()}',
      'path': '/v1/images/$id',
      'download': true,
    });
    if (bytes is! Uint8List || bytes.isEmpty) {
      throw const FormatException('照片内容为空');
    }
    final temp = File('${file.path}.tmp');
    await temp.writeAsBytes(bytes, flush: true);
    await temp.rename(file.path);
    return file.path;
  }

  Future<Json> _preparePhoto(String path) async {
    final owner = _prefs.getString('pending_photo_owner') ?? '',
        profile = _prefs.getString('pending_photo_profile') ?? '';
    if (owner.isEmpty || profile != _namespace) {
      await _clearCamera();
      throw const FormatException('原拍照会话已改变，请重新拍照');
    }
    final file = _photo('photo_${newId()}.jpg');
    final result = await FlutterImageCompress.compressAndGetFile(
      path,
      file.path,
      minWidth: 1600,
      minHeight: 1600,
      quality: 85,
      format: CompressFormat.jpeg,
      autoCorrectionAngle: true,
      keepExif: false,
    );
    if (result == null ||
        await file.length() == 0 ||
        await file.length() > 8 * 1024 * 1024) {
      if (await file.exists()) await file.delete();
      throw const FormatException('照片处理失败，请重新拍摄');
    }
    final photo = {
      'owner': owner,
      'profile': profile,
      'image_file': file.uri.pathSegments.last,
      'mime_type': 'image/jpeg',
    };
    await _prefs.setString('recovered_photo', jsonEncode(photo));
    return photo;
  }

  Future<void> _clearCamera() async {
    await _prefs.remove('pending_photo_owner');
    await _prefs.remove('pending_photo_profile');
    await _prefs.remove('recovered_photo');
  }

  Future<bool> _startRecord() async {
    final epoch = ++_recordEpoch;
    if (!await _recorder.hasPermission(request: false)) {
      await _recorder.hasPermission();
      return false;
    }
    if (epoch != _recordEpoch) return false;
    await _player.stop();
    final file = _audio('input_${newId()}.pcm');
    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
        audioInterruption: AudioInterruptionMode.pause,
      ),
      path: file.path,
    );
    if (epoch != _recordEpoch) {
      await _recorder.cancel();
      return false;
    }
    _recording = true;
    return true;
  }

  Future<void> _cleanup(String state) async {
    final root = object(jsonDecode(state)),
        keepPhotos = <String>{},
        keepVoice = <String>{};
    void photo(Json p) {
      if (validPhoto(text(p['image_file']))) {
        keepPhotos.add(text(p['image_file']));
      }
      if (validImage(text(p['image_id']))) {
        keepPhotos.add('remote_${_namespace}_${p['image_id']}.img');
      }
    }

    for (final s in objects(root['sessions'])) {
      for (final p in objects(s['photos'])) {
        photo(p);
      }
      for (final m in objects(s['messages'])) {
        for (final p in objects(m['content_parts'])) {
          if (p['type'] == 'image') photo(p);
        }
        final audio = text(m['audio_file']);
        keepVoice.add(audio);
        keepVoice.add('$audio.wav');
      }
    }
    final pending = _prefs.getString('recovered_photo');
    if (pending != null) photo(object(jsonDecode(pending)));
    for (final directory in ['photos', 'voice']) {
      final keep = directory == 'photos' ? keepPhotos : keepVoice;
      await for (final file in Directory(
        '${_root.path}/$directory',
      ).list(followLinks: false)) {
        if (file is File && !keep.contains(file.uri.pathSegments.last)) {
          await file.delete();
        }
      }
    }
  }
}
