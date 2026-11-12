/// 列值转换。数据库里全是 TEXT/REAL/INTEGER，
/// 而模型层要的是 `Map<String, double>`、枚举、可空 double——
/// 所有转换只在这里发生，避免每个 DAO 各写一套。
library;

import 'dart:convert';

/// 编码成 JSON 列。`null` 存成 SQL NULL。
String? encodeJsonOrNull(Object? value) =>
    value == null ? null : jsonEncode(value);

/// 编码成 JSON 列，空值退化成空对象（NOT NULL 列用）。
String encodeJsonMap(Map<String, Object?>? value) =>
    jsonEncode(value ?? const <String, Object?>{});

/// 编码成 JSON 数组列（NOT NULL 列用）。
String encodeJsonList(Iterable<Object?>? value) =>
    jsonEncode((value ?? const <Object?>[]).toList());

/// 对象 → map。非 map 一律退化成空 map。
Map<String, Object?> decodeMap(String? raw) {
  if (raw == null || raw.isEmpty) return <String, Object?>{};
  final decoded = _tryDecode(raw);
  if (decoded is Map) {
    return decoded.map<String, Object?>(
      (Object? k, Object? v) => MapEntry<String, Object?>('$k', v),
    );
  }
  return <String, Object?>{};
}

/// 对象 → `Map<String, double>`。非数字项丢弃（脏数据不传染）。
Map<String, double> decodeDoubleMap(String? raw) {
  final src = decodeMap(raw);
  final out = <String, double>{};
  for (final entry in src.entries) {
    final v = entry.value;
    if (v is num) {
      out[entry.key] = v.toDouble();
    } else if (v is String) {
      final parsed = double.tryParse(v);
      if (parsed != null) out[entry.key] = parsed;
    }
  }
  return out;
}

/// 对象 → 字符串列表。非字符串项转成字符串，避免整列丢失。
List<String> decodeStringList(String? raw) {
  if (raw == null || raw.isEmpty) return const <String>[];
  final decoded = _tryDecode(raw);
  if (decoded is List) {
    return decoded.map<String>((Object? e) => e?.toString() ?? '').toList();
  }
  return const <String>[];
}

Object? _tryDecode(String raw) {
  try {
    return jsonDecode(raw);
  } on FormatException {
    return null;
  }
}

/// 任意列 → double?。字符串数字也认。
double? asDoubleOrNull(Object? v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v);
  return null;
}

/// 任意列 → double，缺省用 [fallback]。
double asDouble(Object? v, {double fallback = 0}) =>
    asDoubleOrNull(v) ?? fallback;

/// 任意列 → int，缺省用 [fallback]。
int asInt(Object? v, {int fallback = 0}) {
  if (v == null) return fallback;
  if (v is int) return v;
  if (v is num) return v.round();
  if (v is String) return int.tryParse(v) ?? fallback;
  return fallback;
}

/// 任意列 → bool。SQLite 里是 0/1。
bool asBool(Object? v, {bool fallback = false}) {
  if (v == null) return fallback;
  if (v is bool) return v;
  if (v is num) return v != 0;
  if (v is String) {
    final s = v.toLowerCase();
    if (s == '1' || s == 'true') return true;
    if (s == '0' || s == 'false') return false;
  }
  return fallback;
}

/// 布尔 → 列值。
int boolToInt(bool v) => v ? 1 : 0;

/// 任意列 → 枚举。未知值退化成 [fallback]，绝不抛异常
/// （旧版本写入的枚举名在改名后仍然能读）。
T parseEnum<T extends Enum>(List<T> values, Object? raw, T fallback) {
  if (raw == null) return fallback;
  final name = raw.toString();
  for (final v in values) {
    if (v.name == name) return v;
  }
  return fallback;
}

/// 统一的时间格式：ISO8601 本地时间，带毫秒。
/// 全系统的时间列都走这里，避免有的带 Z 有的不带导致排序错乱。
String nowIso() => DateTime.now().toIso8601String();

/// 读取时间列。解析失败返回 null 而不是抛异常。
DateTime? parseDate(Object? raw) {
  if (raw == null) return null;
  if (raw is DateTime) return raw;
  return DateTime.tryParse(raw.toString());
}
