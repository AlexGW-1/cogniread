import 'package:cogniread/src/core/services/storage_service.dart';
import 'package:cogniread/src/features/library/presentation/library_screen.dart';
import 'package:flutter/material.dart';

class CogniReadApp extends StatelessWidget {
  const CogniReadApp({
    super.key,
    this.pickEpubPath,
    this.storageService,
    this.stubImport,
  });

  final Future<String?> Function()? pickEpubPath;
  final StorageService? storageService;
  final bool? stubImport;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CogniRead',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: LibraryScreen(
        pickEpubPath: pickEpubPath,
        storageService: storageService,
        stubImport: stubImport ?? false,
      ),
    );
  }
}
