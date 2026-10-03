import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/backup_service.dart';
import '../../data/meta_sync_client.dart';
import '../../state/providers.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  Future<void> _editCurrency(BuildContext context, WidgetRef ref, String current) async {
    // Capturados antes del await: `ref` puede dejar de ser válido si la pantalla
    // se cierra mientras el diálogo está abierto.
    final settings = ref.read(settingsRepositoryProvider);
    final quickActions = ref.read(quickActionsProvider);
    final controller = TextEditingController(text: current);
    final value = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Símbolo de moneda'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 5,
          decoration: const InputDecoration(hintText: 'RD\$, US\$, €…'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('Guardar')),
        ],
      ),
    );
    controller.dispose();
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
      builder: (_) => AlertDialog(
        title: const Text('¿Restaurar copia de seguridad?'),
        content: const Text(
          'Esto reemplaza TODOS los datos actuales (movimientos, categorías, cuentas y presupuestos) por los del archivo. '
          'No se puede deshacer.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Restaurar')),
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

    final urlController = TextEditingController(text: prefs.serverUrl ?? 'https://');
    final tokenController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(rotate ? 'Regenerar API key' : 'Conectar con Meta IA'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: urlController,
              autofocus: true,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(labelText: 'URL del servidor', hintText: 'https://tu-servidor.onrender.com'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: tokenController,
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
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Conectar')),
        ],
      ),
    );
    final serverUrl = urlController.text.trim();
    final setupToken = tokenController.text.trim();
    urlController.dispose();
    tokenController.dispose();
    if (confirmed != true || serverUrl.isEmpty || setupToken.isEmpty) return;

    setState(() => _busy = true);
    try {
      final apiKey = await container.read(metaSyncClientProvider).setup(serverUrl: serverUrl, setupToken: setupToken, rotate: rotate);
      await prefs.setCredentials(serverUrl: serverUrl, apiKey: apiKey);
      container.read(metaSyncEnabledProvider.notifier).set(true);
      messenger.showSnackBar(const SnackBar(content: Text('Conectado. Sincronizando…')));
      await container.read(metaSyncServiceProvider).syncNow();
      if (mounted) messenger.showSnackBar(const SnackBar(content: Text('Listo: ya puedes usar tu conector de Meta IA.')));
    } on MetaSyncException catch (e) {
      if (mounted) messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      if (mounted) messenger.showSnackBar(SnackBar(content: Text('No se pudo conectar: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _runSync(Future<void> Function() action, {required String successMessage}) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) messenger.showSnackBar(SnackBar(content: Text(successMessage)));
    } on MetaSyncException catch (e) {
      if (mounted) messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      if (mounted) messenger.showSnackBar(SnackBar(content: Text('No se pudo completar: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _disconnect() async {
    final container = ProviderScope.containerOf(context, listen: false);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('¿Desconectar Meta IA?'),
        content: const Text('Se borra la API key guardada en este teléfono. El servidor y lo que ya se sincronizó no se tocan.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Desconectar')),
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
          onTap: () => _configure(rotate: false),
        ),
        if (configured) ...[
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
