import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/backup_service.dart';
import '../../data/meta_sync_client.dart';
import '../../state/providers.dart';
import '../widgets/update_tile.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  Future<void> _editCurrency(BuildContext context, WidgetRef ref, String current) async {
    // Capturados antes del await: `ref` puede dejar de ser válido si la pantalla
    // se cierra mientras el diálogo está abierto.
    final settings = ref.read(settingsRepositoryProvider);
    final quickActions = ref.read(quickActionsProvider);
    // `_CurrencyDialog` es un StatefulWidget propio (ver el comentario sobre
    // `_ConnectDialog` más abajo): dispone su controller cuando el diálogo de
    // verdad se desmonta, no apenas `showDialog` resuelve.
    final value = await showDialog<String>(context: context, builder: (_) => _CurrencyDialog(initial: current));
    if (value != null && value.isNotEmpty) {
      await settings.setCurrencySymbol(value);
      quickActions.refreshWidgets();
    }
  }

  Future<void> _exportBackup(BuildContext context, WidgetRef ref) async {
    final db = ref.read(databaseProvider);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final json = await BackupService(db).exportJson();
      final dir = await getTemporaryDirectory();
      final stamp = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
      final file = await File('${dir.path}/arnic_backup_$stamp.json').writeAsString(json);
      await SharePlus.instance.share(ShareParams(files: [XFile(file.path)], subject: 'Copia de seguridad de Arnic Finance'));
    } catch (e) {
      if (context.mounted) messenger.showSnackBar(SnackBar(content: Text('No se pudo exportar: $e')));
    }
  }

  Future<void> _importBackup(BuildContext context, WidgetRef ref) async {
    final db = ref.read(databaseProvider);
    final quickActions = ref.read(quickActionsProvider);
    final messenger = ScaffoldMessenger.of(context);

    final picked = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: ['json'], dialogTitle: 'Elige tu copia de seguridad');
    if (picked == null || !context.mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('¿Restaurar copia de seguridad?'),
        content: const Text(
          'Esto reemplaza TODOS los datos actuales (movimientos, categorías, cuentas y presupuestos) por los del archivo. '
          'No se puede deshacer.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Restaurar')),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final bytes = await picked.readAsBytes();
      await BackupService(db).restoreFromJson(utf8.decode(bytes));
      quickActions.refreshWidgets();
      if (context.mounted) messenger.showSnackBar(const SnackBar(content: Text('Copia restaurada.')));
    } on FormatException catch (e) {
      if (context.mounted) messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      if (context.mounted) messenger.showSnackBar(SnackBar(content: Text('No se pudo restaurar: $e')));
    }
  }

  Future<void> _addTile(BuildContext context, WidgetRef ref, {required bool expense}) async {
    final result = await ref.read(quickActionsProvider).requestAddTile(expense: expense);
    if (!context.mounted) return;
    final msg = switch (result) {
      'added' => 'Listo: tile añadida al panel de ajustes rápidos',
      'already_added' => 'Esa tile ya está en tu panel',
      'not_added' => 'No se añadió. Puedes hacerlo desde el editor del panel (lápiz).',
      'unsupported' => 'Tu Android no permite añadirla desde aquí: baja el panel, pulsa el lápiz y arrastra "Arnic: ${expense ? 'Gasto' : 'Ingreso'}".',
      _ => 'No se pudo añadir. Hazlo desde el editor del panel (lápiz).',
    };
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 5)));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currency = ref.watch(currencySymbolProvider).value ?? 'RD\$';
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 110),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Text('Ajustes', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
          ),
          ListTile(leading: const Icon(Icons.category_outlined), title: const Text('Categorías'), trailing: const Icon(Icons.chevron_right), onTap: () => context.push('/categories')),
          ListTile(leading: const Icon(Icons.account_balance_wallet_outlined), title: const Text('Cuentas'), trailing: const Icon(Icons.chevron_right), onTap: () => context.push('/accounts')),
          ListTile(leading: const Icon(Icons.savings_outlined), title: const Text('Presupuestos'), subtitle: const Text('Límites mensuales y metas de ahorro'), trailing: const Icon(Icons.chevron_right), onTap: () => context.push('/budgets')),
          ListTile(leading: const Icon(Icons.payments_outlined), title: const Text('Moneda'), subtitle: Text('Símbolo: $currency'), onTap: () => _editCurrency(context, ref, currency)),
          const Divider(height: 32),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Text('REGISTRO SIN ABRIR LA APP', style: Theme.of(context).textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant)),
          ),
          if (Platform.isAndroid) ...[
            ListTile(
              leading: const Icon(Icons.remove_circle_outline),
              title: const Text('Añadir tile "Gasto" al panel rápido'),
              subtitle: const Text('Baja el panel → pulsa Arnic → monto → guardar'),
              onTap: () => _addTile(context, ref, expense: true),
            ),
            ListTile(
              leading: const Icon(Icons.add_circle_outline),
              title: const Text('Añadir tile "Ingreso" al panel rápido'),
              onTap: () => _addTile(context, ref, expense: false),
            ),
            ListTile(
              leading: const Icon(Icons.widgets_outlined),
              title: const Text('Añadir widget a la pantalla de inicio'),
              subtitle: const Text('Botones Gasto / Ingreso y el total de hoy'),
              onTap: () async {
                final ok = await ref.read(quickActionsProvider).requestPinWidget();
                if (!context.mounted) return;
                if (!ok) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Tu launcher no lo permite desde aquí: mantén pulsada la pantalla de inicio → Widgets → Arnic.'),
                    duration: Duration(seconds: 5),
                  ));
                }
              },
            ),
            const ListTile(
              leading: Icon(Icons.touch_app_outlined),
              title: Text('Atajos del icono'),
              subtitle: Text('Mantén pulsado el icono de la app: "Registrar gasto" o "Registrar ingreso".'),
            ),
          ] else
            const ListTile(
              leading: Icon(Icons.info_outline),
              title: Text('Control Center, botón de acción y Atajos'),
              subtitle: Text('Se activan desde los ajustes de iOS. Consulta docs/IOS.md.'),
            ),
          const Divider(height: 32),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Text('SEGURIDAD', style: Theme.of(context).textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant)),
          ),
          Builder(builder: (context) {
            final supported = ref.watch(appLockSupportedProvider).value ?? false;
            return SwitchListTile(
              secondary: const Icon(Icons.fingerprint),
              title: const Text('Bloquear la app'),
              subtitle: Text(
                supported
                    ? 'Pide tu huella, rostro o el PIN del teléfono al abrir la app'
                    : 'Tu teléfono no tiene huella, rostro ni PIN/patrón configurado: actívalo en Ajustes del sistema primero.',
              ),
              value: ref.watch(appLockEnabledProvider),
              onChanged: !supported ? null : (value) => ref.read(appLockEnabledProvider.notifier).set(value),
            );
          }),
          const Divider(height: 32),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Text('RESPALDO', style: Theme.of(context).textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant)),
          ),
          ListTile(
            leading: const Icon(Icons.upload_outlined),
            title: const Text('Exportar copia de seguridad'),
            subtitle: const Text('Un archivo con todo tu historial, para guardarlo donde quieras'),
            onTap: () => _exportBackup(context, ref),
          ),
          ListTile(
            leading: const Icon(Icons.download_outlined),
            title: const Text('Restaurar desde un archivo'),
            subtitle: const Text('Reemplaza todos los datos actuales por los de la copia'),
            onTap: () => _importBackup(context, ref),
          ),
          if (Platform.isAndroid) ...[
            const Divider(height: 32),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Text('ACTUALIZACIONES', style: Theme.of(context).textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant)),
            ),
            const UpdateTile(),
          ],
          const Divider(height: 32),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Text('INTEGRACIONES', style: Theme.of(context).textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant)),
          ),
          const _MetaSyncSection(),
          const Divider(height: 32),
          ListTile(
            leading: const Icon(Icons.lock_outline),
            title: const Text('Privacidad'),
            subtitle: Text(
              ref.watch(metaSyncEnabledProvider)
                  ? 'Tus datos se guardan en este dispositivo. Activaste "Conectar con Meta IA": tus movimientos y categorías también se envían al servidor que configuraste.'
                  : 'Tus datos financieros se guardan sólo en este dispositivo. La app no se conecta a ningún servidor.',
            ),
          ),
        ],
      ),
    );
  }
}

