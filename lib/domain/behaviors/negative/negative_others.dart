import 'package:exp_ledger/core/util/num_ext.dart';
import 'package:exp_ledger/domain/enums.dart';
import 'package:exp_ledger/domain/models/behavior_def.dart';
import 'package:exp_ledger/domain/models/capture_question.dart';
import 'package:exp_ledger/domain/models/project_axis.dart';
import 'package:exp_ledger/domain/science/sleep_metrics.dart';

import '../qbuild.dart';

/// 负向行为的通用推导：把"越界量"折算成曲线的横轴（分钟当量），
/// 再给出预计扣分。真正的 EXP 由 ValenceEngine 统一结算，
/// 这里只是让用户在确认前就看到后果——不确认不许落库。
DerivedResult buildNegResult({
  required DeriveContext ctx,
  required String slotKey,
  required double curveMinutes,
  required String interpretation,
  required List<ReceiptLine> lines,
  Map<String, double> metrics = const {},
  List<String> notes = const [],
  List<String> warnings = const [],
}) {
  final penalty = ctx.config.negativeDoseCurve(curveMinutes);
  final estExp = ctx.config.negativeDoseExp(curveMinutes);
  return DerivedResult(
    slotKey: slotKey,
    interpretation: interpretation,
    lines: [
      ...lines,
      ReceiptLine(
        '预计扣分',
        '${estExp.toStringAsFixed(1)} EXP（越界越深扣得越快）',
        emphasis: true,
      ),
    ],
    metrics: {
      'curve_minutes': curveMinutes,
      'penalty_units': penalty,
      'estimated_exp': estExp,
      'exp_sign': -1,
      ...metrics,
    },
    normalized: {...ctx.answers},
    confidence: ctx.resolveConfidence(Confidence.selfReport),
    doseFraction: 0,
    notes: notes,
    warnings: warnings,
  );
}

// ------------------------------------------------------------ 睡眠不足（自动派生）

/// 睡眠不足不单独录入——它由睡眠流程自动派生，避免与"熬夜"双计。
/// 这条记录存在的意义，是让明细页能显示"这一项的根因是睡眠"。
final BehaviorDef sleepInsufficientBehavior = BehaviorDef(
  code: 'sleep_insufficient',
  name: '睡眠不足',
  category: BehaviorCategory.negative,
  valence: Valence.negative,
  axis: ProjectAxis.discipline,
  iconName: 'moon_off',
  userCaptureable: false,
  aliases: const [],
  standardDefinition: '有效睡眠时长低于个人需求基准 1 小时以上，判定为睡眠不足。',
  misconception: '周末补觉能缓解困倦，但补不回连续一周欠下的全部。',
  targetDose: 0,
  doseUnit: '小时',
  questions: const [],
  derive: (ctx) {
    final gap = ctx.numOr('gap_hours', 0);
    return buildNegResult(
      ctx: ctx,
      slotKey: 'derived',
      curveMinutes: gap * 60,
      interpretation: '睡眠缺口 ${gap.toStringAsFixed(1)} 小时',
      lines: [ReceiptLine('缺口', humanizeHours(gap))],
      metrics: {'gap_hours': gap},
    );
  },
);

// ------------------------------------------------------------ 久坐

