import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/diet.dart';
import '../services/diet_engine.dart';
import '../services/diet_presets.dart';
import '../state/plan_controller.dart';
import 'meal_reminder_settings_page.dart';
import 'plan_setup_page.dart';

String _mealLabel(AppLocalizations l, MealType type) => switch (type) {
      MealType.breakfast => l.mealBreakfast,
      MealType.lunch => l.mealLunch,
      MealType.dinner => l.mealDinner,
    };

IconData _mealIcon(MealType type) => switch (type) {
      MealType.breakfast => Icons.wb_sunny_outlined,
      MealType.lunch => Icons.restaurant,
      MealType.dinner => Icons.nightlight_round,
    };

String _mealStatusText(AppLocalizations l, MealStatus status) =>
    switch (status) {
      MealStatus.pending => l.mealPending,
      MealStatus.followed => l.mealFollowed,
      MealStatus.replaced => l.mealReplaced,
      MealStatus.skipped => l.mealSkipped,
    };

String _dayStatusText(AppLocalizations l, DietDayStatus status) =>
    switch (status) {
      DietDayStatus.full => l.mealStatusFull,
      DietDayStatus.partial => l.mealStatusPartial,
      DietDayStatus.offPlan => l.mealStatusOffPlan,
      DietDayStatus.noRecord => l.mealStatusNoRecord,
      DietDayStatus.future => l.mealStatusFuture,
    };

Color _dayColor(DietDayStatus status, ColorScheme cs) => switch (status) {
      DietDayStatus.full => Colors.green.shade600,
      DietDayStatus.partial => Colors.orange.shade700,
      DietDayStatus.offPlan => Colors.red.shade500,
      DietDayStatus.noRecord => Colors.red.shade300,
      DietDayStatus.future => cs.outlineVariant,
    };

void _showDayDetail(
  BuildContext context, {
  required AppLocalizations l,
  required DietLog log,
  required DietPreset preset,
  required DateTime day,
  required String lang,
}) {
  showModalBottomSheet<void>(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${l.dietDayDetail} · ${DietLog.dateKey(day)}',
                style: Theme.of(sheetContext).textTheme.titleMedium),
            const SizedBox(height: 8),
            for (final type in MealType.values)
              ListTile(
                dense: true,
                leading: Icon(_mealIcon(type)),
                title: Text(preset.mealOn(day, type).name(lang)),
                subtitle: Text(_mealLabel(l, type)),
                trailing: Text(_mealStatusText(
                    l, log.recordOn(day, type)?.status ?? MealStatus.pending)),
              ),
          ],
        ),
      ),
    ),
  );
}

/// 饮食计划主页：今日三餐打卡 + 按计划/未按计划天数统计 + 执行日历。
class DietPage extends StatelessWidget {
  const DietPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = context.watch<PlanController>();
    final log = c.dietLog;

    return Scaffold(
      appBar: AppBar(
        title: Text(l.dietTitle),
        actions: [
          IconButton(
            tooltip: l.mealReminderSettings,
            icon: const Icon(Icons.alarm),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                  builder: (_) => const MealReminderSettingsPage()),
            ),
          ),
        ],
      ),
      body: log == null
          ? _DietEmpty(l: l)
          : _DietBody(c: c, log: log, l: l),
    );
  }
}

class _DietEmpty extends StatelessWidget {
  const _DietEmpty({super.key, required this.l});

  final AppLocalizations l;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.restaurant_menu, size: 64, color: Colors.teal),
              const SizedBox(height: 16),
              Text(l.dietNoDietLog, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                      builder: (_) => const PlanSetupPage()),
                ),
                icon: const Icon(Icons.add),
                label: Text(l.setupPlan),
              ),
            ],
          ),
        ),
      );
}

class _DietBody extends StatelessWidget {
  const _DietBody({
    super.key,
    required this.c,
    required this.log,
    required this.l,
  });

  final PlanController c;
  final DietLog log;
  final AppLocalizations l;

  @override
  Widget build(BuildContext context) {
    final lang = Localizations.localeOf(context).languageCode;
    final preset = const DietEngine().preset(log.presetId);
    final stats = log.stats();
    final today = DateTime.now();
    final theme = Theme.of(context);
    final dates = List<DateTime>.generate(
      log.days,
      (i) => DateTime(log.startDate.year, log.startDate.month,
          log.startDate.day + i),
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      children: [
        if (c.focusMealKey != null)
          Card(
            color: theme.colorScheme.tertiaryContainer,
            child: ListTile(
              leading: const Icon(Icons.notifications_active),
              title: Text('${l.dietNoteFromNotification}: ${c.focusMealKey}'),
              trailing: IconButton(
                tooltip: l.close,
                icon: const Icon(Icons.close),
                onPressed: c.clearFocus,
              ),
            ),
          ),
        _PresetCard(l: l, lang: lang, log: log, preset: preset),
        const SizedBox(height: 12),
        _StatsCard(l: l, stats: stats),
        const SizedBox(height: 20),
        Text(l.dietTodayMeals, style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        for (final type in MealType.values)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _MealCard(
              c: c,
              l: l,
              lang: lang,
              log: log,
              preset: preset,
              day: today,
              type: type,
            ),
          ),
        const SizedBox(height: 12),
        Text(l.dietCalendar, style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(l.dietStatsNote, style: theme.textTheme.bodySmall),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: <Widget>[
                for (final day in dates)
                  _DayCell(
                    summary: log.summaryOn(day),
                    label:
                        '${DietLog.dateKey(day)} · ${_dayStatusText(l, log.summaryOn(day).status)}',
                    onTap: () => _showDayDetail(context,
                        l: l,
                        log: log,
                        preset: preset,
                        day: day,
                        lang: lang),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        Text(l.dietOffPlanList, style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        _OffPlanList(l: l, stats: stats),
        const SizedBox(height: 20),
        Text(l.dietDisclaimer, style: theme.textTheme.bodySmall),
      ],
    );
  }
}

class _PresetCard extends StatelessWidget {
  const _PresetCard({
    super.key,
    required this.l,
    required this.lang,
    required this.log,
    required this.preset,
  });

  final AppLocalizations l;
  final String lang;
  final DietLog log;
  final DietPreset preset;

  @override
  Widget build(BuildContext context) => Card(
        child: ListTile(
          leading: const Icon(Icons.restaurant_outlined),
          title: Text('${l.dietPresetLabel}: ${preset.name(lang)}'),
          subtitle: Text('${preset.description(lang)}\n'
              '${DietLog.dateKey(log.startDate)} → ${DietLog.dateKey(log.endDate)}'),
          isThreeLine: true,
        ),
      );
}

class _Metric extends StatelessWidget {
  const _Metric({
    super.key,
    required this.label,
    required this.value,
    required this.color,
    this.large = false,
  });

  final String label;
  final int value;
  final Color color;
  final bool large;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$value',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: color,
                    fontWeight: FontWeight.bold,
                    fontSize: large ? 28 : null,
                  )),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      );
}

class _StatsCard extends StatelessWidget {
  const _StatsCard({super.key, required this.l, required this.stats});

