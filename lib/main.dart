import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'l10n/app_localizations.dart';
import 'state/plan_controller.dart';
import 'ui/home_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 先完成时区、通知插件与本地存储的初始化，再挂载 Widget 树。
  final controller = await PlanController.create();
  runApp(LeanPathApp(controller: controller));
}

class LeanPathApp extends StatefulWidget {
  const LeanPathApp({super.key, required this.controller});

  final PlanController controller;

  @override
  State<LeanPathApp> createState() => _LeanPathAppState();
}

class _LeanPathAppState extends State<LeanPathApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.controller.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // 回到前台时重开观察窗口，并按需重排被系统清掉的本地通知。
      widget.controller.onAppResumed();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<PlanController>.value(
      value: widget.controller,
      child: MaterialApp(
        title: '轻计划 LeanPath',
        theme: ThemeData(
          useMaterial3: true,
          colorSchemeSeed: const Color(0xFF2E7D6B),
          brightness: Brightness.light,
        ),
        darkTheme: ThemeData(
          useMaterial3: true,
          colorSchemeSeed: const Color(0xFF2E7D6B),
          brightness: Brightness.dark,
        ),
        localizationsDelegates: [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: const HomePage(),
      ),
    );
  }
}
