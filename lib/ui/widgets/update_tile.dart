import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../../data/update_service.dart';
import '../../state/providers.dart';

/// "Buscar actualización": consulta la última versión publicada, la descarga
/// (verificando su SHA-256) y abre el instalador de Android. Los datos se
/// conservan porque la firma del APK nuevo coincide con la instalada.
class UpdateTile extends ConsumerStatefulWidget {
  const UpdateTile({super.key});

  @override
  ConsumerState<UpdateTile> createState() => _UpdateTileState();
}

class _UpdateTileState extends ConsumerState<UpdateTile> {
  bool _busy = false;
  double? _progress;
  late final Future<PackageInfo> _package = PackageInfo.fromPlatform();

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), duration: const Duration(seconds: 5)));
  }

  Future<void> _run() async {
    setState(() => _busy = true);
    try {
      final package = await _package;
      final service = ref.read(updateServiceProvider);
      final info = await service.check(int.tryParse(package.buildNumber) ?? 0);
      if (info == null) {
        _say('Ya tienes la última versión (${package.version}).');
        return;
      }
      if (!mounted) return;
      final accepted = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text('Actualizar a la ${info.versionName}'),
          content: Text(
            '${info.notes.isEmpty ? '' : '${info.notes}\n\n'}'
            'Tus datos se conservan. Android te pedirá confirmar la instalación.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Más tarde')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Actualizar')),
          ],
        ),
      );
      if (accepted != true) return;

      setState(() => _progress = 0);
      final file = await service.download(info, await getTemporaryDirectory(), onProgress: (p) {
        if (mounted) setState(() => _progress = p);
      });
      final result = await OpenFilex.open(file.path, type: 'application/vnd.android.package-archive');
      if (result.type != ResultType.done) {
        _say('No se pudo abrir el instalador. Permite "Instalar apps desconocidas" para Arnic en los ajustes de Android y vuelve a intentar.');
      }
    } on UpdateException catch (e) {
      _say(e.message);
    } catch (e) {
      _say('No se pudo actualizar: $e');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (_busy) LinearProgressIndicator(value: _progress),
        ListTile(
          leading: const Icon(Icons.system_update_alt),
          title: const Text('Buscar actualización'),
          subtitle: FutureBuilder<PackageInfo>(
            future: _package,
            builder: (context, snapshot) {
              final p = snapshot.data;
              final shown = p == null ? '' : 'Versión instalada: ${p.version} (${p.buildNumber}). ';
              return Text('$shown${_progress == null ? 'Se instala encima, sin perder tus datos.' : 'Descargando… ${(_progress! * 100).round()}%'}');
            },
          ),
          enabled: !_busy,
          onTap: _run,
        ),
      ],
    );
  }
}
