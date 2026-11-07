import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/diet.dart';
import '../models/plan.dart';
import '../services/activity_sensing_service.dart';
import '../state/plan_controller.dart';
import 'diet_page.dart';
import 'plan_setup_page.dart';
import 'reminder_settings_page.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = context.watch<PlanController>();

    // 点击三餐通知进入 App 时，自动打开饮食页并清掉待处理标记。
    if (c.focusMealKey != null &&
        (ModalRoute.of(context)?.isCurrent ?? false)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        c.clearFocus();
        Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const DietPage()),
        );
      });
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(l.appTitle),
        actions: [
          IconButton(
            tooltip: l.dietTitle,
            icon: const Icon(Icons.restaurant_menu),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const DietPage()),
            ),
          ),
          IconButton(
            tooltip: l.reminderSettings,
            icon: const Icon(Icons.alarm),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                  builder: (_) => const ReminderSettingsPage()),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const PlanSetupPage()),
        ),
        label: Text(l.setupPlan),
        icon: const Icon(Icons.edit_calendar),
      ),
      body: !c.ready
          ? const Center(child: CircularProgressIndicator())
          : c.plan == null
              ? _EmptyState(l: l)
              : _PlanView(c: c, l: l),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.l});

  final AppLocalizations l;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.route_outlined, size: 64, color: Colors.teal),
              const SizedBox(height: 16),
              Text(l.noPlan, textAlign: TextAlign.center),
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

class _PlanView extends StatelessWidget {
  const _PlanView({required this.c, required this.l});

  final PlanController c;
  final AppLocalizations l;

  @override
  Widget build(BuildContext context) {
    final plan = c.plan!;
    final task = c.todayTask;
    final rate = (plan.completedDays / plan.days).clamp(0.0, 1.0);
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: [
        Text(l.planTitle, style: theme.textTheme.headlineSmall),
        const SizedBox(height: 12),
        _ProgressCard(l: l, plan: plan, rate: rate),
        const SizedBox(height: 12),
        _DietOverviewCard(c: c, l: l),
        const SizedBox(height: 16),
        Text(l.todayTask, style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        if (task == null)
          Card(child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(l.noPlan),
          ))
        else
          _TaskCard(c: c, l: l, task: task),
        const SizedBox(height: 16),
        _SensingCard(c: c, l: l),
        const SizedBox(height: 16),
        if (task != null && !task.isDone)
          FilledButton.icon(
            onPressed: () => c.checkIn(
              task.id,
              source: c.verdict.detected ? 'sensor' : 'manual',
            ),
            icon: const Icon(Icons.check_circle_outline),
            label: Text(l.checkIn),
          ),
        const SizedBox(height: 16),
        Text(
          l.batteryHint,
          style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        Text(
          l.disclaimer,
          style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _DietOverviewCard extends StatelessWidget {
  const _DietOverviewCard({required this.c, required this.l});

  final PlanController c;
  final AppLocalizations l;

  @override
  Widget build(BuildContext context) {
    final log = c.dietLog;
    if (log == null) return const SizedBox.shrink();
    final stats = log.stats();
    final today = DateTime.now();
    final followedToday = MealType.values
        .where((type) =>
            log.recordOn(today, type)?.status == MealStatus.followed)
        .length;

    return Card(
      child: ListTile(
        leading: const Icon(Icons.restaurant_outlined),
        title: Text(l.dietTitle),
        subtitle: Text('${l.dietTodayMeals} $followedToday/3 · '
            '${l.dietFollowedDays} ${stats.followedDays} ${l.days} · '
            '${l.dietOffPlanDays} ${stats.offPlanDays} ${l.days}'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const DietPage()),
        ),
      ),
    );
  }
}

class _ProgressCard extends StatelessWidget {
  const _ProgressCard(
      {required this.l, required this.plan, required this.rate});

  final AppLocalizations l;
  final WeightPlan plan;
  final double rate;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(l.progress),
                  Text('${plan.completedDays} / ${plan.days} ${l.days}'),
                ],
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(value: rate),
              const SizedBox(height: 12),
              Text(
                '${plan.startWeightKg.toStringAsFixed(1)} kg → '
                '${plan.targetWeightKg.toStringAsFixed(1)} kg',
              ),
              const SizedBox(height: 4),
              Text(l.weightCurve,
                  style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      );
}

class _TaskCard extends StatelessWidget {
  const _TaskCard({required this.c, required this.l, required this.task});

  final PlanController c;
  final AppLocalizations l;
  final DailyTask task;

  String _title(AppLocalizations l) => switch (task.kind) {
        TaskKind.cardio => l.taskCardio,
        TaskKind.strength => l.taskStrength,
        TaskKind.diet => l.taskDiet,
        TaskKind.weighIn => l.taskWeighIn,
        TaskKind.rest => l.taskRest,
      };

  @override
  Widget build(BuildContext context) => Card(
        color: task.isDone
            ? Theme.of(context).colorScheme.secondaryContainer
            : null,
        child: ListTile(
          leading: Icon(task.isDone ? Icons.check_circle : Icons.directions_run),
          title: Text(_title(l)),
          subtitle: Text(
            '${task.targetMinutes} ${l.minutes}'
            '${task.targetSteps > 0 ? ' · ${task.targetSteps} ${l.steps}' : ''}',
          ),
          trailing: task.isDone ? Text(l.checkInDone) : null,
        ),
      );
}

class _SensingCard extends StatelessWidget {
  const _SensingCard({required this.c, required this.l});

  final PlanController c;
  final AppLocalizations l;

  String _text(AppLocalizations l) {
    final v = c.verdict;
    if (v.reasonCode == 'unavailable') return l.sensorUnavailable;
    if (v.detected) return l.sensorDetected;
    if (v.state == MotionState.walking) return l.walking;
    return l.still;
  }

  @override
  Widget build(BuildContext context) {
    final v = c.verdict;
    return Card(
      child: ListTile(
        leading: Icon(
          v.detected ? Icons.sensors : Icons.sensors_off,
          color: v.detected ? Colors.teal : null,
        ),
        title: Text(_text(l)),
        subtitle: Text('${v.stepsInWindow} ${l.steps} · ${v.reasonCode}'),
        trailing: c.permissions?.allGranted == false
            ? IconButton(
                tooltip: l.permissionTitle,
                icon: const Icon(Icons.lock_open),
                onPressed: () => c.ensurePermissions(),
              )
            : null,
      ),
    );
  }
}
