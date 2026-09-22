import 'dart:io';

import 'package:flutter/services.dart';

/// Puente con el código nativo de Android para los accesos rápidos del sistema.
/// En iOS los accesos (control, widget, App Intents) viven en la extensión y no
/// necesitan llamadas desde Dart; ver docs/IOS.md.
class QuickActions {
  const QuickActions();

  static const _channel = MethodChannel('com.arnic.finance/quick');

  bool get isAndroid => Platform.isAndroid;

  /// Pide al sistema añadir una tile al panel de ajustes rápidos (Android 13+).
  /// El sistema muestra su propio diálogo de confirmación; el usuario decide.
  /// Devuelve `unsupported` en Android < 13 (allí se añade a mano desde el editor
  /// de tiles), o `added`, `already_added`, `not_added`, `error`.
  Future<String> requestAddTile({required bool expense}) async {
    if (!Platform.isAndroid) return 'unsupported';
    try {
      return await _channel.invokeMethod<String>('requestAddTile', {'expense': expense}) ?? 'error';
    } on PlatformException {
      return 'error';
    } on MissingPluginException {
      return 'unsupported';
    }
  }

  /// Pide anclar el widget de la pantalla de inicio (si el launcher lo permite).
  Future<bool> requestPinWidget() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('requestPinWidget') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// iOS: ruta que dejó un control/widget (p. ej. `/add?type=expense`) para abrir
  /// la app directo en el registro. `null` si no hay ninguna pendiente.
  Future<String?> consumePendingRoute() async {
    if (!Platform.isIOS) return null;
    try {
      return await _channel.invokeMethod<String>('consumePendingRoute');
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// Refresca el widget tras cambios hechos dentro de la app.
  Future<void> refreshWidgets() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('refreshWidgets');
    } on PlatformException {
      // El widget se actualizará solo en su próximo ciclo.
    } on MissingPluginException {
      // Sin plataforma nativa (tests).
    }
  }
}
