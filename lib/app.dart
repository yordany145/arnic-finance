import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme.dart';
import 'navigation/router.dart';
import 'state/providers.dart';

class ArnicApp extends ConsumerStatefulWidget {
  const ArnicApp({super.key});

  @override
  ConsumerState<ArnicApp> createState() => _ArnicAppState();
}

class _ArnicAppState extends ConsumerState<ArnicApp> with WidgetsBindingObserver {
  final _router = buildRouter();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => checkBudgetAlerts(ref));
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
    checkBudgetAlerts(ref);
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
    );
  }
}
