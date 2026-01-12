import 'package:cogniread/src/app.dart';
import 'package:cogniread/src/features/sync/file_sync/mock_sync_adapter.dart';
import 'package:flutter/material.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(CogniReadApp(syncAdapter: MockSyncAdapter()));
}
