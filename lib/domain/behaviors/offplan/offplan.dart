import 'package:exp_ledger/domain/enums.dart';
import 'package:exp_ledger/domain/models/behavior_def.dart';
import 'package:exp_ledger/domain/models/capture_question.dart';
import 'package:exp_ledger/domain/models/project_axis.dart';

import '../qbuild.dart';

/// 计划外事件的统一回执：不预先算分，只把"这属于哪一类"讲清楚。
/// 最终是"有益超额"还是"过量风险"，要看近 7 天负荷，由引擎判定。
DerivedResult buildOffPlanResult({
  required DeriveContext ctx,
  required String slotKey,
  required String kind,
  required String interpretation,
  required List<ReceiptLine> lines,
  Map<String, double> metrics = const {},
  List<String> notes = const [],
  List<String> warnings = const [],
  double doseRatio = 0.6,
}) {
  return DerivedResult(
    slotKey: slotKey,
    interpretation: interpretation,
    lines: [
      ...lines,
      const ReceiptLine('处理方式', '确认后按你近 7 天的负荷判定'),
    ],
    metrics: {
      'offplan_kind': switch (kind) {
        'beneficial' => 1,
        'risk' => 2,
        'interruption' => 3,
        _ => 0,
      },
      'exp_sign': 0,
      ...metrics,
    },
    normalized: {...ctx.answers, 'offplan_kind': kind},
    confidence: ctx.resolveConfidence(Confidence.selfReport),
    doseFraction: kind == 'interruption' ? 0 : doseRatio,
    notes: notes,
    warnings: warnings,
  );
}

// ------------------------------------------------------------ 临时加练

final BehaviorDef extraTrainingBehavior = BehaviorDef(
  code: 'extra_training',
  name: '临时加练',
  category: BehaviorCategory.offPlan,
  valence: Valence.offPlan,
  axis: ProjectAxis.strength,
  iconName: 'plus_dumbbell',
  aliases: const ['加练', '多练了一组', '又去练了', '补练', '临时加练'],
  keywords: const ['额外', '加'],
  standardDefinition:
      '加练 = 计划外新增的一次训练或额外组数。'
      '判定分流：在个人适应范围内按 0.6 次幂衰减计加分；超出安全上限则不加分，转入损伤负荷。',
  misconception: '"多练总比少练好"只在恢复跟得上的时候成立，恢复不足时加练是负收益。',
  targetDose: 1,
  doseUnit: '次',
  questions: [
    choiceQ('kind', '加了什么？', '不同形式对恢复的压力不同。', const [
      QuestionOption('session', '整节课'),
      QuestionOption('sets', '额外几组'),
      QuestionOption('cardio', '额外有氧'),
    ]),
    numQ('magnitude', '加了多少？', '按组数或分钟估。',
        min: 1, max: 200, initial: 3, step: 1, unit: '', rangeHint: '常规 2–6 组'),
    choiceQ('fatigue', '加之前状态如何？', '疲劳状态下加练，风险会放大。', const [
      QuestionOption('fresh', '状态不错'),
      QuestionOption('ok', '正常'),
      QuestionOption('tired', '已经很累'),
    ]),
  ],
  derive: (ctx) {
    final fatigue = ctx.strOr('fatigue', 'ok');
    final magnitude = ctx.numOr('magnitude', 0);
    final tired = fatigue == 'tired';
    return buildOffPlanResult(
      ctx: ctx,
      slotKey: ctx.strOr('kind', 'sets'),
      kind: tired ? 'risk' : 'beneficial',
      interpretation: tired
          ? '疲劳状态下加练 $magnitude，偏向过量风险'
          : '计划外加练 $magnitude，偏向有益超额',
      lines: [
        ReceiptLine('形式', switch (ctx.strOr('kind', 'sets')) {
          'session' => '整节课',
          'cardio' => '额外有氧',
          _ => '额外几组',
        }),
        ReceiptLine('量', '${magnitude.toStringAsFixed(0)}'),
        ReceiptLine('加练前状态', switch (fatigue) {
          'fresh' => '不错',
          'tired' => '已经很累',
          _ => '正常',
        }),
      ],
      metrics: {'magnitude': magnitude, 'fatigue': tired ? 1 : 0},
      notes: [
        if (!tired) '超额部分按边际递减计分——第 4 组的价值低于第 1 组，这是故意设计的。',
        if (tired) '疲劳叠加时，超出的部分会转成损伤负荷而不是经验。',
      ],
      warnings: [
        if (tired) '如果同时缺觉，建议今天到此为止。',
      ],
    );
  },
);

