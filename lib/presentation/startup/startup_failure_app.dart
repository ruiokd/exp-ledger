import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:exp_ledger/core/theme/app_theme.dart';
import 'package:exp_ledger/core/theme/tokens.dart';
import 'package:exp_ledger/services/log_service.dart';
import 'package:exp_ledger/data/db/app_database.dart';

/// 启动结果。要么带着数据库，要么带着"为什么没有"。
class BootResult {
  const BootResult({
    this.database,
    this.error,
    this.stack,
    this.stage = '',
  });

  final AppDatabase? database;
  final Object? error;
  final StackTrace? stack;

  /// 卡在哪一步：打开数据库 / 迁移 / 补算。
  final String stage;

  bool get ok => database != null;
}

/// 启动失败页。
///
/// 存在的理由很具体：`main()` 里 `await AppDatabase.open()` 在 `runApp` 之前，
/// 一旦抛异常或卡住，用户看到的就是纯黑屏——不知道是崩溃、卡死，还是没装好。
/// 这个页面把"黑屏"换成"看得见的错误 + 一键复制"，把玄学变成可诊断的信息。
class StartupFailureApp extends StatelessWidget {
  const StartupFailureApp({super.key, required this.result});

  final BootResult result;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: StartupErrorView(
            title: '启动没走完',
            stage: result.stage,
            error: result.error,
            stack: result.stack,
          ),
        ),
      ),
    );
  }
}

/// 错误展示本体。既给启动失败页用，也给 `ErrorWidget.builder` 用
/// （release 模式默认只显示一块灰，信息量为零）。
class StartupErrorView extends StatelessWidget {
  const StartupErrorView({
    super.key,
    required this.title,
    required this.stage,
    required this.error,
    this.stack,
  });

  factory StartupErrorView.fromFlutterError(FlutterErrorDetails details) {
    return StartupErrorView(
      title: '界面渲染出错',
      stage: details.context?.toString() ?? 'build',
      error: details.exception,
      stack: details.stack,
    );
  }

  final String title;
  final String stage;
  final Object? error;
  final StackTrace? stack;

  String get _report {
    final StringBuffer b = StringBuffer()
      ..writeln('经验账本 · 启动诊断')
      ..writeln('阶段：$stage')
      ..writeln('错误：${error ?? "（无）"}');
    final String? trace = stack?.toString();
    if (trace != null && trace.isNotEmpty) {
      final List<String> lines = trace.split('\n').take(12).toList();
      b
        ..writeln('堆栈：')
        ..writeln(lines.join('\n'));
    }
    return b.toString();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: const TextStyle(
              fontSize: Tokens.fontHeadline,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: Tokens.gapS),
          const Text(
            '这不是"你的手机不行"，是代码在启动阶段断掉了。'
            '下面这段信息能直接定位问题——点复制，发回给做这个 App 的人。',
            style: TextStyle(
              fontSize: Tokens.fontSmall,
              color: AppColors.inkSoft,
              height: 1.6,
            ),
          ),
          const SizedBox(height: Tokens.gapL),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surfaceMuted,
              borderRadius: BorderRadius.circular(Tokens.radiusCard),
            ),
            child: SelectableText(
              _report,
              style: const TextStyle(
                fontSize: Tokens.fontCaption,
                color: AppColors.ink,
                height: 1.5,
                fontFamily: 'monospace',
              ),
            ),
          ),
          const SizedBox(height: Tokens.gapM),
          Row(
            children: <Widget>[
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.ink,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(Tokens.radiusButton),
                  ),
                ),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: _report));
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('已复制，直接粘出去就行')),
                  );
                },
                icon: const Icon(Icons.copy_rounded, size: 18),
                label: const Text('复制诊断'),
              ),
              const SizedBox(width: Tokens.gapS),
              TextButton(
                onPressed: () {
                  // 重跑一次启动流程；成功会自己接管界面。
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute<void>(
                      builder: (_) => const _BootRetryPage(),
                    ),
                  );
                },
                child: const Text('再试一次'),
              ),
            ],
          ),
          // 启动失败时日志最值钱：把上一次运行的尾巴和这次的异常一起带走。
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () async {
                await Clipboard.setData(
                  ClipboardData(text: LogService.buildReport()),
                );
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('运行日志已复制（含上次运行的尾部）')),
                );
              },
              child: const Text('复制运行日志'),
            ),
          ),
        ],
      ),
    );
  }
}

/// 重试页：挂载时重新跑 boot，成功就换成正式界面。
class _BootRetryPage extends StatefulWidget {
  const _BootRetryPage();

  @override
  State<_BootRetryPage> createState() => _BootRetryPageState();
}

class _BootRetryPageState extends State<_BootRetryPage> {
  String _status = '正在重试…';

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    final BootResult result = await bootApp();
    if (!mounted) return;
    if (result.ok) {
      // 成功：把整棵树换成正式 App（由 main 的同一入口接管）。
      await restartApp();
      return;
    }
    setState(() => _status = '还是不行：${result.stage} · ${result.error}');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _status,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: Tokens.fontSmall,
              color: AppColors.inkSoft,
              height: 1.6,
            ),
          ),
        ),
      ),
    );
  }
}

/// 由 `main.dart` 注入，避免 startup 层反向依赖 main。
Future<BootResult> Function() bootApp = () async => const BootResult();

/// 启动成功后由 `main.dart` 注入：把根 widget 换成正式 App。
Future<void> Function() restartApp = () async {};
