import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/providers.dart';

/// Pantalla que tapa toda la app mientras está bloqueada. Pide biometría/PIN
/// del sistema automáticamente al aparecer, con un botón para reintentar.
class AppLockScreen extends ConsumerStatefulWidget {
  const AppLockScreen({super.key, required this.onUnlocked});

  final VoidCallback onUnlocked;

  @override
  ConsumerState<AppLockScreen> createState() => _AppLockScreenState();
}

class _AppLockScreenState extends ConsumerState<AppLockScreen> {
  bool _authenticating = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _unlock());
  }

  Future<void> _unlock() async {
    if (_authenticating) return;
    setState(() {
      _authenticating = true;
      _error = null;
    });
    final ok = await ref.read(appLockProvider).authenticate();
    if (!mounted) return;
    if (ok) {
      widget.onUnlocked();
      return;
    }
    setState(() {
      _authenticating = false;
      _error = 'No se pudo desbloquear. Inténtalo de nuevo.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surface,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset('assets/images/logo.png', height: 64),
                const SizedBox(height: 24),
                Icon(Icons.lock_outline, size: 40, color: scheme.onSurfaceVariant),
                const SizedBox(height: 16),
                Text('Arnic Finance está bloqueada', style: Theme.of(context).textTheme.titleMedium),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!, style: TextStyle(color: scheme.error), textAlign: TextAlign.center),
                ],
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _authenticating ? null : _unlock,
                  icon: const Icon(Icons.fingerprint),
                  label: Text(_authenticating ? 'Verificando…' : 'Desbloquear'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
