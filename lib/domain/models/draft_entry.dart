import '../../core/util/date_key.dart';
import '../enums.dart';
import 'behavior_def.dart';
import 'project_axis.dart';

/// 一条待落库的行为记录。所有写入都必须经过它——
/// 这是全系统唯一的写入口，幂等与级联重算都靠它收敛。
class DraftEntry {
  const DraftEntry({
    required this.dayKey,
    required this.behaviorCode,
    required this.category,
    required this.valence,
    required this.axis,
    required this.planStatus,
    required this.confidence,
    required this.slotKey,
    required this.answers,
    required this.metrics,
    required this.interpretation,
    required this.doseFraction,
    required this.source,
    required this.createdAt,
    this.sessionId,
    this.notes = const [],
    this.warnings = const [],
    this.revision = 0,
    this.isInterruption = false,
  });

  final DayKey dayKey;
  final String behaviorCode;
  final BehaviorCategory category;
  final Valence valence;

  /// 这条记录属于哪一个能力维度（体能/心肺/词汇/写作/自律）。
  final ProjectAxis axis;

  final PlanStatus planStatus;
  final Confidence confidence;

  /// 同日内区分多个实例（如深蹲 / 卧推 / 硬拉各一条）。
  final String slotKey;

  final Map<String, Object?> answers;
  final Map<String, double> metrics;
  final String interpretation;
  final double doseFraction;

  /// 来源：manual / widget / notification / voice / same_as_last。
  final String source;

  final DateTime createdAt;
  final String? sessionId;
  final List<String> notes;
  final List<String> warnings;

  /// 历史修正次数。每次修正 +1，旧版本留在 daily_log 的历史表里。
  final int revision;

  /// 是否属于"中断期"（生病/受伤/加班/旅行），图表要换底色。
  final bool isInterruption;

  /// 幂等键：同日 + 同行为 + 同槽位。重复提交只会覆盖。
  String get idempotencyKey => '${dayKey.iso}|$behaviorCode|$slotKey';

  /// 带修订号的键，只有修正历史时才用。
  String get revisionKey => '$idempotencyKey#r$revision';

  DraftEntry copyWith({
    PlanStatus? planStatus,
    Confidence? confidence,
    Map<String, Object?>? answers,
    Map<String, double>? metrics,
    String? interpretation,
    double? doseFraction,
    List<String>? notes,
    List<String>? warnings,
    int? revision,
  }) {
    return DraftEntry(
      dayKey: dayKey,
      behaviorCode: behaviorCode,
      category: category,
      valence: valence,
      axis: axis,
      planStatus: planStatus ?? this.planStatus,
      confidence: confidence ?? this.confidence,
      slotKey: slotKey,
      answers: answers ?? this.answers,
      metrics: metrics ?? this.metrics,
      interpretation: interpretation ?? this.interpretation,
      doseFraction: doseFraction ?? this.doseFraction,
      source: source,
      createdAt: createdAt,
      sessionId: sessionId,
      notes: notes ?? this.notes,
      warnings: warnings ?? this.warnings,
      revision: revision ?? this.revision,
      isInterruption: isInterruption,
    );
  }

  /// 从行为定义 + 推导结果组装。
  static DraftEntry fromDerived({
    required DayKey dayKey,
    required BehaviorDef behavior,
    required DerivedResult derived,
    required PlanStatus planStatus,
    required DateTime now,
    String source = 'manual',
    String? sessionId,
    bool isInterruption = false,
  }) {
    return DraftEntry(
      dayKey: dayKey,
      behaviorCode: behavior.code,
      category: behavior.category,
      // 睡眠这类"同一次记录可能正也可能负"的行为，价由推导结果决定，
      // 不能直接用静态 valence。
      valence: behavior.valenceOf(derived),
      axis: behavior.axis,
      planStatus: planStatus,
      confidence: derived.confidence,
      slotKey: derived.slotKey,
      answers: derived.normalized,
      metrics: derived.metrics,
      interpretation: derived.interpretation,
      doseFraction: derived.doseFraction,
      source: source,
      createdAt: now,
      sessionId: sessionId,
      notes: derived.notes,
      warnings: derived.warnings,
      isInterruption: isInterruption,
    );
  }

  Map<String, Object?> toRow() => {
        'day_key': dayKey.iso,
        'behavior_code': behaviorCode,
        'category': category.name,
        'valence': valence.name,
        'axis': axis.name,
        'plan_status': planStatus.name,
        'confidence': confidence.name,
        'slot_key': slotKey,
        'idempotency_key': idempotencyKey,
        'answers_json': answers,
        'metrics_json': metrics,
        'interpretation': interpretation,
        'dose_fraction': doseFraction,
        'source': source,
        'created_at': createdAt.toIso8601String(),
        'session_id': sessionId,
        'notes_json': notes,
        'warnings_json': warnings,
        'revision': revision,
        'is_interruption': isInterruption ? 1 : 0,
      };
}

/// 一次采集会话。保存问答轨迹，用于"事后补全"和问题设计的自我评估。
class CaptureSession {
  CaptureSession({
    required this.id,
    required this.startedAt,
    required this.entrySource,
    this.dayKey,
    this.behaviorCode,
    this.rawText,
    this.endedAt,
    this.stage = CaptureStage.intent,
    this.answeredCount = 0,
    this.abandoned = false,
    this.usedSameAsLast = false,
    this.usedVoice = false,
    this.confidenceCeiling = Confidence.calibrated,
    final List<Map<String, Object?>>? trace,
  }) : trace = trace ?? <Map<String, Object?>>[];

  final String id;
  final DateTime startedAt;
  DateTime? endedAt;

  DayKey? dayKey;
  String? behaviorCode;

  /// 用户最初那句人话，原样保存。
  String? rawText;

  CaptureStage stage;
  int answeredCount;
  bool abandoned;
  bool usedSameAsLast;
  bool usedVoice;

  /// 一旦出现"不确定/跳过"，本次会话的置信度上限就被压到 selfReport。
  Confidence confidenceCeiling;

  /// 问答轨迹：{qid, kind, value, skipped, at}。
  final List<Map<String, Object?>> trace;

  final String entrySource;

  /// 单次录入耗时（秒）。产品目标是 ≤30 秒，这个字段用来验证目标。
  int? get durationSeconds => endedAt == null
      ? null
      : endedAt!.difference(startedAt).inSeconds;

  void record({
    required String questionId,
    required QuestionKind kind,
    Object? value,
    bool skipped = false,
  }) {
    answeredCount++;
    if (skipped || value == kUnknownValueSentinel) {
      confidenceCeiling = Confidence.selfReport;
    }
    trace.add({
      'qid': questionId,
      'kind': kind.name,
      'value': value,
      'skipped': skipped,
      'at': DateTime.now().toIso8601String(),
    });
  }
}

const String kUnknownValueSentinel = '__unknown__';
