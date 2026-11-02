import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/settings.dart';
import '../core/theme.dart';
import '../data/db.dart';
import '../data/plans.dart';
import '../main.dart';
import 'library_screen.dart';
import 'sermon_reader.dart';
import 'shell.dart';
import 'widgets.dart';

class PlansScreen extends StatefulWidget {
  const PlansScreen({super.key});
  @override
  State<PlansScreen> createState() => _PlansScreenState();
}

class _PlansScreenState extends State<PlansScreen> {
  bool mineTab = false;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<Settings>().s;
    final plans = context.watch<Plans>();
    context.watch<LibraryState>();
    final adb = context.read<AppDb>();
    final cs = Theme.of(context).colorScheme;

    Widget tab(bool v, IconData icon, String label) => Expanded(
          child: InkWell(
            onTap: () => setState(() => mineTab = v),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: mineTab == v ? Theme.of(context).colorScheme.primary : cs.outlineVariant, width: mineTab == v ? 3 : 1))),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(icon, size: 20, color: mineTab == v ? Theme.of(context).colorScheme.primary : cs.onSurfaceVariant),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(label,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(letterSpacing: 1.5, color: mineTab == v ? Theme.of(context).colorScheme.primary : cs.onSurfaceVariant)),
                ),
              ]),
            ),
          ),
        );

    final mine = plans.mine();
    final yearCounts = adb.yearCounts();
    final seriesCounts = adb.seriesCounts();

    return SafeArea(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Text(s.t('plans'), style: Theme.of(context).textTheme.headlineMedium!.copyWith(fontWeight: FontWeight.w700)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [
            tab(true, Icons.radio_button_unchecked, s.t('myPlans')),
            tab(false, Icons.explore_outlined, s.t('findPlans')),
          ]),
        ),
        Expanded(
          child: mineTab
              ? (mine.isEmpty
                  ? EmptyState(
                      icon: Icons.event_note_outlined,
                      title: 'Aucun plan en cours',
                      message: 'Choisissez un programme dans « Trouver des plans ».',
                      action: FilledButton(onPressed: () => setState(() => mineTab = false), child: const Text('Trouver des plans')),
                    )
                  : ListView(padding: const EdgeInsets.all(16), children: [
                      for (final p in mine) Padding(padding: const EdgeInsets.only(bottom: 12), child: _PlanTile(plan: p)),
                    ]))
              : ListView(padding: const EdgeInsets.only(bottom: 24), children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: SizedBox(
                      height: 200,
                      child: GestureDetector(
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LibraryScreen())),
                        child: Landscape(
                          variant: 4,
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.end, children: [
                              Text(s.t('allSermons'),
                                  style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w700)),
                              Text(s.t('sermonsCount', n: adb.sermonCount()),
                                  style: const TextStyle(color: Colors.white70, fontSize: 17)),
                            ]),
                          ),
                        ),
                      ),
                    ),
                  ),
                  SectionTitle('Programmes de lecture'),
                  for (final p in plans.all.where((p) => p.series == null))
                    Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 12), child: _PlanTile(plan: p)),
                  SectionTitle(s.t('series'),
                      action: s.t('seeAll'),
                      onAction: () => Navigator.push(
                          context, MaterialPageRoute(builder: (_) => const LibraryScreen(initialGroup: 'series')))),
                  SizedBox(
                    height: 210,
                    child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), children: [
                      for (final p in plans.all.where((p) => p.series != null))
                        _SeriesCard(
                          title: p.series!,
                          subtitle: seriesCounts[p.series] == null
                              ? 'À importer'
                              : '${seriesCounts[p.series]} prédications',
                          variant: p.palette,
                          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PlanDetail(planId: p.id))),
                        ),
                    ]),
                  ),
                  SectionTitle(s.t('yearByYear'),
                      action: s.t('seeAll'),
                      onAction: () => Navigator.push(
                          context, MaterialPageRoute(builder: (_) => const LibraryScreen(initialGroup: 'year')))),
                  SizedBox(
                    height: 210,
                    child: yearCounts.isEmpty
                        ? Center(child: Text('Les années apparaîtront après l\'import des prédications.', style: TextStyle(color: cs.onSurfaceVariant)))
                        : ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), children: [
                            for (final e in yearCounts.entries)
                              _SeriesCard(
                                title: '${e.key}',
                                subtitle: '${e.value} prédications',
                                variant: e.key,
                                onTap: () => Navigator.push(
                                    context, MaterialPageRoute(builder: (_) => LibraryScreen(year: e.key))),
                              ),
                          ]),
                  ),
                ]),
        ),
      ]),
    );
  }
}

class _SeriesCard extends StatelessWidget {
  const _SeriesCard({required this.title, required this.subtitle, required this.variant, required this.onTap});
  final String title, subtitle;
  final int variant;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: SizedBox(
          width: 170,
          child: GestureDetector(
            onTap: onTap,
            child: Landscape(
              variant: variant,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.end, children: [
                  Text(title,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w700, height: 1.2)),
                  const SizedBox(height: 6),
                  Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70)),
                ]),
              ),
            ),
          ),
        ),
      );
}

class _PlanTile extends StatelessWidget {
  const _PlanTile({required this.plan});
  final PlanDef plan;

