import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'app/theme.dart';
import 'application/providers.dart';
import 'features/library/library_page.dart';
import 'features/reader/reader_page.dart';
import 'features/settings/settings_page.dart';

void main() {
  runApp(const ProviderScope(child: KnowledgeReaderApp()));
}

final _routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/library',
    routes: [
      GoRoute(path: '/library', builder: (context, state) => const LibraryPage()),
      GoRoute(
        path: '/reader/:itemId',
        builder: (context, state) => ReaderPage(
          itemId: Uri.decodeComponent(state.pathParameters['itemId'] ?? ''),
        ),
      ),
      GoRoute(path: '/settings', builder: (context, state) => const SettingsPage()),
      GoRoute(
        path: '/settings/server',
        builder: (context, state) => const SettingsPage(focusServer: true),
      ),
    ],
  );
});

class KnowledgeReaderApp extends ConsumerWidget {
  const KnowledgeReaderApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preferences = ref.watch(preferencesProvider).value ?? const ReaderPreferences();
    return MaterialApp.router(
      title: 'Knowledge Reader',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(preferences.theme),
      routerConfig: ref.watch(_routerProvider),
    );
  }
}