  final AppLocalizations l;
  final DietStats stats;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l.dietStatsTitle,
                  style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _Metric(
                    label: l.dietFollowedDays,
                    value: stats.followedDays,
                    color: Colors.green.shade700,
                    large: true,
                  ),
                  _Metric(
                    label: l.dietOffPlanDays,
                    value: stats.offPlanDays,
                    color: Colors.red.shade600,
                    large: true,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              LinearProgressIndicator(value: stats.followedRate),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _Metric(
                      label: l.dietPartialDays,
                      value: stats.partialDays,
                      color: Colors.orange.shade800),
                  _Metric(
                      label: l.dietStreak,
                      value: stats.currentStreak,
                      color: Theme.of(context).colorScheme.primary),
                  _Metric(
                      label: l.dietElapsedDays,
                      value: stats.elapsedDays,
                      color:
                          Theme.of(context).colorScheme.onSurfaceVariant),
                ],
              ),
              const SizedBox(height: 12),
              Text(l.dietStatsNote,
                  style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      );
}

class _MealCard extends StatelessWidget {
  const _MealCard({
    super.key,
    required this.c,
    required this.l,
    required this.lang,
    required this.log,
    required this.preset,
    required this.day,
    required this.type,
  });

  final PlanController c;
  final AppLocalizations l;
  final String lang;
  final DietLog log;
  final DietPreset preset;
  final DateTime day;
  final MealType type;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final meal = preset.mealOn(day, type);
    final status = log.recordOn(day, type)?.status ?? MealStatus.pending;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(_mealIcon(type), size: 20),
                const SizedBox(width: 8),
                Text(_mealLabel(l, type),
                    style: theme.textTheme.titleSmall),
                const Spacer(),
                Chip(
                  label: Text(_mealStatusText(l, status)),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(meal.name(lang), style: theme.textTheme.bodyLarge),
            const SizedBox(height: 4),
            Text(meal.note(lang), style: theme.textTheme.bodySmall),
            const SizedBox(height: 4),
            Text('${l.mealKcalHint}: ${meal.kcalRange} kcal',
                style: theme.textTheme.bodySmall),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: <Widget>[
                FilledButton.tonalIcon(
                  onPressed: () => c.recordMeal(
                      day, type, MealStatus.followed),
                  icon: Icon(status == MealStatus.followed
                      ? Icons.check_circle
                      : Icons.check_circle_outline),
                  label: Text(l.mealFollowedBtn),
                ),
                OutlinedButton(
                  onPressed: () => c.recordMeal(
                      day, type, MealStatus.replaced),
                  child: Text(l.mealReplacedBtn),
                ),
                TextButton(
                  onPressed: () => c.recordMeal(
                      day, type, MealStatus.skipped),
                  child: Text(l.mealSkippedBtn),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    super.key,
    required this.summary,
    required this.label,
    required this.onTap,
  });

  final DietDaySummary summary;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = _dayColor(summary.status, cs);
    final isFuture = summary.status == DietDayStatus.future;
    return Tooltip(
      message: label,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isFuture ? null : color,
            border: Border.all(color: color),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '${summary.date.day}',
            style: TextStyle(
              fontSize: 12,
              color: isFuture ? cs.onSurfaceVariant : Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

class _OffPlanList extends StatelessWidget {
  const _OffPlanList({super.key, required this.l, required this.stats});

  final AppLocalizations l;
  final DietStats stats;

  @override
  Widget build(BuildContext context) {
    final items = stats.offPlanSummaries;
    if (items.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Icon(Icons.emoji_events_outlined, color: Colors.teal),
              const SizedBox(width: 12),
              Expanded(child: Text(l.dietNoOffPlan)),
            ],
          ),
        ),
      );
    }

    final shown = items.take(30).toList();
    return Card(
      child: Column(
        children: <Widget>[
          for (final summary in shown)
            ListTile(
              dense: true,
              leading: Icon(
                Icons.event_busy_outlined,
                color: _dayColor(summary.status, Theme.of(context).colorScheme),
              ),
              title: Text(DietLog.dateKey(summary.date)),
              subtitle: Text('${_dayStatusText(l, summary.status)} · '
                  '${summary.followedMeals}/3 ${l.mealFollowed}'),
              trailing: Text('${summary.recordedMeals}/3'),
            ),
          if (items.length > shown.length)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text('+${items.length - shown.length} ${l.days}'),
            ),
        ],
      ),
    );
  }
}
