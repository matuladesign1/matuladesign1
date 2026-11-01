import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/settings.dart';
import 'ask_screen.dart';
import 'audio_bar.dart';
import 'bible_screen.dart';
import 'home_screen.dart';
import 'plans_screen.dart';
import 'search_screen.dart';

/// Navigation inférieure fixe à cinq onglets.
class Shell extends StatefulWidget {
  const Shell({super.key});

  static final globalKey = GlobalKey<ShellState>();

  /// Accès à la navigation principale depuis n'importe quel écran, y compris
  /// les pages ouvertes par-dessus (elles sont refermées lors du changement d'onglet).
  static ShellState of(BuildContext context) => globalKey.currentState!;

  @override
  State<Shell> createState() => ShellState();
}

class ShellState extends State<Shell> {
  int index = 0;
  final askKey = GlobalKey<AskScreenState>();
  final bibleKey = GlobalKey<BibleScreenState>();
  final searchKey = GlobalKey<SearchScreenState>();

  void go(int i) {
    Navigator.of(context).popUntil((r) => r.isFirst);
    setState(() => index = i);
  }

  void ask(String question) {
    go(1);
    WidgetsBinding.instance.addPostFrameCallback((_) => askKey.currentState?.submit(question));
  }

  void openBible(int book, int chapter, {int? verse}) {
    go(3);
    WidgetsBinding.instance.addPostFrameCallback((_) => bibleKey.currentState?.open(book, chapter, verse: verse));
  }

  void openIndex() {
    go(2);
    WidgetsBinding.instance.addPostFrameCallback((_) => searchKey.currentState?.showIndex(true));
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<Settings>().s;
    return PopScope(
      canPop: index == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) go(0);
      },
      child: Scaffold(
        body: Column(children: [
          Expanded(
            child: IndexedStack(index: index, children: [
              const HomeScreen(),
              AskScreen(key: askKey),
              SearchScreen(key: searchKey),
              BibleScreen(key: bibleKey),
              const PlansScreen(),
            ]),
          ),
          const AudioBar(),
        ]),
        bottomNavigationBar: NavigationBar(
          selectedIndex: index,
          onDestinationSelected: go,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          destinations: [
            NavigationDestination(
                icon: const Icon(Icons.home_outlined), selectedIcon: const Icon(Icons.home_rounded), label: s.t('home')),
            NavigationDestination(
                icon: const Icon(Icons.forum_outlined), selectedIcon: const Icon(Icons.forum_rounded), label: s.t('ask')),
            NavigationDestination(
                icon: const Icon(Icons.search_rounded), selectedIcon: const Icon(Icons.manage_search_rounded), label: s.t('search')),
            NavigationDestination(
                icon: const Icon(Icons.menu_book_outlined), selectedIcon: const Icon(Icons.menu_book_rounded), label: s.t('bible')),
            NavigationDestination(
                icon: const Icon(Icons.event_note_outlined), selectedIcon: const Icon(Icons.event_note_rounded), label: s.t('plans')),
          ],
        ),
      ),
    );
  }
}
