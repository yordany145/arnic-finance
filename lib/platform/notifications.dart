import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../core/money.dart';
import '../domain/budget.dart';

/// Notificaciones locales para los avisos de presupuesto. Se disparan al
/// momento (justo después de guardar un movimiento), no hay servidor.
class BudgetNotifier {
  BudgetNotifier() : _plugin = FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  bool _ready = false;

  static const _channelId = 'arnic_budgets';
  static const _channelName = 'Presupuestos';
  static const _channelDescription = 'Avisos al acercarte o llegar a un límite o meta';

  Future<void> init() async {
    if (_ready) return;
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_notification'),
        iOS: DarwinInitializationSettings(),
      ),
    );
    _ready = true;
  }

  /// Pide permiso de notificaciones (Android 13+ y iOS). Se llama al crear el
  /// primer presupuesto, no al abrir la app, para no pedirlo sin motivo.
  Future<void> requestPermission() async {
    await init();
    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    await _plugin
        .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);
  }

  Future<void> notify(BudgetProgress progress, AlertLevel level, String currency) async {
    await init();
    final savings = progress.budget.kind == BudgetKind.savings;
    final title = switch ((savings, level)) {
      (true, AlertLevel.approaching) => '🐷 Casi llegas a tu meta de ahorro',
      (true, AlertLevel.reached) => '🎉 ¡Meta de ahorro cumplida!',
      (false, AlertLevel.approaching) => '⚠️ Acercándote al límite: ${progress.budget.title}',
      (false, AlertLevel.reached) => '🚨 Límite alcanzado: ${progress.budget.title}',
    };
    final pct = (progress.ratio * 100).clamp(-999, 999).round();
    final body = savings
        ? '${formatMoney(progress.currentMinor, currency)} de ${formatMoney(progress.budget.amountMinor, currency)} ($pct%)'
        : '${formatMoney(progress.currentMinor, currency)} de ${formatMoney(progress.budget.amountMinor, currency)} gastados ($pct%)';

    // Un id estable por presupuesto+nivel: si vuelve a dispararse (no debería,
    // porque markAlertIfNew ya lo evita) reemplaza en vez de duplicar.
    final id = Object.hash(progress.budget.id, level).hashCode & 0x7fffffff;
    await _plugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDescription,
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
    );
  }
}
