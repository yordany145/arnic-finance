import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:go_router/go_router.dart';

/// Barra inferior + botón grande "+" (acción principal de la app).
///
/// El botón flota sobre las listas y tapaba el monto del último movimiento visible: se esconde
/// al bajar por la lista y vuelve en cuanto se sube (o se llega al principio).
class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  /// El "+" para registrar no aporta ni en Ajustes ni en el chat del asistente
  /// (allí ya está el campo de texto).
  static const _hideFabOn = {2, 3};

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  bool _fabVisible = true;

  bool _onScroll(ScrollNotification n) {
    // Sólo el desplazamiento vertical de la lista principal (no carruseles ni hojas).
    if (n.depth != 0 || n.metrics.axis != Axis.vertical) return false;
    if (n is UserScrollNotification) {
      final show = switch (n.direction) {
        ScrollDirection.reverse => false, // el dedo sube: la lista baja
        ScrollDirection.forward => true,
        ScrollDirection.idle => _fabVisible,
      };
      if (show != _fabVisible) setState(() => _fabVisible = show);
    } else if (n is ScrollUpdateNotification && n.metrics.pixels <= n.metrics.minScrollExtent + 1 && !_fabVisible) {
      setState(() => _fabVisible = true);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final shell = widget.shell;
    final showFab = !AppShell._hideFabOn.contains(shell.currentIndex);
    return Scaffold(
      body: NotificationListener<ScrollNotification>(onNotification: _onScroll, child: shell),
      floatingActionButton: showFab
          ? AnimatedSlide(
              offset: _fabVisible ? Offset.zero : const Offset(0, 2),
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              child: AnimatedOpacity(
                opacity: _fabVisible ? 1 : 0,
                duration: const Duration(milliseconds: 200),
                child: IgnorePointer(
                  ignoring: !_fabVisible,
                  child: SizedBox(
                    height: 64,
                    child: FloatingActionButton.extended(
                      onPressed: () => context.push('/add'),
                      icon: const Icon(Icons.add, size: 30),
                      label: const Text('Registrar', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                    ),
                  ),
                ),
              ),
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      bottomNavigationBar: NavigationBar(
        selectedIndex: shell.currentIndex,
        onDestinationSelected: (i) {
          setState(() => _fabVisible = true);
          shell.goBranch(i, initialLocation: i == shell.currentIndex);
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Inicio'),
          NavigationDestination(icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long), label: 'Movimientos'),
          NavigationDestination(icon: Icon(Icons.smart_toy_outlined), selectedIcon: Icon(Icons.smart_toy), label: 'Asistente'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'Ajustes'),
        ],
      ),
    );
  }
}