// ------------------------------------------------------------ 临时加量

final BehaviorDef extraLoadBehavior = BehaviorDef(
  code: 'extra_load',
  name: '临时加量',
  category: BehaviorCategory.offPlan,
  valence: Valence.offPlan,
  axis: ProjectAxis.strength,
  iconName: 'weight',
  aliases: const ['加重量', '冲了个大重量', '试了新重量', '加片'],
  keywords: const ['重量', 'kg', 'PR'],
  standardDefinition: '加量 = 在计划外提高了重量或次数。判定同上，看是否超出安全上限。',
  misconception: '突然加重量带来的力量增长很快会消失，神经适应不等于肌肉增长。',
  targetDose: 1,
  doseUnit: '次',
  questions: [
    numQ('percent', '比平时多了多少？', '按百分比估最直观。',
        min: 0, max: 100, initial: 10, step: 5, unit: ' %', rangeHint: '5–10% 属常规进阶'),
    choiceQ('form', '动作还稳吗？', '动作崩了的那部分不算刺激，只算风险。', const [
      QuestionOption('good', '很稳'),
      QuestionOption('ok', '有点勉强'),
      QuestionOption('bad', '明显变形'),
    ]),
  ],
  derive: (ctx) {
    final percent = ctx.numOr('percent', 0);
    final form = ctx.strOr('form', 'ok');
    final risk = form == 'bad' || percent > 25;
    return buildOffPlanResult(
      ctx: ctx,
      slotKey: 'load',
      kind: risk ? 'risk' : 'beneficial',
      interpretation: '比平时加 ${percent.toStringAsFixed(0)}%${risk ? '，超出安全区间' : ''}',
      lines: [
        ReceiptLine('增量', '+${percent.toStringAsFixed(0)}%'),
        ReceiptLine('动作质量', switch (form) {
          'good' => '很稳',
          'bad' => '明显变形',
          _ => '有点勉强',
        }),
      ],
      metrics: {'percent': percent},
      notes: [
        if (!risk) '小幅渐进加量是最稳的进步方式。',
        if (risk) '这次超出的部分不会换成经验，会记成损伤负荷。',
      ],
      warnings: [
        if (risk) '如果出现关节刺痛，先停下，别用"忍一下"换 PR。',
      ],
    );
  },
);

// ------------------------------------------------------------ 额外学习

final BehaviorDef extraStudyBehavior = BehaviorDef(
  code: 'extra_study',
  name: '额外学习',
  category: BehaviorCategory.offPlan,
  valence: Valence.offPlan,
  axis: ProjectAxis.memory,
  iconName: 'plus_book',
  aliases: const ['多学了', '额外学习', '又看了一会', '加班学'],
  keywords: const ['额外', '学'],
  standardDefinition: '额外学习 = 计划外的学习时段。按 0.6 次幂衰减计入，超过 3 小时转入疲劳风险。',
  misconception: '熬夜多学的两小时，第二天的效率损失常常超过它带来的收益。',
  targetDose: 1,
  doseUnit: '次',
  questions: [
    minutesQ('minutes', '多学了多久？', '按分钟估。', initial: 30, rangeHint: '30–60 分钟最常见'),
    choiceQ('timing', '什么时候学的？', '深夜学习的隐性成本最高。', const [
      QuestionOption('day', '白天'),
      QuestionOption('evening', '晚上'),
      QuestionOption('late', '已经很晚了'),
    ]),
  ],
  derive: (ctx) {
    final minutes = ctx.numOr('minutes', 0);
    final timing = ctx.strOr('timing', 'evening');
    final risk = timing == 'late' || minutes > 180;
    return buildOffPlanResult(
      ctx: ctx,
      slotKey: 'study',
      kind: risk ? 'risk' : 'beneficial',
      interpretation: '额外学习 ${minutes.toStringAsFixed(0)} 分钟（$timing）',
      lines: [
        ReceiptLine('时长', '${minutes.toStringAsFixed(0)} 分钟'),
        ReceiptLine('时段', switch (timing) {
          'day' => '白天',
          'late' => '已经很晚',
          _ => '晚上',
        }),
      ],
      metrics: {'minutes': minutes},
      notes: [
        if (risk) '这次大概率会以明天的困倦偿还，因此超额部分按低权重计。',
      ],
    );
  },
);

// ------------------------------------------------------------ 加班