class _MetaSyncSection extends ConsumerStatefulWidget {
  const _MetaSyncSection();

  @override
  ConsumerState<_MetaSyncSection> createState() => _MetaSyncSectionState();
}

class _MetaSyncSectionState extends ConsumerState<_MetaSyncSection> {
  bool _busy = false;

  Future<void> _configure({required bool rotate}) async {
    final container = ProviderScope.containerOf(context, listen: false);
    final prefs = container.read(metaSyncPrefsProvider);
    final messenger = ScaffoldMessenger.of(context);

    // `_ConnectDialog` es un StatefulWidget con sus propios controllers
    // (mismo patrón que _AccountEditor/_BudgetEditor/_CategoryEditor en el
    // resto de la app): así Flutter los dispone solo cuando el diálogo de
    // verdad termina de desmontarse. Disponerlos a mano justo después de que
    // `showDialog` resuelve es demasiado pronto — la animación de salida
    // todavía está dibujando el TextField en ese momento.
    final result = await showDialog<(String, String)>(
      context: context,
      builder: (_) => _ConnectDialog(rotate: rotate, initialUrl: prefs.serverUrl ?? 'https://'),
    );
    if (result == null) return;
    final (serverUrl, setupToken) = result;
    if (serverUrl.isEmpty || setupToken.isEmpty) return;

    setState(() => _busy = true);
    // Se muestra ANTES de llamar a la red: el plan gratis de Render puede
    // tardar hasta un minuto en "despertar", y sin este aviso esa espera se
    // ve igual que la app congelada (el indicador de progreso de abajo ayuda,
    // pero un mensaje explícito evita la confusión).
    messenger.showSnackBar(
      const SnackBar(content: Text('Conectando… puede tardar hasta un minuto si el servidor estaba dormido.'), duration: Duration(seconds: 65)),
    );
    try {
      final apiKey = await container.read(metaSyncClientProvider).setup(serverUrl: serverUrl, setupToken: setupToken, rotate: rotate);
      await prefs.setCredentials(serverUrl: serverUrl, apiKey: apiKey);
      container.read(metaSyncEnabledProvider.notifier).set(true);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Conectado. Sincronizando…')));
      await container.read(metaSyncServiceProvider).syncNow();
      if (mounted) {
        messenger.hideCurrentSnackBar();
        // La API key sólo se muestra en este momento (y desde "Ver API key"
        // más adelante): es lo único que le falta al usuario para dársela a
        // su conector de Meta IA, y la app nunca se la manda a nadie.
        await _showApiKey(apiKey);
      }
    } on MetaSyncException catch (e) {
      if (mounted) {
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(e.message), duration: const Duration(seconds: 6)));
      }
    } catch (e) {
      if (mounted) {
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text('No se pudo conectar: $e'), duration: const Duration(seconds: 6)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Muestra la API key para copiarla: es lo único que le falta al usuario
  /// para dársela a su conector de Meta IA (junto con la URL del servidor).
  /// La app nunca la envía a ningún sitio salvo al propio servidor configurado.
  Future<void> _showApiKey(String apiKey) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Tu API key'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Dale esto a tu conector de Meta IA junto con la URL del servidor:'),
            const SizedBox(height: 12),
            SelectableText(apiKey, style: const TextStyle(fontFamily: 'monospace')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cerrar')),
          FilledButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: apiKey));
              if (dialogContext.mounted) Navigator.pop(dialogContext);
            },
            icon: const Icon(Icons.copy, size: 18),
            label: const Text('Copiar'),
          ),
        ],
      ),
    );
  }

  Future<void> _runSync(Future<void> Function() action, {required String successMessage}) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    messenger.showSnackBar(
      const SnackBar(content: Text('Sincronizando… puede tardar hasta un minuto si el servidor estaba dormido.'), duration: Duration(seconds: 65)),
    );
    try {
      await action();
      if (mounted) {
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(successMessage)));
      }
    } on MetaSyncException catch (e) {
      if (mounted) {
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(e.message), duration: const Duration(seconds: 6)));
      }
    } catch (e) {
      if (mounted) {
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text('No se pudo completar: $e'), duration: const Duration(seconds: 6)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _disconnect() async {
    final container = ProviderScope.containerOf(context, listen: false);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('¿Desconectar Meta IA?'),
        content: const Text('Se borra la API key guardada en este teléfono. El servidor y lo que ya se sincronizó no se tocan.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Desconectar')),
        ],
      ),
    );
    if (confirmed != true) return;
    await container.read(metaSyncPrefsProvider).clearCredentials();
    container.read(metaSyncEnabledProvider.notifier).set(false);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final prefs = ref.watch(metaSyncPrefsProvider);
    final enabled = ref.watch(metaSyncEnabledProvider);
    final configured = prefs.isConfigured;
    final service = ref.read(metaSyncServiceProvider);

    return Column(
      children: [
        // Visible siempre que haya una operación de red en curso: sin esto,
        // la espera de hasta un minuto (servidor "dormido" del plan gratis de
        // Render) no da ninguna señal de que algo sigue pasando.
        if (_busy) const LinearProgressIndicator(),
        SwitchListTile(
          secondary: const Icon(Icons.hub_outlined),
          title: const Text('Conectar con Meta IA'),
          subtitle: Text(
            !configured
                ? 'Sin configurar todavía. Pulsa "Configurar servidor" para empezar.'
                : enabled
                    ? 'Activo — sincronizando con ${prefs.serverUrl}'
                    : 'Configurado pero apagado: ${prefs.serverUrl}',
          ),
          value: enabled && configured,
          onChanged: _busy || !configured ? null : (v) => ref.read(metaSyncEnabledProvider.notifier).set(v),
        ),
        ListTile(
          leading: const Icon(Icons.settings_ethernet),
          title: Text(configured ? 'Reconfigurar servidor' : 'Configurar servidor'),
          subtitle: const Text('Pega la URL de tu servidor y el setup token (ver server/README.md)'),
          enabled: !_busy,
          // rotate: true es seguro aquí en los dos casos: si el servidor
          // todavía no tiene ninguna key, la crea igual (rotate se ignora);
          // si ya tiene una (p. ej. quedó aprovisionada de una prueba previa),
          // la reemplaza en vez de fallar con 409 "ya existe".
          onTap: () => _configure(rotate: true),
        ),
        if (configured) ...[
          ListTile(
            leading: const Icon(Icons.key_outlined),
            title: const Text('Ver API key'),
            subtitle: const Text('Para dársela a tu conector de Meta IA'),
            enabled: !_busy,
            onTap: () => _showApiKey(prefs.apiKey!),
          ),
          ListTile(
            leading: const Icon(Icons.vpn_key_outlined),
            title: const Text('Regenerar API key'),
            subtitle: const Text('Invalida la key anterior'),
            enabled: !_busy,
            onTap: () => _configure(rotate: true),
          ),
          ListTile(
            leading: const Icon(Icons.sync),
            title: const Text('Sincronizar ahora'),
            enabled: !_busy,
            onTap: () => _runSync(service.syncNow, successMessage: 'Sincronizado.'),
          ),
          ListTile(
            leading: const Icon(Icons.restart_alt),
            title: const Text('Forzar sincronización completa'),
            subtitle: const Text('Reenvía y relee todo desde cero'),
            enabled: !_busy,
            onTap: () => _runSync(service.fullResync, successMessage: 'Sincronización completa lista.'),
          ),
          ListTile(
            leading: Icon(Icons.link_off, color: scheme.error),
            title: Text('Desconectar', style: TextStyle(color: scheme.error)),
            enabled: !_busy,
            onTap: _disconnect,
          ),
        ],
      ],
    );
  }
}

