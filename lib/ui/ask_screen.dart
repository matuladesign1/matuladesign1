import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/settings.dart';
import '../core/theme.dart';
import '../data/ai_service.dart';
import 'search_screen.dart';

class _Turn {
  _Turn(this.question);
  final String question;
  AiAnswer? answer;
  bool loading = true;
}

/// « Demander » : assistant conversationnel adossé à une recherche réelle.
class AskScreen extends StatefulWidget {
  const AskScreen({super.key});
  @override
  State<AskScreen> createState() => AskScreenState();
}

class AskScreenState extends State<AskScreen> {
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  final _turns = <_Turn>[];

  static const examples = [
    'Que dit Branham sur le retour du Seigneur ?',
    'Dans quel sermon parle-t-il de l\'Aigle ?',
    'Où trouve-t-on l\'expression « le temps de la fin » ?',
    'Quels sermons parlent des Sept Sceaux ?',
    'Que dit la Bible sur la nouvelle naissance ?',
    'Trouve les passages concernant la Colombe.',
  ];

  @override
  void dispose() {
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> submit(String q) async {
    q = q.trim();
    if (q.isEmpty) return;
    _ctrl.clear();
    final turn = _Turn(q);
    setState(() => _turns.add(turn));
    _toBottom();
    final ai = context.read<AiService>();
    try {
      turn.answer = await ai.ask(q);
    } catch (e) {
      turn.answer = AiAnswer('', const [], error: '$e');
    }
    if (!mounted) return;
    setState(() => turn.loading = false);
    _toBottom();
  }

  void _toBottom() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.animateTo(_scroll.position.maxScrollExtent,
              duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
        }
      });

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<Settings>();
    final s = settings.s;
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.auto_awesome, color: Brand.gold, size: 20),
          const SizedBox(width: 8),
          Text(s.t('ask')),
        ]),
        actions: [
          if (_turns.isNotEmpty)
            IconButton(
                tooltip: 'Nouvelle conversation',
                onPressed: () => setState(_turns.clear),
                icon: const Icon(Icons.add_comment_outlined)),
        ],
      ),
      body: Column(children: [
        Expanded(
          child: _turns.isEmpty
              ? ListView(padding: const EdgeInsets.all(20), children: [
                  Text(s.t('aiTitle'), style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 8),
                  Text(
                      'Chaque réponse s\'appuie sur une recherche réelle dans votre bibliothèque et la Bible, avec le titre, le numéro, le paragraphe et la citation exacte. Aucune citation n\'est inventée.',
                      style: TextStyle(color: cs.onSurfaceVariant, height: 1.4)),
                  if (!settings.hasServer) ...[
                    const SizedBox(height: 12),
                    Card(
                      color: cs.secondaryContainer,
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Text(
                            'Serveur IA non configuré : l\'assistant fonctionne en mode recherche locale (passages exacts, sans synthèse).',
                            style: TextStyle(color: cs.onSecondaryContainer)),
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  for (final e in examples)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                            alignment: Alignment.centerLeft,
                            padding: const EdgeInsets.all(14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                        onPressed: () => submit(e),
                        child: Text(e, style: TextStyle(color: cs.onSurface)),
                      ),
                    ),
                ])
              : ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  itemCount: _turns.length,
                  itemBuilder: (_, i) => _TurnView(turn: _turns[i]),
                ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
            child: TextField(
              controller: _ctrl,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              onSubmitted: submit,
              decoration: InputDecoration(
                hintText: s.t('askHint'),
                suffixIcon: IconButton(icon: const Icon(Icons.send_rounded), onPressed: () => submit(_ctrl.text)),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

class _TurnView extends StatelessWidget {
  const _TurnView({required this.turn});
  final _Turn turn;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final a = turn.answer;
    final s = context.read<Settings>().s;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.only(left: 48, bottom: 12),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(color: Brand.royalBlue, borderRadius: BorderRadius.circular(18)),
          child: Text(turn.question, style: const TextStyle(color: Colors.white, fontSize: 16)),
        ),
      ),
      if (turn.loading)
        const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()))
      else if (a != null) ...[
        if (a.error != null)
          Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(a.error!, style: TextStyle(color: cs.error))),
        if (a.sources.isEmpty)
          Text(s.t('noReliable'), style: const TextStyle(fontSize: 16))
        else ...[
          if (a.text.isNotEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: SelectableText(a.text, style: const TextStyle(fontSize: 16, height: 1.5)),
              ),
            )
          else
            Text(a.offline ? s.t('aiOffline') : '', style: TextStyle(color: cs.onSurfaceVariant, height: 1.4)),
          const SizedBox(height: 8),
          for (final (i, h) in a.sources.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: HitCard(hit: h, index: a.text.isNotEmpty ? i + 1 : null),
            ),
        ],
      ],
      const SizedBox(height: 16),
    ]);
  }
}