final BehaviorDef overtimeBehavior = BehaviorDef(
  code: 'overtime',
  name: '突发加班',
  category: BehaviorCategory.offPlan,
  valence: Valence.offPlan,
  axis: ProjectAxis.discipline,
  iconName: 'briefcase',
  aliases: const ['加班', '赶工', '临时有事', '忙到很晚'],
  keywords: const ['工作', '小时'],
  standardDefinition: '加班 = 计划外的工作时段。记为中断期因素，本身不扣成长分。',
  misconception: '加班不是道德问题，它只是挤掉了恢复的时间——账要记在"被挤掉的那件事"上。',
  targetDose: 0,
  doseUnit: '小时',
  questions: [
    numQ('hours', '加了多久？', '按小时估。',
        min: 0, max: 16, initial: 2, step: 0.5, decimals: 1, unit: ' 小时'),
    choiceQ('impact', '它挤掉了什么？', '这决定这件事要不要单独记一笔。', const [
      QuestionOption('training', '训练'),
      QuestionOption('sleep', '睡眠'),
      QuestionOption('study', '学习'),
      QuestionOption('none', '没挤掉什么'),
    ], allowUnknown: false),
  ],
  derive: (ctx) {
    final hours = ctx.numOr('hours', 0);
    return buildOffPlanResult(
      ctx: ctx,
      slotKey: 'day',
      kind: 'interruption',
      interpretation: '加班 ${hours.toStringAsFixed(1)} 小时',
      lines: [
        ReceiptLine('时长', '${hours.toStringAsFixed(1)} 小时'),
        const ReceiptLine('处理', '记为中断期，不扣成长分'),
      ],
      metrics: {'hours': hours},
      notes: [
        if (ctx.strOr('impact', 'none') == 'sleep')
          '如果因此睡晚了，那一项会照实记录；这里不再重复扣。',
      ],
    );
  },
);

// ------------------------------------------------------------ 生病

final BehaviorDef illnessBehavior = BehaviorDef(
  code: 'illness',
  name: '生病',
  category: BehaviorCategory.offPlan,
  valence: Valence.offPlan,
  axis: ProjectAxis.discipline,
  iconName: 'thermometer',
  aliases: const ['生病', '感冒', '发烧', '不舒服', '阳了'],
  keywords: const ['病', '症状'],
  standardDefinition: '生病 = 出现发热、明显乏力、呼吸道或消化道症状等。记为中断期。',
  misconception: '带病训练不会让你更强，只会让病程更长——这一项永远不扣分。',
  targetDose: 0,
  doseUnit: '天',
  questions: [
    choiceQ('severity', '大概什么程度？', '只用来决定要不要提示就医。', const [
      QuestionOption('mild', '轻微，能正常活动'),
      QuestionOption('moderate', '明显不适，想躺着'),
      QuestionOption('severe', '发烧/剧烈症状'),
    ]),
  ],
  derive: (ctx) {
    final severity = ctx.strOr('severity', 'mild');
    return buildOffPlanResult(
      ctx: ctx,
      slotKey: 'day',
      kind: 'interruption',
      interpretation: '生病（$severity），记为中断期',
      lines: [
        ReceiptLine('程度', switch (severity) {
          'severe' => '发烧/剧烈症状',
          'moderate' => '明显不适',
          _ => '轻微',
        }),
        const ReceiptLine('处理', '中断期：不扣分，能力值按自然衰减走'),
      ],
      metrics: {
        'severity': (switch (severity) {
          'severe' => 3,
          'moderate' => 2,
          _ => 1,
        })
            .toDouble(),
      },
      notes: ['这段时间的曲线会自动用特殊底色标出，你不会被误判成懈怠。'],
      warnings: [
        if (severity == 'severe') '持续高热或呼吸困难请及时就医，App 不做诊断。',
      ],
    );
  },
);

// ------------------------------------------------------------ 受伤

