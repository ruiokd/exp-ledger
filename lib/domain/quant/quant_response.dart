/// 导入端：解析 AI 回复，一条一条过闸。
///
/// 从 `quant_codec.dart` 切出来的两半之一。绝不抛异常：
/// 所有异常都变成 `batchIssues` 里的一条原因码，坏的那条带序号回到 UI。
library;

import 'dart:convert';

import 'axis_registry.dart';
import 'dose_shape.dart';
import 'quant_measure.dart';
import 'quant_spec.dart';
import 'quant_validate.dart';

/// 解码结果。坏的那条**不会被丢掉**：它带着原因码回到 UI，
/// 用户能拿它回去让 AI 只改那一条。
class QuantDecodeResult {
  const QuantDecodeResult(this.items, this.batchIssues);

  final List<QuantValidation> items;
  final List<QuantIssue> batchIssues;

  bool get hasItems => items.isNotEmpty;

  List<QuantValidation> get accepted =>
      items.where((QuantValidation v) => v.accepted).toList(growable: false);

  List<QuantValidation> get rejected =>
      items.where((QuantValidation v) => !v.accepted).toList(growable: false);

  int get acceptedCount => accepted.length;
  int get rejectedCount => rejected.length;
}

/// 解析 AI 回复。绝不抛异常：所有异常都变成 `batchIssues` 里的一条原因码。
QuantDecodeResult decodeQuantResponse(
  String raw, {
  AxisRegistry registry = const AxisRegistry(),
}) {
  final List<QuantIssue> batch = <QuantIssue>[];

  final String? jsonText = extractJson(raw);
  if (jsonText == null) {
    batch.add(const QuantIssue(
      code: 'R_NO_JSON',
      field: 'raw',
      message: '回复里找不到 JSON（要一整段平衡的 {} 或 []）',
    ));
    return QuantDecodeResult(const <QuantValidation>[], batch);
  }

  Object? decoded;
  try {
    decoded = jsonDecode(jsonText);
  } on FormatException catch (e) {
    batch.add(QuantIssue(
      code: 'R_BAD_JSON',
      field: 'raw',
      message: 'JSON 解析失败：${e.message}',
    ));
    return QuantDecodeResult(const <QuantValidation>[], batch);
  }

  Object? rawItems;
  if (decoded is Map) {
    rawItems = decoded['items'];
  } else if (decoded is List) {
    rawItems = decoded;
  }
  if (rawItems is! List || rawItems.isEmpty) {
    batch.add(const QuantIssue(
      code: 'R_NO_ITEMS',
      field: 'items',
      message: '没有 items 数组，或数组是空的',
    ));
    return QuantDecodeResult(const <QuantValidation>[], batch);
  }

  final List<QuantValidation> items = <QuantValidation>[];
  for (int i = 0; i < rawItems.length; i++) {
    final Object? entry = rawItems[i];
    if (entry is! Map) {
      batch.add(QuantIssue(
        code: 'R_BAD_ITEM',
        field: 'items[$i]',
        message: '第 ${i + 1} 条不是对象，已跳过',
        slot: i,
      ));
      continue;
    }
    items.add(_decodeOne(Map<String, Object?>.from(entry), i, registry));
  }
  return QuantDecodeResult(items, batch);
}

