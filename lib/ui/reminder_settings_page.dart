import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/plan.dart';
import '../services/notification_service.dart';
import '../state/plan_controller.dart';

class ReminderSettingsPage extends StatefulWidget {
  const ReminderSettingsPage({super.key});

  @override
  State<ReminderSettingsPage> createState() => _ReminderSettingsPageState();
}

class _ReminderSettingsPageState extends State<ReminderSettingsPage> {
  late ReminderSettings _settings;

  @override
  void initState() {
    super.initState();
    _settings = context.read<PlanController>().settings;
  }

  String _timeLabel() =>
      '${_settings.hour.toString().padLeft(2, '0')}:'
      '${_settings.minute.toString().padLeft(2, '0')}';

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime:
          TimeOfDay(hour: _settings.hour, minute: _settings.minute),
    );
    if (picked != null) {
      setState(() => _settings = _settings.copyWith(
            hour: picked.hour,
            minute: picked.minute,
          ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final controller = context.read<PlanController>();

    return Scaffold(
      appBar: AppBar(title: Text(l.reminderSettings)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SwitchListTile(
            title: Text(l.reminderEnabled),
            value: _settings.enabled,
            onChanged: (v) =>
                setState(() => _settings = _settings.copyWith(enabled: v)),
          ),
          ListTile(
            title: Text(l.reminderTime),
            trailing: Text(_timeLabel(),
                style: Theme.of(context).textTheme.titleMedium),
            onTap: _pickTime,
          ),
          SwitchListTile(
            title: Text(l.alarmMode),
            subtitle: Text(l.normalMode),
            value: _settings.alarmMode,
            onChanged: (v) =>
                setState(() => _settings = _settings.copyWith(alarmMode: v)),
          ),
          const Divider(),
          Text(l.snooze, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          SegmentedButton<int>(
            segments: [5, 10, 15, 30]
                .map((m) => ButtonSegment<int>(
                      value: m,
                      label: Text('$m ${l.minutes}'),
                    ))
                .toList(),
            selected: <int>{_settings.snoozeMinutes},
            onSelectionChanged: (Set<int> selected) => setState(() =>
                _settings =
                    _settings.copyWith(snoozeMinutes: selected.first)),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => controller.ensurePermissions(),
                  child: Text(l.requestPermission),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton(
                  onPressed: () =>
                      NotificationService.instance.openBatterySettings(),
                  child: Text(l.openBatterySettings),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () async {
              await controller.updateSettings(_settings);
              if (mounted) Navigator.of(context).pop();
            },
            child: Text(l.save),
          ),
          const SizedBox(height: 16),
          Text(l.batteryHint, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          Text(l.permissionBody, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}
