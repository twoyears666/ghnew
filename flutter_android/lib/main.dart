import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';

import 'app_store.dart';
import 'content_view.dart';
import 'settings.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SettingsStore.i.init();
  await store.init();
  runApp(const GhnewApp());
}

class GhnewApp extends StatefulWidget {
  const GhnewApp({super.key});
  @override
  State<GhnewApp> createState() => _GhnewAppState();
}

class _GhnewAppState extends State<GhnewApp> {
  final _links = AppLinks();

  @override
  void initState() {
    super.initState();
    _initLinks();
  }

  Future<void> _initLinks() async {
    // Cold start.
    try {
      final initial = await _links.getInitialLink();
      if (initial != null) _handle(Uri.parse(initial.toString()));
    } catch (_) {}
    try {
      _links.uriLinkStream.listen((uri) => _handle(uri));
    } catch (_) {}
  }

  void _handle(Uri uri) {
    if (uri.scheme != 'ghnew') return;
    final host = uri.host;
    final parts = uri.pathSegments;
    switch (host) {
      case 'add':
        if (parts.length >= 2) store.prefillAddRepo(parts[0], parts[1]);
        break;
      case 'repo':
        if (parts.length >= 2) store.openRepo(parts[0], parts[1]);
        break;
      case 'release':
        if (parts.length >= 3) {
          store.openRelease(parts[0], parts[1], parts[2]);
        }
        break;
      case 'action':
        if (parts.length >= 3) {
          final id = int.tryParse(parts[2]);
          if (id != null) store.openAction(parts[0], parts[1], id);
        }
        break;
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: SettingsStore.i,
      builder: (context, _) {
        return MaterialApp(
          title: 'ghnew',
          debugShowCheckedModeBanner: false,
          theme: buildAppTheme(),
          darkTheme: buildAppTheme(),
          themeMode: SettingsStore.i.isDark ? ThemeMode.dark : ThemeMode.light,
          home: const Scaffold(body: ContentView()),
        );
      },
    );
  }
}