QuantValidation _decodeOne(
  Map<String, Object?> item,
  int slot,
  AxisRegistry registry,
) {
  final List<QuantIssue> issues = <QuantIssue>[];

  final String code = _str(item['behavior_code']);
  final Map<String, Object?> measure = _map(item['measure']);
  final Map<String, Object?> shape = _map(item['shape']);

  // 量什么
  MeasureKind measureKind = MeasureKind.count;
  final String measureRaw = _str(measure['kind']);
  final MeasureKind? parsedMeasure = MeasureKind.tryParse(measureRaw);
  if (parsedMeasure == null) {
    issues.add(QuantIssue(
      code: 'R_UNKNOWN_MEASURE',
      field: 'measure.kind',
      message: '量法「$measureRaw」不认识，只接受 '
          '${MeasureKind.values.map((MeasureKind k) => k.name).join(" / ")}',
      slot: slot,
    ));
  } else {
    measureKind = parsedMeasure;
  }

  final String unit = _str(measure['unit']).trim();

  // 怎么折算
  final String shapeRaw = _str(shape['kind']);
  DoseShape shapeKind = DoseShape.linear;
  if (shapeRaw.isNotEmpty) {
    final DoseShape? parsedShape = DoseShape.tryParse(shapeRaw);
    if (parsedShape == null) {
      issues.add(QuantIssue(
        code: 'R_UNKNOWN_SHAPE',
        field: 'shape.kind',
        message: '形状「$shapeRaw」不在白名单（linear / log / saturating / threshold）',
        slot: slot,
      ));
    } else {
      shapeKind = parsedShape;
    }
  }
  final DoseShapeSpec shapeSpec = DoseShapeSpec(
    kind: shapeKind,
    logK: _num(shape['k'], 1),
    thetaFraction: _num(shape['theta_fraction'], 1),
  );

  // 落在哪些维度
  final List<ImpactShare> impact = <ImpactShare>[];
  final Object? rawImpact = item['impact'];
  if (rawImpact is List) {
    for (final Object? entry in rawImpact) {
      if (entry is! Map) continue;
      final Map<String, Object?> m = Map<String, Object?>.from(entry);
      final ImpactShare? share = ImpactShare.fromJson(m);
      if (share == null) continue;
      // 标签缺失时用注册表补，别在界面上显示一个 key。
      final AxisSpec? known = registry.tryResolve(share.axisKey);
      impact.add(
        share.axisLabel == share.axisKey && known != null
            ? ImpactShare(
                axisKey: share.axisKey,
                axisLabel: known.label,
                kind: share.kind,
                share: share.share,
                decayTauDays: share.decayTauDays,
                decayCitation: share.decayCitation,
              )
            : share,
      );
    }
  } else if (rawImpact != null) {
    issues.add(QuantIssue(
      code: 'R_BAD_IMPACT',
      field: 'impact',
      message: 'impact 必须是数组',
      slot: slot,
    ));
  }

  final double target = _num(item['target_dose'], 0);
  final String citation = _str(item['citation']);
  final String rationale = _str(item['rationale']);

  if (unit.isEmpty) {
    issues.add(QuantIssue(
      code: 'R_NO_UNIT',
      field: 'measure.unit',
      message: '缺单位（"30" 没有单位就没法复算）',
      slot: slot,
    ));
  }

  final QuantSpec spec = QuantSpec(
    behaviorCode: code,
    measureKind: measureKind,
    measureUnit: unit.isEmpty ? measureKind.defaultUnit : unit,
    shape: shapeSpec,
    targetDose: target,
    impact: impact,
    howToCheck: _str(measure['how_to_check']),
    citation: citation.isEmpty ? '无' : citation,
    source: 'aiProposal',
    note: <String>[
      if (rationale.isNotEmpty) 'AI 原话：$rationale',
      if (citation.isEmpty) 'AI 未给依据',
    ].join('；'),
  );

  final QuantValidation base = validateQuantSpec(spec, registry: registry, slot: slot);
  return QuantValidation(base.spec, <QuantIssue>[...issues, ...base.issues]);
}

/// 从一堆话里抠出第一个括号平衡的 JSON 片段。字符串内的括号不参与计数，
/// 转义由 `\` 处理——AI 的回复里经常带 `\"`。
String? extractJson(String raw) {
  final int objStart = raw.indexOf('{');
  final int arrStart = raw.indexOf('[');

  // 取更靠前的那个起点；都没有就返回 null。
  int start;
  if (objStart < 0 && arrStart < 0) return null;
  if (objStart < 0) {
    start = arrStart;
  } else if (arrStart < 0) {
    start = objStart;
  } else {
    start = objStart < arrStart ? objStart : arrStart;
  }

  final String open = raw[start];
  final String close = open == '{' ? '}' : ']';

  int depth = 0;
  bool inString = false;
  bool escaped = false;
  for (int i = start; i < raw.length; i++) {
    final String ch = raw[i];
    if (inString) {
      if (escaped) {
        escaped = false;
      } else if (ch == '\\') {
        escaped = true;
      } else if (ch == '"') {
        inString = false;
      }
      continue;
    }
    if (ch == '"') {
      inString = true;
      continue;
    }
    if (ch == open) depth++;
    if (ch == close) {
      depth--;
      if (depth == 0) return raw.substring(start, i + 1);
    }
  }
  return null;
}

Map<String, Object?> _map(Object? raw) =>
    raw is Map ? Map<String, Object?>.from(raw) : const <String, Object?>{};

String _str(Object? raw) => raw == null ? '' : raw.toString();

double _num(Object? raw, double fallback) {
  if (raw is num) return raw.toDouble();
  if (raw is String) return double.tryParse(raw.trim()) ?? fallback;
  return fallback;
}