class _CurrencyDialog extends StatefulWidget {
  const _CurrencyDialog({required this.initial});

  final String initial;

  @override
  State<_CurrencyDialog> createState() => _CurrencyDialogState();
}

class _CurrencyDialogState extends State<_CurrencyDialog> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Símbolo de moneda'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 5,
        decoration: const InputDecoration(hintText: 'RD\$, US\$, €…'),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        TextButton(onPressed: () => Navigator.pop(context, _controller.text.trim()), child: const Text('Guardar')),
      ],
    );
  }
}

/// Contenido del diálogo de "Configurar servidor"/"Regenerar API key". Un
/// `StatefulWidget` propio (no un `TextEditingController` ad-hoc en el método
/// de afuera) para que Flutter dispone los controllers en su propio
/// `dispose()`, cuando el diálogo de verdad se desmonta — no en cuanto
/// `showDialog` resuelve, que todavía es mitad de la animación de salida.
class _ConnectDialog extends StatefulWidget {
  const _ConnectDialog({required this.rotate, required this.initialUrl});

  final bool rotate;
  final String initialUrl;

  @override
  State<_ConnectDialog> createState() => _ConnectDialogState();
}

class _ConnectDialogState extends State<_ConnectDialog> {
  late final _urlController = TextEditingController(text: widget.initialUrl);
  final _tokenController = TextEditingController();

  @override
  void dispose() {
    _urlController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  void _submit() => Navigator.pop(context, (_urlController.text.trim(), _tokenController.text.trim()));

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.rotate ? 'Regenerar API key' : 'Conectar con Meta IA'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _urlController,
            autofocus: true,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(labelText: 'URL del servidor', hintText: 'https://tu-servidor.onrender.com'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _tokenController,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Setup token'),
          ),
          const SizedBox(height: 8),
          Text(
            'El setup token lo definiste tú al desplegar el servidor (variable SETUP_TOKEN). No se guarda en la app: sólo sirve para pedir la API key una vez.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: _submit, child: const Text('Conectar')),
      ],
    );
  }
}
