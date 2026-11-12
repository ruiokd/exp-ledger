/// 日期键：全系统唯一的"天"标识。
///
/// 结算以本地日为单位，因此 DayKey 只保存年月日，不保存时刻，
/// 避免夏令时/时区导致的跨日漂移。
class DayKey implements Comparable<DayKey> {
  const DayKey(this.year, this.month, this.day);

  final int year;
  final int month;
  final int day;

  factory DayKey.fromDate(DateTime d) => DayKey(d.year, d.month, d.day);

  factory DayKey.today([DateTime? now]) => DayKey.fromDate(now ?? DateTime.now());

  factory DayKey.parse(String s) {
    final parts = s.split('-');
    if (parts.length != 3) {
      throw FormatException('DayKey 需要 yyyy-MM-dd 格式：$s');
    }
    return DayKey(
      int.parse(parts[0]),
      int.parse(parts[1]),
      int.parse(parts[2]),
    );
  }

  String get iso =>
      '${year.toString().padLeft(4, '0')}-'
      '${month.toString().padLeft(2, '0')}-'
      '${day.toString().padLeft(2, '0')}';

  DateTime get startOfDay => DateTime(year, month, day);

  DayKey addDays(int n) => DayKey.fromDate(
        DateTime(year, month, day).add(Duration(days: n)),
      );

  /// this 减去 other 的天数（不含时分秒误差）。
  int diffDays(DayKey other) =>
      startOfDay.difference(other.startOfDay).inDays;

  bool isBefore(DayKey other) => compareTo(other) < 0;

  bool isAfter(DayKey other) => compareTo(other) > 0;

  /// 同一 ISO 周内（周一为一周起点）。
  bool isSameWeekAs(DayKey other) {
    final a = startOfDay;
    final b = other.startOfDay;
    final mondayA = a.subtract(Duration(days: a.weekday - 1));
    final mondayB = b.subtract(Duration(days: b.weekday - 1));
    return mondayA.year == mondayB.year &&
        mondayA.month == mondayB.month &&
        mondayA.day == mondayB.day;
  }

  String get weekdayLabel =>
      const ['一', '二', '三', '四', '五', '六', '日'][startOfDay.weekday - 1];

  String get shortLabel => '$month/$day';

  @override
  int compareTo(DayKey other) {
    if (year != other.year) return year.compareTo(other.year);
    if (month != other.month) return month.compareTo(other.month);
    return day.compareTo(other.day);
  }

  @override
  bool operator ==(Object other) =>
      other is DayKey &&
      other.year == year &&
      other.month == month &&
      other.day == day;

  @override
  int get hashCode => Object.hash(year, month, day);

  @override
  String toString() => iso;
}

/// 一天中的分钟数（0..1439），用于睡眠界线比较。
class MinuteOfDay implements Comparable<MinuteOfDay> {
  const MinuteOfDay(this.minutes);

  final int minutes;

  factory MinuteOfDay.of(int hour, int minute) =>
      MinuteOfDay((hour * 60 + minute) % 1440);

  factory MinuteOfDay.parse(String hhmm) {
    final parts = hhmm.split(':');
    return MinuteOfDay.of(int.parse(parts[0]), int.parse(parts[1]));
  }

  int get hour => minutes ~/ 60;

  int get minute => minutes % 60;

  String get label =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  /// 以 reference 为"日界"的环形差值：返回 this 相对 reference 前进了多少分钟。
  /// 用于"02:10 比 00:20 晚 110 分钟"这类判定。
  int forwardFrom(MinuteOfDay reference) => (minutes - reference.minutes + 1440) % 1440;

  /// 反向差值（可能是负数）——判断是否早于界线。
  int signedDeltaFrom(MinuteOfDay reference) {
    final d = forwardFrom(reference);
    return d > 720 ? d - 1440 : d;
  }

  @override
  int compareTo(MinuteOfDay other) => minutes.compareTo(other.minutes);

  @override
  bool operator ==(Object other) =>
      other is MinuteOfDay && other.minutes == minutes;

  @override
  int get hashCode => minutes.hashCode;

  @override
  String toString() => label;
}
