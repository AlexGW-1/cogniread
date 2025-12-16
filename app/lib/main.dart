import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  runApp(const ProviderScope(child: CogniReadApp()));
}

class CogniReadApp extends StatelessWidget {
  const CogniReadApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CogniRead',
      theme: ThemeData(useMaterial3: true),
      home: const AppShell(),
    );
  }
}

class AppShell extends StatelessWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('CogniRead (MVP skeleton)')),
      body: const Center(
        child: Text('App shell ready. Next: auth + library + reader.'),
      ),
    );
  }
}