  @override
  Widget build(BuildContext context) {
    final plans = context.watch<Plans>();
    final st = plans.state(plan.id);
    final cs = Theme.of(context).colorScheme;
    final progress = st == null || plan.days.isEmpty ? 0.0 : st.done.length / plan.days.length;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PlanDetail(planId: plan.id))),
        child: Row(children: [
          SizedBox(width: 96, height: 112, child: Landscape(variant: plan.palette, radius: 0)),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(plan.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text('${plan.days.length} jours${st == null ? '' : st.paused ? ' · en pause' : ' · en cours'}',
                    style: TextStyle(color: cs.onSurfaceVariant)),
                if (st != null) ...[
                  const SizedBox(height: 8),
                  LinearProgressIndicator(value: progress, color: Brand.gold, borderRadius: BorderRadius.circular(4)),
                  const SizedBox(height: 4),
                  Text('${(progress * 100).round()} %', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                ],
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

class PlanDetail extends StatelessWidget {
  const PlanDetail({super.key, required this.planId});
  final String planId;

  @override
  Widget build(BuildContext context) {
    final plans = context.watch<Plans>();
    final plan = plans.byId(planId);
    final st = plans.state(planId);
    final cs = Theme.of(context).colorScheme;
    final nextDay = st == null ? 0 : List.generate(plan.days.length, (i) => i + 1).firstWhere((d) => !st.done.contains(d), orElse: () => 0);
    return Scaffold(
      body: CustomScrollView(slivers: [
        SliverAppBar(
          expandedHeight: 200,
          pinned: true,
          flexibleSpace: FlexibleSpaceBar(
            title: Text(plan.title, style: const TextStyle(color: Colors.white, fontSize: 16)),
            background: Landscape(variant: plan.palette, radius: 0),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(plan.description, style: const TextStyle(fontSize: 16, height: 1.4)),
              const SizedBox(height: 12),
              Wrap(spacing: 16, runSpacing: 4, children: [
                Text('${plan.days.length} jours', style: TextStyle(color: cs.onSurfaceVariant)),
                if (st != null) Text('Commencé le ${st.startedAt.substring(0, 10)}', style: TextStyle(color: cs.onSurfaceVariant)),
                if (st?.lastReadAt != null)
                  Text('Dernière lecture : ${st!.lastReadAt!.substring(0, 10)}', style: TextStyle(color: cs.onSurfaceVariant)),
                if (st != null)
                  Text('Progression : ${st.done.length}/${plan.days.length}', style: TextStyle(color: cs.onSurfaceVariant)),
              ]),
              const SizedBox(height: 16),
              if (plan.days.isEmpty)
                Text('Ce plan s\'activera quand les prédications de la série seront importées.',
                    style: TextStyle(color: cs.onSurfaceVariant))
              else if (st == null)
                FilledButton.icon(
                    onPressed: () => plans.start(planId), icon: const Icon(Icons.play_arrow_rounded), label: const Text('Commencer'))
              else
                Wrap(spacing: 8, children: [
                  if (st.paused)
                    FilledButton.icon(
                        onPressed: () => plans.pause(planId, false),
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: const Text('Reprendre'))
                  else
                    OutlinedButton.icon(
                        onPressed: () => plans.pause(planId, true), icon: const Icon(Icons.pause_rounded), label: const Text('Suspendre')),
                  TextButton(
                    onPressed: () async {
                      final ok = await showDialog<bool>(
                          context: context,
                          builder: (_) => AlertDialog(
                                title: const Text('Abandonner ce plan ?'),
                                content: const Text('La progression sera effacée.'),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
                                  FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Abandonner')),
                                ],
                              ));
                      if (ok == true) plans.stop(planId);
                    },
                    child: const Text('Abandonner'),
                  ),
                ]),
            ]),
          ),
        ),
        SliverList.builder(
          itemCount: plan.days.length,
          itemBuilder: (_, i) {
            final day = i + 1;
            final done = st?.done.contains(day) ?? false;
            final readings = plan.days[i];
            return ListTile(
              leading: CircleAvatar(
                backgroundColor: done ? Brand.gold : (day == nextDay ? cs.primaryContainer : cs.surfaceContainerHigh),
                child: done ? const Icon(Icons.check, color: Brand.black) : Text('$day'),
              ),
              title: Text(readings.isEmpty ? 'Jour de rattrapage' : readings.map((r) => r.label).join(', '),
                  maxLines: 2, overflow: TextOverflow.ellipsis),
              subtitle: Text('Jour $day'),
              trailing: st == null ? null : Checkbox(value: done, onChanged: (_) => plans.toggleDay(planId, day)),
              onTap: readings.isEmpty ? null : () => _openReading(context, plans, readings.first),
            );
          },
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 40)),
      ]),
    );
  }

  void _openReading(BuildContext context, Plans plans, Reading r) {
    if (r.sermonCode != null) {
      final s = plans.sermonFor(r);
      if (s != null) Navigator.push(context, MaterialPageRoute(builder: (_) => SermonReader(sermonId: s.id)));
    } else {
      Shell.of(context).openBible(r.book, r.chapter);
    }
  }
}
