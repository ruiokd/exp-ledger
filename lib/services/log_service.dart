/// 日志的落盘与全局错误钩子。
///
/// 两条纪律（都是 v1.0.0 黑屏换来的）：
///   1. `init()` 全流程 try/catch：**写日志失败绝不允许拦住启动**。
///      拿不到目录、拿不到权限，就退回纯内存日志，功能照常。
///   2. 每次写入立即 flush：崩溃前最后几行最值钱，
///      缓存在 buffer 里没落盘等于没写。
///
/// 文件位置：应用私有 support 目录下的 `app.log`，超过 512 KB 轮转一次
/// （旧的改成 `app.log.1`，只留一代）。不联网、不上传。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:exp_ledger/core/log/app_log.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class LogService {
  LogService._();

  static const String fileName = 'app.log';
  static const int rotateBytes = 512 * 1024;
  static const int seedLines = 120;

  static File? _file;
  static bool _ready = false;
  static String _path = '';

  /// 日志文件路径（未就绪时为空串）。
  static String get path => _path;

  static bool get isReady => _ready;

  /// 启动时调用一次。**任何失败都被吞掉并降级**，不影响 App。
  static Future<void> init() async {
    if (_ready) return;
    try {
      final Directory dir = await getApplicationSupportDirectory();
      final File file = File(p.join(dir.path, fileName));
      if (await file.exists()) {
        final int size = await file.length();
        if (size > rotateBytes) {
          final File old = File('${file.path}.1');
          if (await old.exists()) await old.delete();
          await file.rename(old.path);
        }
      }
      _file = File(p.join(dir.path, fileName));
      _path = _file!.path;

      // 把上次运行的尾巴读回来：连着上次崩溃一起看，才定位得了问题。
      if (await _file!.exists()) {
        final String text = await _file!.readAsString();
        final List<String> lines = const LineSplitter().convert(text);
        final List<String> tail = lines.length <= seedLines
            ? lines
            : lines.sublist(lines.length - seedLines);
        appLog.seedFromLines(tail);
      }

      appLog.attachSink(_append);
      _ready = true;
      logInfo('boot', '日志已就绪',
          detail: 'file=${p.basename(_path)} seeded=${appLog.length}');
    } catch (error) {
      _ready = false;
      debugPrint('日志初始化失败（降级为内存日志）：$error');
    }
  }

  static void _append(LogEntry entry) {
    final File? file = _file;
    if (file == null) return;
    try {
      // 同步追加 + flush：崩溃前最后一行必须已经在盘上。
      final RandomAccessFile raf = file.openSync(mode: FileMode.append);
      try {
        raf.writeStringSync('${entry.line}\n');
        raf.flushSync();
      } finally {
        raf.closeSync();
      }
    } catch (error) {
      debugPrint('日志落盘失败：$error');
      _file = null; // 写不进去就别每次再试，退回内存日志
    }
  }

  /// 安装全局错误钩子。必须在 `runApp` 之前调用。
  static void installHandlers() {
    final FlutterExceptionHandler? previous = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      logError(
        'flutter',
        details.context?.toString() ?? '界面异常',
        error: details.exception,
        stack: details.stack,
      );
      // 保持原行为：release 下仍然打印到控制台/灰屏逻辑不变。
      if (previous != null) {
        previous(details);
      } else {
        FlutterError.presentError(details);
      }
    };

    PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
      logError('platform', '未捕获的异步异常', error: error, stack: stack);
      return false; // false = 仍然走默认处理
    };
  }

  /// 读回磁盘上的全部日志（页面「上次运行」分栏用）。
  static Future<String> readPersisted() async {
    final File? file = _file;
    if (file == null) return '';
    try {
      if (!await file.exists()) return '';
      return await file.readAsString();
    } catch (error) {
      return '读日志失败：$error';
    }
  }

  static Future<void> clearPersisted() async {
    appLog.clear();
    final File? file = _file;
    if (file == null) return;
    try {
      if (await file.exists()) await file.writeAsString('');
      final File old = File('${file.path}.1');
      if (await old.exists()) await old.delete();
      logInfo('boot', '日志已清空');
    } catch (error) {
      debugPrint('清空日志失败：$error');
    }
  }

  /// 导出成一段文本（复制/分享用）。带上环境信息，省一轮追问。
  static String buildReport() {
    final StringBuffer head = StringBuffer();
    head.writeln('# 经验账本运行日志');
    head.writeln('导出时间：${DateTime.now().toIso8601String()}');
    head.writeln('平台：${Platform.operatingSystem} ${Platform.operatingSystemVersion}');
    head.writeln('Dart：${Platform.version}');
    head.writeln('日志条数：${appLog.length}（其中错误 ${appLog.errorCount} 条）');
    head.writeln('落盘：${_ready ? '正常' : '未就绪（仅内存）'}');
    head.writeln('说明：日志不含行为内容与数值，只有「什么操作、什么结果」。');
    head.writeln('---');
    head.write(appLog.dump());
    return head.toString();
  }
}
