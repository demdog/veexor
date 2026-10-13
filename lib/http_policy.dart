import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';

const homeConnectTimeout = Duration(seconds: 8);
const homeAnswerTimeout = Duration(seconds: 390);
const homeSendTimeout = Duration(seconds: 30);

Exception householdFailure(DioException error) {
  if (CancelToken.isCancel(error)) {
    return const HttpException('请求已停止，服务端结果需另行查询');
  }
  if ([401, 403].contains(error.response?.statusCode)) {
    return const HttpException('访问令牌无效或无权限，请检查设置');
  }
  if (error.type == DioExceptionType.receiveTimeout) {
    return TimeoutException('等待回答超时，结果未知。可同步历史；涉及电器时先查询状态。');
  }
  if (error.type == DioExceptionType.connectionTimeout) {
    return TimeoutException('连接服务超时，请检查家庭 Wi-Fi 和服务地址');
  }
  if (error.type == DioExceptionType.sendTimeout) {
    return TimeoutException('发送请求超时，结果未知，请先同步历史确认');
  }
  if (error.response?.statusCode != null) {
    return HttpException('服务返回 HTTP ${error.response!.statusCode}，未自动重试');
  }
  return const HttpException('网络连接失败或中断，请检查家庭 Wi-Fi 和服务地址');
}
