import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/diet.dart';
import '../state/plan_controller.dart';

/// 三餐提前提醒设置：用餐时间 + 提前量。
/// 实际排程见 NotificationService._scheduleMeals。
class MealReminderSettingsPage extends StatefulWidget {
  const MealReminderSettingsPage({super.key});

  @override
  State<MealReminderSettingsPage> createState() =>
      _MealReminderSettingsPageState();
}

class _MealReminderSettingsPageState
    extends State<MealReminderSettingsPage> {
  late MealReminderSettings _settings;

  @override
  void initState() {
    super.initState();
    _settings = context.read<PlanController>().mealSettings;
  }

  int _hour(MealType type) => switch (type) {
        MealType.breakfast => _settings.breakfastHour,
        MealType.lunch => _settings.lunchHour,
        MealType.dinner => _settings.dinnerHour,
      };

  int _minute(MealType type) => switch (type) {
        MealType.breakfast => _settings.breakfastMinute,
        MealType.lunch => _settings.lunchMinute,
        MealType.dinner => _settings.dinnerMinute,
      };

  static String _two(int value) => value.toString().padLeft(2, '0');

  String _mealTimeLabel(MealType type) =>
      '${_two(_hour(type))}:${_two(_minute(type))}';

  /// 用固定日期计算提醒时刻，避免 DateTime.now() 带来的展示抖动。
  String _remindAtLabel(MealType type) {
    final at = _settings.remindAt(DateTime(2026, 1, 1), type);
    return '${_two(at.hour)}:${_two(at.minute)}';
  }

  Future<void> _pickTime(MealType type) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _hour(type), minute: _minute(type)),
    );
    if (picked == null) return;
    setState(() {
      switch (type) {
        case MealType.breakfast:
          _settings = _settings.copyWith(
              breakfastHour: picked.hour, breakfastMinute: picked.minute);
          break;
        case MealType.lunch:
          _settings = _settings.copyWith(
              lunchHour: picked.hour, lunchMinute: picked.minute);
          break;
        case MealType.dinner:
          _settings = _settings.copyWith(
              dinnerHour: picked.hour, dinnerMinute: picked.minute);
          break;
      }
    });
  }

  String _mealTimeTitle(AppLocalizations l, MealType type) => switch (type) {
        MealType.breakfast => l.mealBreakfastTime,
        MealType.lunch => l.mealLunchTime,
        MealType.dinner => l.mealDinnerTime,
      };

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final controller = context.read<PlanController>();

    return Scaffold(
      appBar: AppBar(title: Text(l.mealReminderSettings)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SwitchListTile(
            title: Text(l.mealReminderEnabled),
            subtitle: Text(l.mealNotice),
            value: _settings.enabled,
            onChanged: (v) =>
                setState(() => _settings = _settings.copyWith(enabled: v)),
          ),
          const Divider(),
          for (final type in MealType.values)
            ListTile(
              title: Text(_mealTimeTitle(l, type)),
              subtitle: Text('${l.mealRemindAt} ${_remindAtLabel(type)}'),
              trailing: Text(_mealTimeLabel(type),
                  style: Theme.of(context).textTheme.titleMedium),
              onTap: () => _pickTime(type),
            ),
          const Divider(),
          Text(l.mealLeadMinutes,
              style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          SegmentedButton<int>(
            segments: <int>[0, 5, 10, 15, 20, 30]
                .map((m) => ButtonSegment<int>(
                      value: m,
                      label: Text('$m ${l.minutes}'),
                    ))
                .toList(),
            selected: <int>{_settings.leadMinutes},
            onSelectionChanged: (Set<int> selected) => setState(() =>
                _settings =
                    _settings.copyWith(leadMinutes: selected.first)),
          ),
          const SizedBox(height: 20),
          OutlinedButton(
            onPressed: () => controller.ensurePermissions(),
            child: Text(l.requestPermission),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () async {
              await controller.updateMealSettings(_settings);
              if (!context.mounted) return;
              Navigator.of(context).pop();
            },
            child: Text(l.save),
          ),
          const SizedBox(height: 12),
          Text(l.batteryHint, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}
