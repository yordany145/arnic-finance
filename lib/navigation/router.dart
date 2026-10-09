import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../domain/enums.dart';
import '../ui/screens/accounts_screen.dart';
import '../ui/screens/assistant_screen.dart';
import '../ui/screens/budgets_screen.dart';
import '../ui/screens/add_movement_screen.dart';
import '../ui/screens/cards_screen.dart';
import '../ui/screens/categories_screen.dart';
import '../ui/screens/history_screen.dart';
import '../ui/screens/home_screen.dart';
import '../ui/screens/reports_screen.dart';
import '../ui/screens/review_screen.dart';
import '../ui/screens/settings_screen.dart';
import '../ui/shell.dart';

/// Rutas. `/add?type=expense|income` también sirve como enlace profundo
/// (`arnic:///add?type=expense`) para los accesos rápidos de iOS que abren la app.
GoRouter buildRouter() => GoRouter(
      initialLocation: '/',
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (context, state, shell) => AppShell(shell: shell),
          branches: [
            StatefulShellBranch(routes: [GoRoute(path: '/', builder: (_, _) => const HomeScreen())]),
            StatefulShellBranch(routes: [GoRoute(path: '/history', builder: (_, _) => const HistoryScreen())]),
            StatefulShellBranch(routes: [GoRoute(path: '/assistant', builder: (_, _) => const AssistantScreen())]),
            StatefulShellBranch(routes: [GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen())]),
          ],
        ),
        GoRoute(
          path: '/add',
          builder: (_, state) => AddMovementScreen(
            initialType: state.uri.queryParameters['type'] == 'income' ? TxType.income : TxType.expense,
          ),
        ),
        GoRoute(path: '/edit/:id', builder: (_, state) => AddMovementScreen(editId: state.pathParameters['id'])),
        GoRoute(path: '/categories', builder: (_, _) => const CategoriesScreen()),
        GoRoute(path: '/accounts', builder: (_, _) => const AccountsScreen()),
        GoRoute(path: '/budgets', builder: (_, _) => const BudgetsScreen()),
        GoRoute(path: '/cards', builder: (_, _) => const CardsScreen()),
        GoRoute(path: '/reports', builder: (_, _) => const ReportsScreen()),
        GoRoute(path: '/review', builder: (_, _) => const ReviewScreen()),
      ],
      errorBuilder: (_, _) => const Scaffold(body: Center(child: Text('Pantalla no encontrada'))),
    );
