import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
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

  @override
  void dispose() {
    _start.dispose();
    _target.dispose();
    _days.dispose();
    _steps.dispose();
    super.dispose();
  }

  double? _num(String raw) => double.tryParse(raw.trim());

  Future<void> _submit(AppLocalizations l) async {
    if (!_formKey.currentState!.validate()) return;
    final controller = context.read<PlanController>();
    await controller.createPlan(PlanInput(
      startDate: DateTime.now(),
      days: int.parse(_days.text.trim()),
      startWeightKg: _num(_start.text)!,
      targetWeightKg: _num(_target.text)!,
      baseStepGoal: int.parse(_steps.text.trim()),
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
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => _submit(l),
              child: Text(l.save),
            ),
            const SizedBox(height: 16),
            Text(l.disclaimer, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}
