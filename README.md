# Veexor · Flutter

Veexor 2.0.0（Android versionCode 14）。家庭 Wi-Fi 下的手机聊天应用，连接现有家庭服务，查询物品、操作电器。保留竖屏聊天、多会话、称谓选择、拍照发送和微信式语音交互。原 Java Android 工程保留在相邻的 HomeChat 目录。

## 跨平台实现

聊天界面、会话状态、身份绑定、HTTP 接口、阿里 Omni WebSocket、转写与朗读校验均为共享 Dart 代码。Android 和 iOS 使用同一份实现。

| 能力 | 依赖 | Android / iOS |
| --- | --- | --- |
| 录音 | record | 单声道 16 kHz PCM；权限请求、系统中断处理 |
| 播放 | audioplayers | 16/24 kHz PCM 转 WAV 后播放 |
| 拍照 | image_picker | 系统相机；Android 进程回收后恢复拍照结果 |
| 图片处理 | flutter_image_compress | JPEG、方向校正、移除 EXIF |
| 私密配置 | flutter_secure_storage | Android Keystore / iOS Keychain |
| 本地文件与偏好 | path_provider、shared_preferences | 私有应用目录及本地偏好 |
| 网络状态 / 请求 | connectivity_plus、dio | 检查 Wi-Fi、HTTP/图片上传下载 |
| STT / TTS | Dart dart:io WebSocket | 共用阿里 Omni 协议及校验逻辑 |

`android/.../MainActivity.java` 只负责导入旧版设置和绑定 Android Wi-Fi 路由；旧 TokenStore 只用于读取旧版加密凭据。业务功能没有依赖原 Android 界面或语音实现。iOS 无需重写这些业务。

支持 Android 8.0+（API 26）与 iOS 15.0+。依赖版本和摘要固定在 pubspec.lock。开发基线为 Flutter 3.47.6 / Dart 3.13.5、JDK 17、Android SDK 36。

## 使用方式

1. 手机连接家庭 Wi-Fi，打开设置。默认服务地址是 `http://192.168.31.68:8001`，填写家庭服务访问令牌。
2. 配置北京地域百炼业务空间 ID 和百炼 API Key 后，可使用语音。家庭 Wi-Fi 还需能够访问阿里云。
3. 点击“身份”按服务端 `name` 称谓选择人员；实际请求仍传 UUID。切换已有聊天的身份会新建会话，防止串用上下文。
4. 列表末尾的 `+` 创建新会话，`×` 关闭本机标签。每个会话保留自己的草稿、照片和历史；服务端历史可从设置重新打开。
5. 文字发送得到文字回答。语音按住录音、松开发送、上划 64 逻辑像素取消；少于 300 ms 不发送，30 秒自动结束。系统中断、切后台或多指操作取消未提交录音。
6. 相机拍照后先预览，可重拍、取消或添加到当前会话；点击发送后才上传照片。单次最多 4 张，不将本地文件路径发送到接口。

语音转写只接受输入音频的最终转写，不将 Omni 生成的回答当作用户输入。语音回复只朗读家庭接口已经返回的正文；校验音频对应的转录后播放，数量、否定、日期、单位和括号内容必须保留。允许等价数字读法；不一致只重试该段朗读一次。失败时保留文字及差异供查看，绝不自动重发家庭操作。HTTP 请求结果不确定时，同样不自动重试，应先同步历史或查询电器状态。

## Android 升级

包名继续使用 `cn.home.chat`。新包必须使用与已安装旧版相同的证书签名，才能覆盖安装并保留应用数据；本次调试包延用本机 Android 调试证书。

首次启动导入旧版 Activity 偏好、访问令牌、百炼配置、会话、草稿、称谓缓存、照片及录音。密钥转存到安全存储。导入不删除原偏好和原媒体文件，导入成功后不重复覆盖 Flutter 数据。正在等待的旧请求恢复为“结果未知”，不会再次执行。请勿卸载旧应用或清除数据后再升级。

