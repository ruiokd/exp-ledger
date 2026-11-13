/// 量什么 + 影响落在哪些维度。
///
/// 从 `quant_spec.dart` 切出来的：这两个类型是"输入的形状"，
/// 校验器与规格本身都要用，混在一个 450 行的文件里会让人以为它们是同一层。
library;

import 'axis_registry.dart';

/// 量什么。决定采集页问哪个问题，也决定哪些行为根本不该有"剂量曲线"。
enum MeasureKind {
  /// 时长：分钟。适合阅读、训练、陪伴。
  durationMin('时长', '分钟'),

  /// 次数：可数。适合组数、页数。
  count('次数', '次'),

  /// 事件：发生/未发生。配合 [DoseShape.threshold] 用。
  episode('事件', '次'),

  /// 主观分：自报 0–10。只允许进 `experience` 维度。
  rating('主观分', '分');

  const MeasureKind(this.label, this.defaultUnit);

  final String label;
  final String defaultUnit;

  /// 从单位猜量法。**只用于没问过用户的地方**（自建项目的默认口径）：
  /// 猜错只会让采集页问的问题不一样，不影响分数口径（形状默认 linear）。
  /// 所以这里允许猜，跟 [tryParse] 的"猜就报错"是两种场景，别混。
  static MeasureKind guessFromUnit(String unit) {
    final String u = unit.trim();
    if (u.isEmpty) return count;
    if (u.contains('分钟') || u.startsWith('min')) return durationMin;
    if (u == '分' || u == '点') return rating;
    return count;
  }

  /// 未知值返回 null：不许静默回退成「时长」，那会把一次电影记成 0 分钟。
  static MeasureKind? tryParse(String? raw) {
    if (raw == null) return null;
    for (final MeasureKind k in MeasureKind.values) {
      if (k.name == raw) return k;
    }
    return null;
  }
}

/// 影响在某个维度上的份额。
class ImpactShare {
  const ImpactShare({
    required this.axisKey,
    required this.axisLabel,
    required this.kind,
    required this.share,
    this.decayTauDays = 0,
    this.decayCitation = '',
  });

  final String axisKey;
  final String axisLabel;
  final AxisKind kind;
  final double share;

  /// 新维度宣称自己能进主曲线时，必须自带衰减常数与依据。
  /// 内置维度忽略这两个字段（以注册表为准）。
  final double decayTauDays;
  final String decayCitation;

  bool get hasDecayEvidence =>
      decayTauDays > 0 && decayCitation.trim().isNotEmpty;

  ImpactShare copyWith({double? share, AxisKind? kind}) => ImpactShare(
        axisKey: axisKey,
        axisLabel: axisLabel,
        kind: kind ?? this.kind,
        share: share ?? this.share,
        decayTauDays: decayTauDays,
        decayCitation: decayCitation,
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'axis': axisKey,
        'axis_label': axisLabel,
        'dim_kind': kind.name,
        'share': share,
        if (decayTauDays > 0) 'decay_tau_days': decayTauDays,
        if (decayCitation.isNotEmpty) 'decay_citation': decayCitation,
      };

  static ImpactShare? fromJson(Map<String, Object?> json) {
    final String key = json['axis']?.toString() ?? '';
    if (key.isEmpty) return null;
    final double share = (json['share'] as num?)?.toDouble() ?? 0;
    return ImpactShare(
      axisKey: key,
      axisLabel: json['axis_label']?.toString() ?? key,
      kind: AxisKind.parseOrDefault(json['dim_kind']?.toString()),
      share: share,
      decayTauDays: (json['decay_tau_days'] as num?)?.toDouble() ?? 0,
      decayCitation: json['decay_citation']?.toString() ?? '',
    );
  }
}

