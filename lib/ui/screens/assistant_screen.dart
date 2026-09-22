import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/money.dart';
import '../../domain/assistant/amount_parser.dart';
import '../../domain/assistant/assistant_engine.dart';
import '../../domain/assistant/assistant_intent.dart';
import '../../domain/assistant/intent_parser.dart';
import '../../domain/assistant/text_normalize.dart';
import '../../domain/enums.dart';
import '../../domain/models.dart';
import '../../state/providers.dart';

class _ChatMessage {
  const _ChatMessage(this.text, {required this.fromUser});
  final String text;
  final bool fromUser;
}

const _quickReplies = <String>[
  '¿Cuánto gasté hoy?',
  '¿Cuánto gasté este mes?',
  '¿Cómo van mis presupuestos?',
  '¿En qué categoría gasté más?',
  'Mi saldo por cuenta',
];

/// Chat de preguntas sobre las finanzas del usuario. No es un LLM: interpreta
/// el texto con `IntentParser` (patrones/palabras clave) y responde con datos
/// reales vía `AssistantEngine`, todo local. Ver docs/ARQUITECTURA.md.
class AssistantScreen extends ConsumerStatefulWidget {
  const AssistantScreen({super.key});

  @override
  ConsumerState<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends ConsumerState<AssistantScreen> {
  static const _parser = IntentParser();

  final _messages = <_ChatMessage>[
    const _ChatMessage(
      '¡Hola! Pregúntame lo que quieras sobre tus finanzas, o escribe "ayuda" para ver ejemplos.',
      fromUser: false,
    ),
  ];
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  PendingClarification? _pending;
  bool _sending = false;

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _send([String? quickText]) async {
    final text = (quickText ?? _controller.text).trim();
    if (text.isEmpty || _sending) return;
    _controller.clear();
    setState(() {
      _messages.add(_ChatMessage(text, fromUser: true));
      _sending = true;
    });
    _scrollToEnd();

    // Capturado antes del await: si el usuario sale de esta pantalla mientras
    // se calcula la respuesta, `ref` deja de ser válido pero el container no.
    final container = ProviderScope.containerOf(context, listen: false);
    final now = container.read(nowProvider);
    final currency = container.read(currencySymbolProvider).value ?? kFallbackCurrencySymbol;
    final expenseCats = container.read(categoriesProvider(TxType.expense)).value ?? const <Category>[];
    final incomeCats = container.read(categoriesProvider(TxType.income)).value ?? const <Category>[];
    final accounts = container.read(accountsProvider).value ?? const <Account>[];
    final engine = AssistantEngine(
      container.read(movementRepositoryProvider),
      container.read(accountRepositoryProvider),
      container.read(budgetRepositoryProvider),
      currency,
      now,
    );

    final pending = _pending;
    final completed = pending == null ? null : _tryCompletePending(pending, text, expenseCats);
    final intent = completed ??
        _parser.parse(text, expenseCategories: expenseCats, incomeCategories: incomeCats, accounts: accounts, now: now);
    final result = await engine.answer(intent);

    if (!mounted) return;
    setState(() {
      _messages.add(_ChatMessage(result.text, fromUser: false));
      _pending = result.pending;
      _sending = false;
    });
    _scrollToEnd();

    // Crear/actualizar un presupuesto desde el chat puede cruzar un umbral con
    // datos que ya existían: se revisa igual que tras guardar un movimiento.
    if (result.pending == null) unawaited(checkBudgetAlerts(container));
  }

  /// Si el mensaje anterior dejó pendiente un solo dato ('amount' o
  /// 'category'), intenta sacarlo de este mensaje nuevo. Si no lo logra,
  /// `null`: la pantalla hará una interpretación normal por si el usuario
  /// cambió de tema.
  CreateAlertIntent? _tryCompletePending(PendingClarification pending, String text, List<Category> expenseCategories) {
    final normalized = normalize(text);
    if (pending.missing == 'amount') {
      final amount = extractAmountMinor(normalized);
      if (amount == null || amount <= 0) return null;
      return pending.template.copyWith(amountMinor: amount);
    }
    if (pending.missing == 'category') {
      for (final c in expenseCategories) {
        if (containsWord(normalized, normalize(c.name))) {
          return pending.template.copyWith(categoryId: c.id, categoryName: c.name);
        }
      }
    }
    return null;
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Asistente')),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.all(16),
                itemCount: _messages.length,
                itemBuilder: (context, i) => _Bubble(message: _messages[i]),
              ),
            ),
            if (_messages.length == 1)
              SizedBox(
                height: 40,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: [
                    for (final q in _quickReplies)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ActionChip(label: Text(q), onPressed: () => _send(q)),
                      ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      textCapitalization: TextCapitalization.sentences,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: const InputDecoration(hintText: 'Escribe tu pregunta…'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _sending ? null : () => _send(),
                    icon: _sending
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message});
  final _ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fromUser = message.fromUser;
    return Align(
      alignment: fromUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.8),
        decoration: BoxDecoration(
          color: fromUser ? scheme.primaryContainer : scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(message.text, style: TextStyle(color: fromUser ? scheme.onPrimaryContainer : scheme.onSurface)),
      ),
    );
  }
}
