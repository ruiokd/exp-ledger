/// 等级曲线与缓冲池。
///
/// 门槛公式：升至 n 级累计 EXP = 100 × n^1.6（本项目自定的游戏化数值，
/// 不是任何科学曲线，UI 上必须与生理公式区分开）。
///
/// 非对称设计：
///   · 正向累积慢，但不会归零；
///   · 负向先扣"缓冲池"，池子空了才动等级；
///   · 掉级必须同时产出解释与回升路径，不允许静默降级。
library;

import 'package:exp_ledger/core/config/balance_config.dart';
import 'package:exp_ledger/core/util/num_ext.dart';
import 'package:exp_ledger/domain/models/state_vars.dart';

class LevelState {
  const LevelState({
    required this.level,
    required this.totalExp,
    required this.buffer,
  });

  final int level;
  final double totalExp;

  /// 缓冲池：专门用来吸收负向经验，避免一次熬夜就掉级。
  final double buffer;

  static const LevelState zero = LevelState(level: 0, totalExp: 0, buffer: 0);

  /// 距离下一级还差多少。
  double expToNext(BalanceConfig? cfg) {
    final c = cfg ?? kDefaultConfig;
    return c.levelThreshold(level + 1) - totalExp;
  }

  /// 当前等级内的进度 0–1。
  double progress(BalanceConfig? cfg) {
    final c = cfg ?? kDefaultConfig;
    final lo = c.levelThreshold(level);
    final hi = c.levelThreshold(level + 1);
    if (hi <= lo) return 0;
    return ((totalExp - lo) / (hi - lo)).clampRange(0, 1);
  }

  Map<String, Object?> toRow() => {
        'level': level,
        'total_exp': totalExp,
        'buffer': buffer,
      };
}

/// 当前等级到下一级的跨度。
double levelSpan(int level, BalanceConfig? cfg) {
  final c = cfg ?? kDefaultConfig;
  return c.levelThreshold(level + 1) - c.levelThreshold(level);
}

/// 应用一次经验变动。正负走完全不同的路径。
LevelState applyExp(LevelState state, double delta, [BalanceConfig? cfg]) {
  final c = cfg ?? kDefaultConfig;
  if (delta == 0) return state;

  if (delta > 0) {
    final total = state.totalExp + delta;
    final cap = levelSpan(c.levelFor(total), c) * c.levelBufferRatio;
    var buffer = state.buffer + delta * 0.35;
    if (buffer > cap) buffer = cap;
    return LevelState(
      level: c.levelFor(total),
      totalExp: total,
      buffer: buffer.clampRange(0, 1e9),
    );
  }

  var debt = -delta;
  var buffer = state.buffer;
  final used = debt < buffer ? debt : buffer;
  buffer -= used;
  debt -= used;
  final total = state.totalExp - debt;
  return LevelState(
    level: c.levelFor(total),
    totalExp: total,
    buffer: buffer.clampRange(0, 1e9),
  );
}

/// 掉级解释。必须包含三件事：发生了什么、为什么、怎么回来。
String? explainDrop({
  required LevelState before,
  required LevelState after,
  required StateVars state,
  BalanceConfig? cfg,
}) {
  final c = cfg ?? kDefaultConfig;
  if (after.level >= before.level) return null;
  final need = c.levelThreshold(before.level) - after.totalExp;
  final hints = <String>[];
  if (state.sleepDebtHours > 0.5) {
    hints.add('连续 3 晚在 ${_sleepLineHint(c)} 前入睡，可回补约 60% 的睡眠负债');
  }
  if (state.damageLoad > 1) {
    hints.add('接下来 3 天把训练量降到平时的 60%，损伤负荷会慢慢降下来');
  }
  if (hints.isEmpty) {
    hints.add('把接下来三天的记录补全，趋势会在图上自己走回来');
  }
  return '这次结算让等级从 ${before.level} 回落到 ${after.level}：'
      '缓冲池已经用完，还差 ${need.ceil()} 点经验回到原等级。'
      '${hints.join('；')}。等级回落不会清空任何已有记录。';
}

/// 缓冲池状态的中性描述。
String bufferNote(LevelState s, BalanceConfig? cfg) {
  final c = cfg ?? kDefaultConfig;
  final cap = levelSpan(s.level, c) * c.levelBufferRatio;
  if (cap <= 0) return '';
  final pct = (s.buffer / cap * 100).round();
  return '缓冲池 $pct%（上限 $cap 点）。负向经验先扣这里，扣完才会影响等级。';
}

String _sleepLineHint(BalanceConfig c) {
  final h = c.defaultSleepLineHour.toString().padLeft(2, '0');
  final m = c.defaultSleepLineMinute.toString().padLeft(2, '0');
  return '$h:$m';
}
