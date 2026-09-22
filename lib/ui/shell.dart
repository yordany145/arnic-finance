import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Barra inferior + botón grande "+" (acción principal de la app).
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) {
    final onSettings = shell.currentIndex == 2;
    return Scaffold(
      body: shell,
      floatingActionButton: onSettings
          ? null
          : SizedBox(
              height: 64,
              child: FloatingActionButton.extended(
                onPressed: () => context.push('/add'),
                icon: const Icon(Icons.add, size: 30),
                label: const Text('Registrar', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              ),
            ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      bottomNavigationBar: NavigationBar(
        selectedIndex: shell.currentIndex,
        onDestinationSelected: (i) => shell.goBranch(i, initialLocation: i == shell.currentIndex),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Inicio'),
          NavigationDestination(icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long), label: 'Movimientos'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'Ajustes'),
        ],
      ),
    );
  }
}
