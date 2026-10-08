import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';
import 'chat_controller.dart';
import 'mobile_host.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(VeexorApp(controller: ChatController(MobileHost())));
}
