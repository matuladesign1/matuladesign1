import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/settings.dart';
import '../core/theme.dart';
import '../data/plans.dart';
import '../data/user_repo.dart';
import 'notes_screen.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<Settings>();
    final user = context.watch<UserRepo>();
    final plans = context.watch<Plans>();
    final cs = Theme.of(context).colorScheme;
    final earned = user.earnedBadges();

    Widget stat(String value, String label) => Expanded(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Column(children: [
                Text(value, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: Brand.gold)),
                const SizedBox(height: 4),
                Text(label, textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
              ]),
            ),
          ),
        );

    return Scaffold(
      appBar: AppBar(title: Text(settings.s.t('profile'))),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Center(
          child: CircleAvatar(
            radius: 46,
            backgroundColor: Brand.royalBlue,
            child: Text(settings.userName.isEmpty ? '?' : settings.userName[0].toUpperCase(),
                style: const TextStyle(fontSize: 38, color: Brand.brightYellow, fontWeight: FontWeight.bold)),
          ),
        ),
        const SizedBox(height: 12),
        Center(
          child: Text(settings.userName.isEmpty ? settings.s.t('guest') : settings.userName,
              style: Theme.of(context).textTheme.headlineSmall),
        ),
        if (settings.userEmail.isNotEmpty) Center(child: Text(settings.userEmail, style: TextStyle(color: cs.onSurfaceVariant))),
        Center(child: Text('Membre depuis le ${settings.joinedAt}', style: TextStyle(color: cs.onSurfaceVariant))),
        Center(
          child: TextButton.icon(
            icon: const Icon(Icons.edit_outlined),
            label: const Text('Modifier le profil'),
            onPressed: () => _edit(context, settings),
          ),
        ),
        const SizedBox(height: 8),
        Row(children: [
          stat('${user.streak()}', 'jours consécutifs'),
          const SizedBox(width: 8),
          stat('${user.totalActiveDays()}', 'jours actifs'),
          const SizedBox(width: 8),
          stat('${user.countHistory('sermon')}', 'sermons consultés'),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          stat('${user.favorites(type: 'verse').length}', 'versets favoris'),
          const SizedBox(width: 8),
          stat('${user.countNotes()}', 'notes créées'),
          const SizedBox(width: 8),
          stat('${plans.completedPlans()}', 'plans terminés'),
        ]),
        const SizedBox(height: 24),
        Text('Badges', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        Wrap(spacing: 12, runSpacing: 12, children: [
          for (final b in UserRepo.badges) _Badge(days: b, earned: earned.contains(b)),
        ]),
        const SizedBox(height: 24),
        ListTile(
          leading: const Icon(Icons.edit_note_rounded),
          title: const Text('Mes notes, favoris et historique'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NotesScreen())),
        ),
        const SizedBox(height: 8),
        Text(
          'Compte invité : vos données restent sur cet appareil. La synchronisation entre appareils sera active dès que le serveur de comptes sera configuré.',
          style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
        ),
      ]),
    );
  }

  void _edit(BuildContext context, Settings settings) {
    final name = TextEditingController(text: settings.userName);
    final email = TextEditingController(text: settings.userEmail);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Profil'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, decoration: const InputDecoration(labelText: 'Nom')),
          const SizedBox(height: 12),
          TextField(controller: email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Adresse e-mail')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
          FilledButton(
            onPressed: () {
              settings.userName = name.text.trim();
              settings.userEmail = email.text.trim();
              Navigator.pop(context);
            },
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.days, required this.earned});
  final int days;
  final bool earned;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(children: [
      Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: earned
              ? const LinearGradient(colors: [Brand.brightYellow, Brand.gold], begin: Alignment.topLeft, end: Alignment.bottomRight)
              : null,
          color: earned ? null : cs.surfaceContainerHigh,
          border: Border.all(color: earned ? Brand.royalBlue : cs.outline, width: 3),
        ),
        child: Center(
          child: Text('$days',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: earned ? Brand.deepBlue : cs.onSurfaceVariant)),
        ),
      ),
      const SizedBox(height: 4),
      Text('jours', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
    ]);
  }
}
