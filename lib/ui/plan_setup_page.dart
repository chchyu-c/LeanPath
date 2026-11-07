import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../services/diet_engine.dart';
import '../services/plan_engine.dart';
import '../state/plan_controller.dart';

class PlanSetupPage extends StatefulWidget {
  const PlanSetupPage({super.key});

  @override
  State<PlanSetupPage> createState() => _PlanSetupPageState();
}

class _PlanSetupPageState extends State<PlanSetupPage> {
  final _formKey = GlobalKey<FormState>();
  final _start = TextEditingController(text: '70');
  final _target = TextEditingController(text: '64');
  final _days = TextEditingController(text: '56');
  final _steps = TextEditingController(text: '6000');

  final DietEngine _dietEngine = const DietEngine();

  /// 用户手动选过方案后，不再随表单输入自动改推荐。
  bool _dietManuallyChanged = false;
  String? _selectedPresetId;

  @override
  void initState() {
    super.initState();
    for (final controller in <TextEditingController>[
      _start,
      _target,
      _days,
      _steps
    ]) {
      controller.addListener(_onFieldChanged);
    }
  }

  void _onFieldChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    for (final controller in <TextEditingController>[
      _start,
      _target,
      _days,
      _steps
    ]) {
      controller.removeListener(_onFieldChanged);
      controller.dispose();
    }
    super.dispose();
  }

  double? _num(String raw) => double.tryParse(raw.trim());

  /// 表单尚未填完时给防御式默认值，保证推荐卡片永远有内容可展示。
  DietRecommendation _recommendation() {
    final start = _num(_start.text) ?? 70;
    final rawTarget = _num(_target.text) ?? 64;
    final target = rawTarget >= start ? start - 1 : rawTarget;
    final days = (int.tryParse(_days.text.trim()) ?? 56).clamp(7, 3650);
    final steps = (int.tryParse(_steps.text.trim()) ?? 6000).clamp(1000, 100000);
    return _dietEngine.recommend(PlanInput(
      startDate: DateTime.now(),
      days: days,
      startWeightKg: start,
      targetWeightKg: target,
      baseStepGoal: steps,
    ));
  }

  String get _effectivePresetId => _dietManuallyChanged
      ? (_selectedPresetId ?? DietEngine.defaultPresetId)
      : _recommendation().presetId;

  String _reasonText(AppLocalizations l, DietReason reason) => switch (reason) {
        DietReason.intensive => l.dietReasonIntensive,
        DietReason.gentle => l.dietReasonGentle,
        DietReason.balanced => l.dietReasonBalanced,
      };

  Future<void> _submit(AppLocalizations l) async {
    if (!_formKey.currentState!.validate()) return;
    final controller = context.read<PlanController>();
    await controller.createPlan(PlanInput(
      startDate: DateTime.now(),
      days: int.parse(_days.text.trim()),
      startWeightKg: _num(_start.text)!,
      targetWeightKg: _num(_target.text)!,
      baseStepGoal: int.parse(_steps.text.trim()),
      dietPresetId: _effectivePresetId,
    ));
    if (!mounted) return;
    if (controller.error != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(controller.error!)));
      return;
    }
    // 申请权限前先说明目的（个保法：告知 + 单独同意 + 时机合理）。
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l.permissionTitle),
        content: Text(l.permissionBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l.later),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.of(dialogContext).pop();
              await controller.ensurePermissions();
            },
            child: Text(l.agreeAndEnable),
          ),
        ],
      ),
    );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    final recommendation = _recommendation();
    final selectedId = _effectivePresetId;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l.setupPlan)),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _start,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: l.startWeight),
              validator: (v) => (_num(v ?? '') ?? 0) <= 0 ? l.invalidValue : null,
            ),
            TextFormField(
              controller: _target,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: l.targetWeight),
              validator: (v) {
                final target = _num(v ?? '');
                final start = _num(_start.text) ?? 0;
                if (target == null || target <= 0) return l.invalidValue;
                if (target >= start) return l.errorInvalidWeight;
                return null;
              },
            ),
            TextFormField(
              controller: _days,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: l.planDays),
              validator: (v) {
                final days = int.tryParse((v ?? '').trim()) ?? 0;
                return days < 7 ? l.errorInvalidDays : null;
              },
            ),
            TextFormField(
              controller: _steps,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: l.stepGoal),
              validator: (v) =>
                  (int.tryParse((v ?? '').trim()) ?? 0) < 1000 ? l.invalidValue : null,
            ),
            const SizedBox(height: 28),
            Text(l.dietPlanSection, style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Card(
              color: theme.colorScheme.secondaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.auto_awesome, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          '${l.dietRecommendedLabel}: '
                          '${recommendation.preset.name(lang)}',
                          style: theme.textTheme.titleSmall,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(_reasonText(l, recommendation.reason),
                        style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 4),
            for (final preset in _dietEngine.presets)
              ListTile(
                selected: preset.id == selectedId,
                leading: Icon(
                  preset.id == selectedId
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                ),
                title: Text(preset.name(lang)),
                subtitle: Text(preset.description(lang)),
                onTap: () => setState(() {
                  _dietManuallyChanged = true;
                  _selectedPresetId = preset.id;
                }),
              ),
            const SizedBox(height: 8),
            Text(l.dietDisclaimer, style: theme.textTheme.bodySmall),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => _submit(l),
              child: Text(l.save),
            ),
            const SizedBox(height: 16),
            Text(l.disclaimer, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}