final BehaviorDef sedentaryBehavior = BehaviorDef(
  code: 'sedentary',
  name: '久坐',
  category: BehaviorCategory.negative,
  valence: Valence.negative,
  axis: ProjectAxis.discipline,
  iconName: 'chair',
  aliases: const ['久坐', '坐了一天', '没动', '一直坐着', '躺了一天'],
  keywords: const ['小时', '坐着'],
  standardDefinition:
      '1 段久坐 = 连续坐着超过 60 分钟没有起身。'
      '本项目只对"超出 60 分钟且没有打断"的部分计时。',
  misconception: '一天里插 3 次 5 分钟起身，比"晚上补一次运动"更能抵消久坐的影响。',
  targetDose: 0,
  doseUnit: '小时',
  questions: [
    numQ('hours', '今天坐了很久吗？', '只算连续坐着没起来的时间。',
        min: 0, max: 18, initial: 6, step: 0.5, decimals: 1, unit: ' 小时', rangeHint: '低于 4 小时算轻'),
    choiceQ('breaks', '中途有起来走动吗？', '打断次数直接决定这一段要不要扣。', const [
      QuestionOption('many', '每小时都会起来'),
      QuestionOption('some', '起来过几次'),
      QuestionOption('none', '基本没动'),
    ]),
  ],
  derive: (ctx) {
    final hours = ctx.numOr('hours', 0);
    final breaks = ctx.strOr('breaks', 'some');
    final breakFactor = switch (breaks) { 'many' => 0.4, 'none' => 1.0, _ => 0.75 };
    // 超过 4 小时才进入扣分区间，4 小时以内只记录不扣分。
    final over = (hours - 4).clampRange(0, 14);
    final curveMinutes = over * 60 * breakFactor;
    return buildNegResult(
      ctx: ctx,
      slotKey: 'day',
      curveMinutes: curveMinutes,
      interpretation: '久坐 ${hours.toStringAsFixed(1)} 小时，打断情况：$breaks',
      lines: [
        ReceiptLine('久坐时长', '${hours.toStringAsFixed(1)} 小时'),
        ReceiptLine('打断折算', '×${breakFactor.toStringAsFixed(2)}'),
        ReceiptLine('超出部分', '${over.toStringAsFixed(1)} 小时'),
      ],
      metrics: {'hours': hours, 'over_hours': over},
      notes: [
        if (over > 0) '下一个整点起来走 2 分钟，这一段就能被抵消一部分。',
      ],
    );
  },
);

// ------------------------------------------------------------ 饮酒

final BehaviorDef alcoholBehavior = BehaviorDef(
  code: 'alcohol_over',
  name: '超量饮酒',
  category: BehaviorCategory.negative,
  valence: Valence.negative,
  axis: ProjectAxis.discipline,
  iconName: 'glass',
  aliases: const ['喝酒', '喝多了', '啤酒', '白酒', '烈酒', '微醺', '醉了'],
  keywords: const ['杯', '瓶', '两', 'ml'],
  standardDefinition:
      '1 标准杯 ≈ 14 g 纯酒精 ≈ 啤酒 350 ml / 葡萄酒 150 ml / 烈酒 45 ml。'
      '超过 2 标准杯即进入负向区间。',
  misconception: '喝酒助眠是错觉：它缩短入睡时间，但会显著破坏后半夜的深睡与 REM。',
  targetDose: 0,
  doseUnit: '标准杯',
  questions: [
    numQ('drinks', '喝了几标准杯？', '按 14 g 纯酒精折算成一标准杯。',
        min: 0, max: 20, initial: 3, step: 1, unit: ' 杯', rangeHint: '2 杯以内属低风险'),
    choiceQ('late', '几点喝完的？', '离睡觉越近，对睡眠结构影响越大。', const [
      QuestionOption('early', '睡前 3 小时以上'),
      QuestionOption('mid', '睡前 1–3 小时'),
      QuestionOption('late', '睡前 1 小时内'),
    ]),
  ],
  derive: (ctx) {
    final drinks = ctx.numOr('drinks', 0);
    final timing = ctx.strOr('late', 'mid');
    final timingFactor = switch (timing) { 'early' => 0.8, 'late' => 1.25, _ => 1.0 };
    final over = (drinks - 2).clampRange(0, 18);
    // 折算：1 标准杯超出量 ≈ 30 分钟当量（启发式映射，只为复用同一条加速曲线）。
    final curveMinutes = over * 30 * timingFactor;
    return buildNegResult(
      ctx: ctx,
      slotKey: 'day',
      curveMinutes: curveMinutes,
      interpretation: '$drinks 标准杯，超出 ${over.toStringAsFixed(0)} 杯',
      lines: [
        ReceiptLine('摄入', '$drinks 标准杯（约 ${(drinks * 14).round()} g 酒精）'),
        ReceiptLine('超出量', '${over.toStringAsFixed(0)} 杯'),
        ReceiptLine('时间系数', '×${timingFactor.toStringAsFixed(2)}'),
      ],
      metrics: {'drinks': drinks, 'over_drinks': over, 'alcohol_g': drinks * 14},
      notes: [if (over > 0) '今晚多喝一杯水，明早的静息心率通常会告诉你答案。'],
    );
  },
);

