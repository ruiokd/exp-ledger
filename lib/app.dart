import 'package:exp_ledger/core/theme/app_theme.dart';
import 'package:exp_ledger/presentation/shell/app_shell.dart';
import 'package:flutter/material.dart';

class ExpLedgerApp extends StatelessWidget {
  const ExpLedgerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '经验账本',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: const AppShell(),
    );
  }
}
