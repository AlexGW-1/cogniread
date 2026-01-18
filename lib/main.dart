import 'package:cogniread/src/app.dart';
import 'package:cogniread/src/core/utils/logger.dart';
import 'package:flutter/material.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Log.init();
  Log.installErrorHandlers();
  runApp(const CogniReadApp());
}