// ------------------------------------------------------------ 含糖饮料

final BehaviorDef sugaryDrinkBehavior = BehaviorDef(
  code: 'sugary_drink',
  name: '含糖饮料',
  category: BehaviorCategory.negative,
  valence: Valence.negative,
  axis: ProjectAxis.discipline,
  iconName: 'soda',
  aliases: const ['可乐', '奶茶', '含糖饮料', '甜饮料', '果汁', '汽水'],
  keywords: const ['杯', '瓶', '糖'],
  standardDefinition: '1 杯 = 500 ml 含糖饮料（约 50 g 糖）。超过 1 杯即进入负向区间。',
  misconception: '"零糖"饮料通常不含糖但含甜味剂，本项目只计糖，不评价甜味剂。',
  targetDose: 0,
  doseUnit: '杯',
  questions: [
    numQ('cups', '喝了几杯？', '一杯按 500 ml 估。',
        min: 0, max: 10, initial: 1, step: 1, unit: ' 杯', rangeHint: '0 杯最好，1 杯属常见'),
  ],
  derive: (ctx) {
    final cups = ctx.numOr('cups', 0);
    final over = (cups - 1).clampRange(0, 9);
    final curveMinutes = over * 40;
    return buildNegResult(
      ctx: ctx,
      slotKey: 'day',
      curveMinutes: curveMinutes,
      interpretation: '$cups 杯含糖饮料（约 ${(cups * 50).round()} g 糖）',
      lines: [
        ReceiptLine('摄入', '$cups 杯'),
        ReceiptLine('折合糖', '${(cups * 50).round()} g'),
      ],
      metrics: {'cups': cups, 'sugar_g': cups * 50},
    );
  },
);

// ------------------------------------------------------------ 暴食 / 超加工

final BehaviorDef bingeEatingBehavior = BehaviorDef(
  code: 'binge_eating',
  name: '过量进食',
  category: BehaviorCategory.negative,
  valence: Valence.negative,
  axis: ProjectAxis.discipline,
  iconName: 'bowl',
  aliases: const ['暴食', '吃撑了', '吃太多', '宵夜', '超加工', '炸鸡', '外卖'],
  keywords: const ['撑', '过量'],
  standardDefinition:
      '过量 = 吃到明显超过平时的舒适饱腹感，且事后有身体不适。'
      '只是"比计划多吃一点"不计入负向。',
  misconception: '偶尔吃撑不等于失控，单次事件扣分很小，真正的问题是它是否变成了每周三次。',
  targetDose: 0,
  doseUnit: '次',
  questions: [
    choiceQ('degree', '吃到什么程度？', '只有到"身体不舒服"才计入负向。', const [
      QuestionOption('mild', '比平时多一点'),
      QuestionOption('full', '吃撑了'),
      QuestionOption('pain', '撑到难受'),
    ]),
    choiceQ('ultra', '主要是什么？', '超加工食品更容易让人吃过头。', const [
      QuestionOption('home', '正常的饭菜'),
      QuestionOption('mixed', '一半一半'),
      QuestionOption('ultra', '炸物/零食/外卖为主'),
    ]),
  ],
  derive: (ctx) {
    final degree = ctx.strOr('degree', 'full');
    final ultra = ctx.strOr('ultra', 'mixed');
    final base = switch (degree) { 'mild' => 0.0, 'pain' => 90.0, _ => 45.0 };
    final ultraFactor = switch (ultra) { 'home' => 0.7, 'ultra' => 1.3, _ => 1.0 };
    final curveMinutes = base * ultraFactor;
    return buildNegResult(
      ctx: ctx,
      slotKey: 'day',
      curveMinutes: curveMinutes,
      interpretation: '过量进食（$degree，$ultra）',
      lines: [
        ReceiptLine('程度', degree == 'mild' ? '轻微超出' : (degree == 'pain' ? '撑到难受' : '吃撑')),
        ReceiptLine('来源', ultra == 'ultra' ? '以超加工为主' : (ultra == 'home' ? '正常饭菜' : '各半')),
      ],
      metrics: {'curve_base': base},
      notes: [
        if (degree == 'mild') '这次没有达到计入负向的程度，只做了记录。',
      ],
    );
  },
);

