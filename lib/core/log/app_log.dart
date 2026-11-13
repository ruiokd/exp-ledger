/// 运行日志：内存环形缓冲 + 可插拔落盘。
///
/// 为什么需要它：装机后出问题，用户能给的只有「黑屏」「卡」「点了没反应」。
/// 有日志才有第二句话——阶段、异常原文、堆栈。v1.0.0 那次黑屏排查，靠的
/// 就是诊断页把 `DatabaseException(...)` 原文显示出来。
///
/// 三条约束：
///   1. **纯 Dart**：只依赖 `dart:core`，因此 domain / data 层都能打点，
///      不需要 Flutter，也不影响"domain 零 Flutter 依赖"这条铁律。
///   2. **固定容量**：环形缓冲 800 条，满了丢最旧的。日志不许把内存吃掉。
///   3. **不记内容**：只记"什么操作、什么结果、什么错误"。
///      行为细节、答案、数值都不进日志——日志会被复制出去。
library;

/// 日志级别。`warn` 及以上默认在页面上高亮。
enum LogLevel {
  debug,
  info,
  warn,
  error;

  String get tag {
    if (this == LogLevel.debug) return 'D';
    if (this == LogLevel.info) return 'I';
    if (this == LogLevel.warn) return 'W';
    return 'E';
  }

  String get label {
    if (this == LogLevel.debug) return '调试';
    if (this == LogLevel.info) return '信息';
    if (this == LogLevel.warn) return '警告';
    return '错误';
  }

  static LogLevel parse(String raw) {
    for (final LogLevel l in LogLevel.values) {
      if (l.tag == raw.toUpperCase()) return l;
    }
    return LogLevel.info;
  }
}

class LogEntry {
  const LogEntry({
    required this.at,
    required this.level,
    required this.tag,
    required this.message,
    this.detail = '',
    this.previousRun = false,
  });

  final DateTime at;
  final LogLevel level;

  /// 模块标记：boot / db / settle / capture / anchor / ui / flutter / zone。
  final String tag;

  final String message;

  /// 异常原文、堆栈、附加键值。已截断，不会无限长。
  final String detail;

  /// 上一次运行留下的（启动时从文件尾部读回来的）。
  ///
  /// 默认**不**参与列表与导出：不然每次导出的前半截都是上次的碎片，
  /// 时间戳还全被压成"现在"，读起来像刚发生的事。
  final bool previousRun;

  String get time =>
      '${_two(at.hour)}:${_two(at.minute)}:${_two(at.second)}.${_three(at.millisecond)}';

  /// 单行版（页面列表用）。
  String get line => '${_date(at)} $time ${level.tag} [$tag] $message'
      '${detail.isEmpty ? '' : ' | $detail'}';

  static String _two(int v) => v < 10 ? '0$v' : '$v';
  static String _three(int v) => v < 10 ? '00$v' : (v < 100 ? '0$v' : '$v');

  static String _date(DateTime t) =>
      '${t.year}-${_two(t.month)}-${_two(t.day)}';
}

class AppLog {
  AppLog._();

  static final AppLog instance = AppLog._();

  /// 环形缓冲容量。够覆盖一次使用 + 一次启动，又不会吃掉内存。
  static const int capacity = 800;

  /// 单条 detail 的最大长度。堆栈取前若干行就够定位了。
  static const int maxDetailLength = 1200;

  final List<LogEntry> _buffer = <LogEntry>[];

  void Function(LogEntry entry)? _sink;

  /// 落盘钩子。`LogService.init` 里挂上；挂不上就是纯内存日志（仍然可用）。
  void attachSink(void Function(LogEntry entry)? sink) => _sink = sink;

  bool get hasPersistentSink => _sink != null;

  void add(
    LogLevel level,
    String tag,
    String message, {
    String detail = '',
  }) {
    final LogEntry entry = LogEntry(
      at: DateTime.now(),
      level: level,
      tag: tag,
      message: message,
      detail: detail.length > maxDetailLength
          ? '${detail.substring(0, maxDetailLength)}…'
          : detail,
    );
    _buffer.add(entry);
    if (_buffer.length > capacity) {
      _buffer.removeRange(0, _buffer.length - capacity);
    }
    final void Function(LogEntry)? sink = _sink;
    if (sink != null) {
      try {
        sink(entry);
      } catch (_) {
        // 落盘失败不许影响调用方——写日志永远不该让业务失败。
      }
    }
  }

  List<LogEntry> snapshot({
    LogLevel? minLevel,
    int? limit,
    bool includePreviousRun = false,
  }) {
    final List<LogEntry> all = _buffer
        .where((LogEntry e) =>
            (includePreviousRun || !e.previousRun) &&
            (minLevel == null || e.level.index >= minLevel.index))
        .toList(growable: false);
    if (limit == null || all.length <= limit) return all;
    return all.sublist(all.length - limit);
  }

  int get length => _buffer.length;

  /// 只数**本次运行**的错误：重启后的"上次那 9 条"不该永远挂在这里。
  int get errorCount => _buffer
      .where((LogEntry e) => !e.previousRun && e.level == LogLevel.error)
      .length;

  /// 上次运行留下来的行数。
  int get previousRunCount =>
      _buffer.where((LogEntry e) => e.previousRun).length;

  /// 纯文本导出（复制给别人的就是这段）。
  String dump({
    LogLevel? minLevel,
    String header = '',
    bool includePreviousRun = false,
  }) {
    final StringBuffer b = StringBuffer();
    if (header.isNotEmpty) {
      b.writeln(header);
      b.writeln('---');
    }
    for (final LogEntry e in snapshot(
      minLevel: minLevel,
      includePreviousRun: includePreviousRun,
    )) {
      b.writeln(e.line);
    }
    return b.toString();
  }

  void clear() {
    _buffer.clear();
  }

  /// 启动时把上次运行的日志尾巴塞回来（标成上一条运行）。
  void seedFromLines(Iterable<String> lines) {
    for (final String raw in lines) {
      final String line = raw.trimRight();
      if (line.isEmpty) continue;
      _buffer.add(LogEntry(
        at: DateTime.now(),
        level: line.contains(' E [') ? LogLevel.error : LogLevel.info,
        tag: 'last',
        message: line,
        previousRun: true,
      ));
    }
    if (_buffer.length > capacity) {
      _buffer.removeRange(0, _buffer.length - capacity);
    }
  }
}

AppLog get appLog => AppLog.instance;

/// 打点用的简短入口。日志点越多越好用，所以调用要短到不会让人犹豫。
void logDebug(String tag, String message, {String detail = ''}) =>
    appLog.add(LogLevel.debug, tag, message, detail: detail);

void logInfo(String tag, String message, {String detail = ''}) =>
    appLog.add(LogLevel.info, tag, message, detail: detail);

void logWarn(String tag, String message, {String detail = ''}) =>
    appLog.add(LogLevel.warn, tag, message, detail: detail);

void logError(
  String tag,
  String message, {
  Object? error,
  StackTrace? stack,
  String detail = '',
}) {
  final StringBuffer d = StringBuffer(detail);
  if (error != null) {
    if (d.isNotEmpty) d.write(' · ');
    d.write(error.toString());
  }
  if (stack != null) {
    final List<String> lines = stack.toString().split('\n');
    d.write('\n${lines.take(8).join('\n')}');
  }
  appLog.add(LogLevel.error, tag, message, detail: d.toString());
}
