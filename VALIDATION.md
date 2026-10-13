# 验证记录

## 2026-10-13 · 2.0.1+15

- 核对在线 OpenAPI 1.10.5 的 POST `/v1/conversations`；没有调用真实聊天、库存或电器操作。
- `flutter analyze --no-pub`：No issues found；Android ARM64 2.0.1+15 构建成功，安装包签名验证通过。
- 自动测试 49 项通过：新增首轮会话编号在请求前落盘、超时后 GET 恢复完整回答、空历史保留待确认消息与身份、重启恢复且不重发、创建失败保留草稿、8/30/390 秒超时配置与分类提示。
- 本次改动需安装新版后验证手机网络中断及真实长耗时回答；当前未在手机上复现桌子建模的 96 秒请求。

日期：2026-10-08。版本：Veexor 2.0.0+14。

## 已完成

- Flutter 3.47.6 / Dart 3.13.5，Windows，JDK 17、Android SDK 36。
- `flutter analyze --no-pub`：No issues found。
- `flutter test --no-pub`：43 项通过。
- 本地中文字体和 Material 图标渲染预览：1 项通过，检查空白聊天、消息列表、文字输入和按住说话页面。字体仅用于本机测试，没有随应用打包。
- Android ARM64 调试包最终构建成功：`flutter build apk --debug --target-platform android-arm64 --no-pub`。
- 签名验证：与 Veexor 1.12 调试包的 SHA-256 证书摘要相同（fccd90fda2dd655ec825711fc4f30844d597918e63818fd499f02535af24c06a）。包名继续为 cn.home.chat，versionCode 从 13 升为 14。
- iOS 静态配置：iOS 15.0、相机/麦克风/照片/本地网络用途、局域网 ATS 配置、竖屏、Keychain entitlement、AppIcon、工程 Bundle ID。

## 自动测试覆盖

| 范围 | 项数 | 关键行为 |
| --- | ---: | --- |
| 模型与旧 JSON | 9 | 称谓 name/null、UUID、每会话身份、草稿/照片保留、旧数据格式、未知历史身份禁止发送、历史合并保留音频 |
| 控制器 | 13 | 并发回复归属、关闭后丢弃迟到回复、4 个请求限制、上传失败保留草稿、超时不重发、短按/上划/后台取消、语音输入/输出、换会话禁止自动播放、播放错误不循环生成 |
| 朗读校验 | 12 | 用户提供的括号回答、数量/单位/日期/时间/百分比、精确数值、否定及设备编号、分段和响应索引、拒绝无音频转录或工具调用 |
| 本地 WebSocket | 5 | 实际 PCM 分包与输入转写、TTS 单段一次重试、失败删除音频、工具响应拒绝、取消等待 |
| Widget | 4 | Android/iOS 平台模式竖屏与键盘、草稿切换、称谓选择、末尾加号、语音展开文字及差异 |

## 仍需真机验收

- Android：新版未覆盖安装到用户手机。旧数据导入、录音/播放/相机插件、Wi-Fi 路由及阿里云真实模型需要手机验收。本轮测试没有读取手机凭据、调用真实家庭控制或消耗用户百炼额度。
- iOS：当前没有 Mac/Xcode 或 iPhone 环境，尚未编译、签名、安装和验证原生插件。Widget 的 iOS 平台模式只验证 Dart 界面与逻辑。Mac 编译步骤见 README。
- 源码压缩包不包含 SDK、构建缓存、机器本地路径配置、签名私钥或用户配置。Android 源工程和旧 APK 保留。

构建提示中的 Kotlin 插件迁移告警来自 flutter_image_compress_common，目前锁定的 Flutter/依赖组合构建成功；未来升级 Flutter 时需要先核对该插件兼容性。