// ------------------------------------------------------------ 漏复习

final BehaviorDef missedReviewBehavior = BehaviorDef(
  code: 'missed_review',
  name: '漏复习',
  category: BehaviorCategory.negative,
  valence: Valence.negative,
  axis: ProjectAxis.memory,
  iconName: 'book_off',
  aliases: const ['没复习', '漏复习', '忘了背', '没背单词', '断了'],
  keywords: const ['词', '复习'],
  standardDefinition:
      '漏复习 = 计划内应当复习但未完成的词数。'
      '按词数计，不按天数计——一天漏 50 个比三天各漏 5 个更严重。',
  misconception: '漏一天不会让记忆归零，但会让下一次复习的成本明显上升。',
  targetDose: 0,
  doseUnit: '词',
  questions: [
    numQ('words', '有多少词该复习没复习？', '按你设定的复习计划算。',
        min: 0, max: 500, initial: 20, step: 5, unit: ' 个', rangeHint: '常规 0–30 个'),
  ],
  derive: (ctx) {
    final words = ctx.numOr('words', 0);
    final curveMinutes = words * 1.5;
    return buildNegResult(
      ctx: ctx,
      slotKey: 'day',
      curveMinutes: curveMinutes,
      interpretation: '$words 个词漏了复习',
      lines: [ReceiptLine('漏复习', '$words 个')],
      metrics: {'words': words},
      notes: ['补的时候不用一次补完，拆成两天各一半，效果更好。'],
    );
  },
);

// ------------------------------------------------------------ 缺席训练

final BehaviorDef trainingAbsenceBehavior = BehaviorDef(
  code: 'training_absence',
  name: '缺训',
  category: BehaviorCategory.negative,
  valence: Valence.negative,
  axis: ProjectAxis.strength,
  iconName: 'dumbbell_off',
  aliases: const ['没练', '请假', '缺训', '跳过一次', '今天没去'],
  keywords: const ['训练', '计划'],
  standardDefinition: '缺训 = 计划内安排了训练但没有执行的一次课。临时调整不算缺训。',
  misconception: '一次缺训不会让你掉肌肉，连续两周才会——所以这个扣分是缓的。',
  targetDose: 0,
  doseUnit: '次',
  questions: [
    choiceQ('reason', '为什么没练？', '原因决定这是"中断期"还是"缺训"。', const [
      QuestionOption('busy', '太忙/加班'),
      QuestionOption('tired', '太累/没睡好'),
      QuestionOption('sick', '身体不舒服'),
      QuestionOption('lazy', '就是不想动'),
    ]),
  ],
  derive: (ctx) {
    final reason = ctx.strOr('reason', 'busy');
    // 生病/受伤走"中断期"，不算负向；其余按一次课的当量计。
    final interruption = reason == 'sick';
    final curveMinutes = interruption ? 0.0 : 60.0;
    return buildNegResult(
      ctx: ctx,
      slotKey: 'day',
      curveMinutes: curveMinutes,
      interpretation: interruption ? '身体不适，记为中断期' : '缺训一次（$reason）',
      lines: [
        ReceiptLine('原因', switch (reason) {
          'busy' => '太忙/加班',
          'tired' => '太累/没睡好',
          'sick' => '身体不舒服',
          _ => '就是不想动',
        }),
        if (interruption) const ReceiptLine('处理', '记为中断期，不扣成长分'),
      ],
      metrics: {'interruption': interruption ? 1 : 0},
      notes: [
        if (interruption) '中断期不扣分，能力值只按自然衰减走，不用补回来。',
        if (reason == 'tired') '如果是缺觉导致的缺训，根因已经记在睡眠那一项上，这里不重复扣。',
      ],
    );
  },
);

