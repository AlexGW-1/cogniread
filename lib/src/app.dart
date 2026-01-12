import 'package:cogniread/src/core/services/storage_service.dart';
import 'package:cogniread/src/features/library/presentation/library_screen.dart';
import 'package:cogniread/src/features/sync/file_sync/sync_adapter.dart';
import 'package:flutter/material.dart';

class CogniReadApp extends StatelessWidget {
  const CogniReadApp({
    super.key,
    this.pickEpubPath,
    this.storageService,
    this.syncAdapter,
    this.stubImport,
  });

  final Future<String?> Function()? pickEpubPath;
  final StorageService? storageService;
  final SyncAdapter? syncAdapter;
  final bool? stubImport;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CogniRead',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFB3623C),
          surface: const Color(0xFFF7F2EA),
        ),
        useMaterial3: true,
        fontFamily: 'Avenir',
        fontFamilyFallback: const ['Helvetica', 'Arial', 'sans-serif'],
        scaffoldBackgroundColor: const Color(0xFFF7F2EA),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFF7F2EA),
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: true,
        ),
      ),
      home: LibraryScreen(
        pickEpubPath: pickEpubPath,
        storageService: storageService,
        syncAdapter: syncAdapter,
        stubImport: stubImport ?? false,
      ),
    );
  }
}
