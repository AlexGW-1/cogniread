import 'package:cogniread_app/src/features/library/presentation/library_screen.dart';
import 'package:flutter/material.dart';

class CogniReadApp extends StatelessWidget {
  const CogniReadApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CogniRead',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const LibraryScreen(),
    );
  }
}