// ------------------------------------------------------------ 无意识刷手机

final BehaviorDef doomscrollingBehavior = BehaviorDef(
  code: 'doomscrolling',
  name: '无意识刷手机',
  category: BehaviorCategory.negative,
  valence: Valence.negative,
  axis: ProjectAxis.discipline,
  iconName: 'phone',
  aliases: const ['刷手机', '刷短视频', '刷了一晚上', '看手机', '滑手机'],
  keywords: const ['视频', '抖音', '无意识'],
  standardDefinition:
      '无意识刷 = 打开时没打算看、放下时说不出看了什么的时间。'
      '有目的地查资料不算。',
  misconception: '关键不是时长，而是"是不是你决定的"——主动看 1 小时和被动刷 20 分钟，成本不同。',
  targetDose: 0,
  doseUnit: '分钟',
  questions: [
    minutesQ('minutes', '大概刷了多久？', '估个量级就行。', initial: 60, max: 600, rangeHint: '超过 60 分钟进入扣分区间'),
    choiceQ('intent', '是主动打开的吗？', '这决定它算不算"无意识"。', const [
      QuestionOption('active', '有事要查'),
      QuestionOption('mixed', '本来有事，刷偏了'),
      QuestionOption('passive', '没事，就是手滑开的'),
    ]),
  ],
  derive: (ctx) {
    final minutes = ctx.numOr('minutes', 0);
    final intent = ctx.strOr('intent', 'passive');
    final factor = switch (intent) { 'active' => 0.25, 'mixed' => 0.7, _ => 1.0 };
    final over = (minutes - 60).clampRange(0, 540) * factor;
    return buildNegResult(
      ctx: ctx,
      slotKey: 'day',
      curveMinutes: over,
      interpretation: '刷手机 $minutes 分钟（$intent）',
      lines: [
        ReceiptLine('时长', '${minutes.toStringAsFixed(0)} 分钟'),
        ReceiptLine('主动系数', '×${factor.toStringAsFixed(2)}'),
        ReceiptLine('计入部分', '${over.toStringAsFixed(0)} 分钟'),
      ],
      metrics: {'minutes': minutes, 'counted_minutes': over},
      notes: [
        if (intent == 'active') '主动查资料的部分只按 25% 计入，几乎不会扣分。',
      ],
    );
  },
);

// ------------------------------------------------------------ 吸烟

final BehaviorDef smokingBehavior = BehaviorDef(
  code: 'smoking',
  name: '吸烟',
  category: BehaviorCategory.negative,
  valence: Valence.negative,
  axis: ProjectAxis.discipline,
  iconName: 'smoke',
  aliases: const ['抽烟', '吸烟', '抽了几根', '烟'],
  keywords: const ['支', '根', '包'],
  standardDefinition: '1 支 = 一根香烟/一支电子烟。按支数计，不按包计。',
  misconception: '减量有意义，但心血管风险不是线性下降的——这里的扣分只是记录，不是医学评估。',
  targetDose: 0,
  doseUnit: '支',
  questions: [
    numQ('sticks', '今天抽了几支？', '按支计，方便看趋势。',
        min: 0, max: 60, initial: 3, step: 1, unit: ' 支', rangeHint: '0 支是唯一低风险值'),
  ],
  derive: (ctx) {
    final sticks = ctx.numOr('sticks', 0);
    final curveMinutes = sticks * 25;
    return buildNegResult(
      ctx: ctx,
      slotKey: 'day',
      curveMinutes: curveMinutes,
      interpretation: '$sticks 支烟',
      lines: [ReceiptLine('数量', '$sticks 支')],
      metrics: {'sticks': sticks},
      notes: [
        if (sticks > 0) '这条记录的用途是让你看见趋势，不是给你打分。',
      ],
    );
  },
);

final List<BehaviorDef> negativeOthers = [
  sleepInsufficientBehavior,
  sedentaryBehavior,
  alcoholBehavior,
  sugaryDrinkBehavior,
  bingeEatingBehavior,
  missedReviewBehavior,
  trainingAbsenceBehavior,
  doomscrollingBehavior,
  smokingBehavior,
];