final BehaviorDef injuryBehavior = BehaviorDef(
  code: 'injury',
  name: '受伤',
  category: BehaviorCategory.offPlan,
  valence: Valence.offPlan,
  axis: ProjectAxis.strength,
  iconName: 'bandage',
  aliases: const ['受伤', '拉伤', '扭了', '关节疼', '腰疼', '膝盖疼'],
  keywords: const ['痛', '伤'],
  standardDefinition:
      '受伤 = 出现影响动作完成的疼痛或活动受限。记为中断期，并累积到损伤负荷。',
  misconception: '疼痛是信号不是障碍，"练过去"往往把小伤练成大伤。',
  targetDose: 0,
  doseUnit: '次',
  questions: [
    choiceQ('site', '哪里？', '部位决定之后哪些动作要避开。', const [
      QuestionOption('knee', '膝'),
      QuestionOption('back', '腰'),
      QuestionOption('shoulder', '肩'),
      QuestionOption('elbow', '肘/腕'),
      QuestionOption('other', '其他'),
    ]),
    choiceQ('severity', '什么程度？', '只用来决定提示强度。', const [
      QuestionOption('mild', '有点疼，还能动'),
      QuestionOption('moderate', '影响动作了'),
      QuestionOption('severe', '明显疼痛/肿'),
    ]),
  ],
  derive: (ctx) {
    final severity = ctx.strOr('severity', 'mild');
    final site = ctx.strOr('site', 'other');
    final load = switch (severity) { 'severe' => 3.0, 'moderate' => 1.6, _ => 0.6 };
    return buildOffPlanResult(
      ctx: ctx,
      slotKey: site,
      kind: 'interruption',
      interpretation: '受伤（$site，$severity）',
      lines: [
        ReceiptLine('部位', switch (site) {
          'knee' => '膝',
          'back' => '腰',
          'shoulder' => '肩',
          'elbow' => '肘/腕',
          _ => '其他',
        }),
        ReceiptLine('程度', switch (severity) {
          'severe' => '明显疼痛/肿',
          'moderate' => '影响动作',
          _ => '轻微',
        }),
        ReceiptLine('记录', '中断期 + 损伤负荷 +${load.toStringAsFixed(1)}'),
      ],
      metrics: {'injury_load': load, 'severity': severity == 'severe' ? 3 : (severity == 'moderate' ? 2 : 1)},
      warnings: [
        '这段记录会作为损伤负荷累积，影响之后同等训练量的得分权重。',
        if (severity != 'mild') '持续疼痛、肿胀或活动受限，建议就医评估，App 不做诊断。',
      ],
    );
  },
);

// ------------------------------------------------------------ 旅行中断

final BehaviorDef travelBreakBehavior = BehaviorDef(
  code: 'travel_break',
  name: '旅行中断',
  category: BehaviorCategory.offPlan,
  valence: Valence.offPlan,
  axis: ProjectAxis.discipline,
  iconName: 'plane',
  aliases: const ['出差', '旅行', '在外面', '没条件练', '换环境'],
  keywords: const ['天', '出差'],
  standardDefinition: '旅行中断 = 因环境变化连续无法执行原计划。按天计，记为中断期。',
  misconception: '中断期掉的是"神经适应"，不是肌肉本身，恢复起来比你想的快。',
  targetDose: 0,
  doseUnit: '天',
  questions: [
    numQ('days', '预计几天？', '影响衰减曲线的长度。',
        min: 1, max: 60, initial: 5, step: 1, unit: ' 天'),
    choiceQ('canTrain', '有没有条件做点轻的？', '哪怕 10 分钟，也能明显减缓去训练效应。', const [
      QuestionOption('yes', '可以，有场地'),
      QuestionOption('bodyweight', '只能自重'),
      QuestionOption('no', '完全没条件'),
    ]),
  ],
  derive: (ctx) {
    final days = ctx.numOr('days', 0);
    final canTrain = ctx.strOr('canTrain', 'no');
    return buildOffPlanResult(
      ctx: ctx,
      slotKey: 'day',
      kind: 'interruption',
      interpretation: '旅行中断 $days 天（$canTrain）',
      lines: [
        ReceiptLine('天数', '${days.toStringAsFixed(0)} 天'),
        ReceiptLine('条件', switch (canTrain) {
          'yes' => '有场地',
          'bodyweight' => '只能自重',
          _ => '完全没条件',
        }),
        const ReceiptLine('处理', '中断期：不扣分，只按自然衰减'),
      ],
      metrics: {'days': days},
      notes: [
        if (canTrain == 'no') '这段时间图表会用特殊底色，你不会被算成懈怠。',
        if (canTrain != 'no') '做 2 组自重深蹲就能把衰减压掉一半，不用多。',
      ],
    );
  },
);

final List<BehaviorDef> offPlanBehaviors = [
  extraTrainingBehavior,
  extraLoadBehavior,
  extraStudyBehavior,
  overtimeBehavior,
  illnessBehavior,
  injuryBehavior,
  travelBreakBehavior,
];