JSON 兼容迁移有自动测试；旧版真实设备覆盖导入、相机和音频插件仍需真机验收。保留旧版 APK 和 Java 工程作为迁移对照。Flutter 中的新聊天不会反向同步到旧版本地缓存。

## 构建与检查

```sh
flutter pub get
flutter analyze
flutter test
flutter build apk --debug --target-platform android-arm64
```

Android 构建使用工程内的 Gradle Wrapper。需要 Android SDK 36、Build Tools 和 NDK 28.2.13676358；首次构建会下载依赖。发布版请在 Android 工程配置正式签名；当前 release 配置继承模板的调试签名，不作为商店发行包。

国内网络可参考 Flutter 官方镜像设置：

```sh
export PUB_HOSTED_URL=https://pub.flutter-io.cn
export FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
```

Windows PowerShell 使用 `$env:PUB_HOSTED_URL='https://pub.flutter-io.cn'` 和 `$env:FLUTTER_STORAGE_BASE_URL='https://storage.flutter-io.cn'`。

## 在 Mac 上构建 iOS

1. 安装相同 Flutter 版本及匹配的 Xcode，完成 Xcode 首次启动设置。
2. 在工程目录执行 `flutter pub get`、`flutter build ios --debug --no-codesign`。工程使用 Flutter 模板的 Swift Package Manager 集成；Flutter 会生成插件集成文件，必要时按工具提示安装 CocoaPods。
3. 用 Xcode 打开 `ios/Runner.xcworkspace`，在 Runner 的 Signing & Capabilities 中选择自己的 Development Team，确认 Bundle ID 可用。若 `cn.home.chat` 已被其他团队占用，为 iOS 设置自己的 Bundle ID。
4. 连接 iPhone，选择设备并运行。首次请求允许“本地网络”“麦克风”“相机”。局域网明文 HTTP 已声明本地网络 ATS 例外，阿里 Omni 使用 WSS。
5. 验收称谓、多会话切换/关闭、键盘竖屏布局、拍照与预览、语音取消/中断/播放、阿里真实转写和朗读、家庭接口及后台恢复。

Windows 无法编译、签名或验证 iOS 原生插件。本工程已包含 iOS 项目、权限描述、竖屏配置、Keychain entitlement 和应用图标；Widget 测试的 iOS 平台模式不等同于 iPhone 真机验证。

Android 本地应用数据不会自动搬到另一部 iPhone；iPhone 填写同一服务配置后可重新打开服务端会话历史。仅在 Android 覆盖升级时自动导入原本机数据。

## 源码

- `lib/app.dart`、`settings_page.dart`：竖屏聊天、拍照预览、身份和设置。
- `lib/chat_controller.dart`、`models.dart`：独立会话、生命周期、请求和旧数据兼容。
- `lib/mobile_host.dart`：跨平台插件、文件、安全存储和 HTTP。
- `lib/omni.dart`、`speech.dart`：Omni 连接、音频传输、朗读及校验。
- `test/`：会话/身份/照片、并发和取消、语音数值校验、本地 WebSocket 模拟服务、Android/iOS 界面测试。
- `docs/household-api-1.9.0.json`：迁移所用的接口文档快照。
- `VALIDATION.md`：已完成的验证及需要手机/Mac 验收的范围。

接口沿用原 Android 工程已核对的家庭 API 1.9.0：`/v1/status`、`/v1/personal-sync/people`、`/v1/chat`、`/v1/conversations`、`/v1/images`、`/v1/home-assistant/entities`、`/v1/home-assistant/control` 及场景任务状态接口。服务端 API 有更新时须按最新文档再次核对。

参考：[Flutter 中国镜像](https://docs.flutter.dev/community/china)、[Flutter iOS 部署](https://docs.flutter.dev/deployment/ios)、[阿里 Omni 实时模型](https://help.aliyun.com/zh/model-studio/realtime)、[阿里服务端事件](https://help.aliyun.com/zh/model-studio/server-events)、[Apple 本地网络 ATS 配置](https://developer.apple.com/documentation/bundleresources/information-property-list/nsapptransportsecurity/nsallowslocalnetworking)。
