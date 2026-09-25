import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:local_auth/local_auth.dart';
import 'package:provider/provider.dart';

import 'app_services.dart';
import 'data/prefs.dart';
import 'data/store.dart';
import 'services/drive_sync.dart';
import 'services/exporter.dart';
import 'ui/screens/home_shell.dart';

class ClientProApp extends StatelessWidget {
  const ClientProApp({super.key, required this.services});
  final AppServices services;

  ThemeData _theme(Color seed, Brightness brightness) {
    final scheme = ColorScheme.fromSeed(seedColor: seed, brightness: brightness);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: 'Tajawal',
      scaffoldBackgroundColor: brightness == Brightness.light ? const Color(0xFFF4F5F9) : null,
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surfaceContainerLowest,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
      appBarTheme: const AppBarTheme(centerTitle: false),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AppStore>.value(value: services.store),
        ChangeNotifierProvider<DevicePrefs>.value(value: services.prefs),
        ChangeNotifierProvider<DriveSync>.value(value: services.sync),
        Provider<AppServices>.value(value: services),
        Provider<Exporter>.value(value: services.exporter),
      ],
      child: Consumer<DevicePrefs>(
        builder: (context, prefs, _) => MaterialApp(
          title: 'ClientPro',
          debugShowCheckedModeBanner: false,
          locale: const Locale('ar'),
          supportedLocales: const [Locale('ar'), Locale('en')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          themeMode: prefs.themeMode,
          theme: _theme(prefs.accent, Brightness.light),
          darkTheme: _theme(prefs.accent, Brightness.dark),
          home: LockGate(services: services, child: const HomeShell()),
        ),
      ),
    );
  }
}

/// Face ID / fingerprint lock, and app lifecycle hooks.
class LockGate extends StatefulWidget {
  const LockGate({super.key, required this.services, required this.child});
  final AppServices services;
  final Widget child;

  @override
  State<LockGate> createState() => _LockGateState();
}

class _LockGateState extends State<LockGate> with WidgetsBindingObserver {
  bool _unlocked = false;
  bool _authenticating = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _unlock());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused && !_authenticating) {
      setState(() => _unlocked = false);
    }
    if (state == AppLifecycleState.resumed) {
      widget.services.onResume();
      _unlock();
    }
  }

  Future<void> _unlock() async {
    if (!widget.services.prefs.appLock || _unlocked || _authenticating) return;
    _authenticating = true;
    try {
      final auth = LocalAuthentication();
      if (!await auth.isDeviceSupported()) {
        setState(() => _unlocked = true);
        return;
      }
      final ok = await auth.authenticate(
        localizedReason: 'افتح التطبيق للوصول إلى بيانات عملائك',
        persistAcrossBackgrounding: true,
      );
      if (mounted && ok) setState(() => _unlocked = true);
    } catch (_) {
      // Leave it locked; the user can retry with the button.
    } finally {
      _authenticating = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final locked = context.watch<DevicePrefs>().appLock && !_unlocked;
    return Stack(
      children: [
        widget.child,
        if (locked)
          Positioned.fill(
            child: Material(
              color: Theme.of(context).colorScheme.surface,
              child: SafeArea(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.lock_outline, size: 72, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(height: 16),
                    Text(
                      context.watch<AppStore>().business.name.isEmpty
                          ? 'ClientPro'
                          : context.watch<AppStore>().business.name,
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    const Text('التطبيق مقفل لحماية بيانات عملائك'),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: _unlock,
                      icon: const Icon(Icons.fingerprint),
                      label: const Text('فتح القفل'),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
