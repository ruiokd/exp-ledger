/// 运行日志页。给用户一条"出问题能说出第二句话"的路。
///
/// 三件事：
///   1. 看——按级别筛，最新的在最上面，出错的行标红；
///   2. 带走——一键复制或分享成文本，直接发给开发者；
///   3. 清——清空内存与磁盘，别把旧噪音混进新问题。
///
/// 日志内容**不含行为明细与数值**（见 `app_log.dart` 的约束 3），
/// 所以复制出去不需要打码。
library;

import 'dart:io';

import 'package:exp_ledger/core/log/app_log.dart';
import 'package:exp_ledger/core/theme/tokens.dart';
import 'package:exp_ledger/services/log_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class LogPage extends StatefulWidget {
  const LogPage({super.key});

  @override
  State<LogPage> createState() => _LogPageState();
}

class _LogPageState extends State<LogPage> {
  LogLevel? _min = LogLevel.info;

  List<LogEntry> get _entries =>
      AppLog.instance.snapshot(minLevel: _min).reversed.toList(growable: false);

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), backgroundColor: AppColors.ink),
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<LogEntry> entries = _entries;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.ink,
        elevation: 0,
        title: const Text('运行日志', style: TextStyle(fontSize: Tokens.fontTitle)),
        actions: <Widget>[
          IconButton(
            tooltip: '复制全部',
            icon: const Icon(Icons.copy_rounded, size: 20),
            onPressed: _copy,
          ),
          IconButton(
            tooltip: '分享文件',
            icon: const Icon(Icons.ios_share, size: 20),
            onPressed: _share,
          ),
          IconButton(
            tooltip: '清空',
            icon: const Icon(Icons.delete_outline, size: 20),
            onPressed: _confirmClear,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            _header(),
            _filters(),
            const SizedBox(height: Tokens.gapS),
            Expanded(
              child: entries.isEmpty
                  ? const Center(
                      child: Text(
                        '这个级别下还没有日志。\n出问题时先复现一次，再回来这里。',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: Tokens.fontSmall,
                          color: AppColors.inkFaint,
                          height: 1.6,
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(
                        Tokens.gapL,
                        0,
                        Tokens.gapL,
                        Tokens.gapXl,
                      ),
                      itemCount: entries.length,
                      separatorBuilder: (_, __) => const Divider(
                        height: 1,
                        color: AppColors.divider,
                      ),
                      itemBuilder: (BuildContext context, int i) =>
                          _row(entries[i]),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header() => Container(
        margin: const EdgeInsets.fromLTRB(
          Tokens.gapL,
          Tokens.gapS,
          Tokens.gapL,
          Tokens.gapS,
        ),
        padding: const EdgeInsets.all(Tokens.gapM),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(Tokens.radiusCard),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              '共 ${AppLog.instance.length} 条 · 错误 ${AppLog.instance.errorCount} 条 · '
              '${LogService.isReady ? '已落盘' : '仅内存（落盘不可用）'}',
              style: const TextStyle(
                fontSize: Tokens.fontSmall,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '日志只记「什么操作、什么结果」，不含行为内容与数值。'
              '出异常时点右上角复制，整段发过来即可。',
              style: const TextStyle(
                fontSize: Tokens.fontCaption,
                color: AppColors.inkFaint,
                height: 1.4,
              ),
            ),
          ],
        ),
      );

  Widget _filters() {
    Widget chip(String label, LogLevel? level) {
      final bool on = _min == level;
      return Padding(
        padding: const EdgeInsets.only(right: Tokens.gapS),
        child: FilterChip(
          label: Text(label, style: const TextStyle(fontSize: Tokens.fontCaption)),
          selected: on,
          selectedColor: AppColors.accentSoft,
          backgroundColor: AppColors.surface,
          side: BorderSide(color: on ? AppColors.accent : AppColors.divider),
          onSelected: (_) => setState(() => _min = level),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: Tokens.gapL),
      child: Row(
        children: <Widget>[
          chip('全部', null),
          chip('信息以上', LogLevel.info),
          chip('警告以上', LogLevel.warn),
          chip('仅错误', LogLevel.error),
        ],
      ),
    );
  }

  Widget _row(LogEntry e) {
    Color color = AppColors.inkSoft;
    if (e.level == LogLevel.error) color = AppColors.accent;
    if (e.level == LogLevel.warn) color = AppColors.calm;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Tokens.gapS),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  e.level.tag,
                  style: TextStyle(
                    fontSize: Tokens.fontMicro,
                    color: color,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: Tokens.gapS),
              Text(
                e.time,
                style: const TextStyle(
                  fontSize: Tokens.fontMicro,
                  color: AppColors.inkFaint,
                ),
              ),
              const SizedBox(width: Tokens.gapS),
              Text(
                e.tag,
                style: const TextStyle(
                  fontSize: Tokens.fontMicro,
                  color: AppColors.inkFaint,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            e.message,
            style: TextStyle(
              fontSize: Tokens.fontSmall,
              color: e.level == LogLevel.error ? AppColors.ink : AppColors.inkSoft,
              height: 1.35,
            ),
          ),
          if (e.detail.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: SelectableText(
                e.detail,
                style: const TextStyle(
                  fontSize: Tokens.fontMicro,
                  color: AppColors.inkFaint,
                  height: 1.3,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: LogService.buildReport()));
    _toast('已复制整份日志，直接发过去就行');
  }

  Future<void> _share() async {
    try {
      final String report = LogService.buildReport();
      final Directory dir = await getTemporaryDirectory();
      final String stamp = DateTime.now()
          .toIso8601String()
          .replaceAll(RegExp(r'[:.]'), '')
          .substring(0, 15);
      final File file = File(p.join(dir.path, 'exp_ledger_log_$stamp.txt'));
      await file.writeAsString(report);
      await Share.shareXFiles(
        <XFile>[XFile(file.path, mimeType: 'text/plain')],
        subject: '经验账本运行日志',
        text: '整份运行日志，不含行为内容与数值。',
      );
    } catch (error) {
      logError('ui', '分享日志失败', error: error);
      _toast('分享失败：$error');
    }
  }

  Future<void> _confirmClear() async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('清空日志？'),
        content: const Text('内存与磁盘上的都会清掉。清之前建议先复制一份。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.accent),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await LogService.clearPersisted();
    if (!mounted) return;
    setState(() {});
    _toast('已清空');
  }
}
