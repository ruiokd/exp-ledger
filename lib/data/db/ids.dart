/// 标识符工具。
///
/// 引擎产出的 `ValenceEvent.id` 是 `dayKey|behaviorCode|slotKey#p`，
/// 里面已经带了槽位信息。数据层需要独立的一列 `slot_key` 来建唯一索引，
/// 又不想给 domain 模型加一个只服务数据库的字段——
/// 所以在这一个地方做解析，别处不准再拆这个字符串。
library;

/// 从事件 id 里取出槽位键。格式不符时返回空串。
String slotKeyOfEventId(String id) {
  final hashIndex = id.indexOf('#');
  final core = hashIndex >= 0 ? id.substring(0, hashIndex) : id;
  final parts = core.split('|');
  if (parts.length < 3) return '';
  // 槽位本身理论上不含 `|`，但真含了也不能丢——剩下的全部拼回去。
  return parts.sublist(2).join('|');
}

/// 从事件 id 里取出行为码。
String behaviorCodeOfEventId(String id) {
  final hashIndex = id.indexOf('#');
  final core = hashIndex >= 0 ? id.substring(0, hashIndex) : id;
  final parts = core.split('|');
  if (parts.length < 2) return '';
  return parts[1];
}

/// 生成一个本地唯一 id（不依赖 uuid 包，避免多一个依赖）。
String newLocalId(String prefix, [DateTime? now]) {
  final t = (now ?? DateTime.now()).microsecondsSinceEpoch;
  return '$prefix-$t';
}

/// 根因键：`behaviorCode@yyyy-MM-dd`。与 domain/engine/attribution.dart 一致。
/// 数据层做查询时用它，避免两处格式漂移。
String rootCauseKeyFor(String behaviorCode, String dayIso) =>
    '$behaviorCode@$dayIso';
