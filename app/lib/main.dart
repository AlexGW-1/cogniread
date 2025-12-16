import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/app_router.dart';

void main() {
  runApp(const ProviderScope(child: CogniReadApp()));
}

class CogniReadApp extends ConsumerWidget {
  const CogniReadApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      title: 'CogniRead',
      theme: ThemeData(useMaterial3: true),
      routerConfig: router,
    );
  }
}
