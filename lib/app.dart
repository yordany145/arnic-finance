import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme.dart';
import 'navigation/router.dart';
import 'state/providers.dart';
import 'ui/screens/app_lock_screen.dart';

class ArnicApp extends ConsumerStatefulWidget {
  const ArnicApp({super.key});

  @override
  ConsumerState<ArnicApp> createState() => _ArnicAppState();
}

class _ArnicAppState extends ConsumerState<ArnicApp> with WidgetsBindingObserver {
  final _router = buildRouter();
  bool _locked = false;

  @override
  void initState() {
    super.initState();
    _locked = ref.read(appLockEnabledProvider);
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final container = ProviderScope.containerOf(context, listen: false);
      checkBudgetAlerts(container);
      syncWithServerIfEnabled(container);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _openPendingRoute());
  }

  /// iOS: un control de Centro de control/pantalla de bloqueo abrió la app pidiendo
  /// una pantalla concreta (registrar gasto/ingreso).
  Future<void> _openPendingRoute() async {
    final route = await ref.read(quickActionsProvider).consumePendingRoute();
    if (route != null && mounted) _router.push(route);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _router.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Al ir a segundo plano: si el bloqueo está activado, la próxima vez que se
    // vea la app debe pedir desbloquear (sin importar cuánto haya tardado).
    if (state == AppLifecycleState.paused && ref.read(appLockEnabledProvider) && !_locked) {
      setState(() => _locked = true);
      return;
    }
    if (state != AppLifecycleState.resumed) return;
    _openPendingRoute();
    // "Hoy"/"este mes" pueden haber cambiado mientras la app dormía.
    ref.invalidate(nowProvider);
    // El registro rápido nativo escribe en el mismo archivo SQLite desde otro
    // proceso/hilo: drift no lo detecta solo, así que pedimos releer.
    final db = ref.read(databaseProvider);
    db.markTablesUpdated({db.transactions, db.categories, db.accounts, db.appSettings, db.budgets});
    // Por si la hoja rápida nativa insertó un gasto mientras la app dormía.
    // (Kotlin ya intenta notificar al guardar; esto es el respaldo. La tabla
    // budget_alerts evita que se avise dos veces.)
    final container = ProviderScope.containerOf(context, listen: false);
    checkBudgetAlerts(container);
    // No-op si la sincronización con el servidor está apagada (el caso por defecto).
    syncWithServerIfEnabled(container);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Arnic Finance',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      locale: const Locale('es', 'DO'),
      supportedLocales: const [Locale('es', 'DO'), Locale('es')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      routerConfig: _router,
      // Tapa toda la app (encima del Navigator) mientras esté bloqueada, sin
      // perder el Theme/Localizations que MaterialApp ya montó.
      builder: (context, child) =>
          _locked ? AppLockScreen(onUnlocked: () => setState(() => _locked = false)) : child!,
    );
  }
}
