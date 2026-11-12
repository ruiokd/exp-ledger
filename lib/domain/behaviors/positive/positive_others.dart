import 'package:exp_ledger/core/util/num_ext.dart';
import 'package:exp_ledger/domain/enums.dart';
import 'package:exp_ledger/domain/models/behavior_def.dart';
import 'package:exp_ledger/domain/models/capture_question.dart';
import 'package:exp_ledger/domain/models/project_axis.dart';
import 'package:exp_ledger/domain/science/energy.dart';

import '../qbuild.dart';

// ---------------------------------------------------------------- 有氧

/// 有氧类型的 MET 三档（低/中/高），参考 Ainsworth MET Compendium (2011)
/// 的常见条目。三档是粗分，个人差异 ±20~30%。
const Map<String, List<double>> _cardioMet = {
  'run': [6.0, 9.8, 11.5],
  'cycle': [4.0, 7.5, 10.0],
  'swim': [5.0, 7.0, 9.5],
  'walk': [3.0, 3.5, 5.0],
  'rope': [8.8, 11.0, 12.3],
  'ball': [5.0, 7.0, 9.0],
};

const Map<String, String> _cardioLabel = {
  'run': '跑步',
  'cycle': '骑行',
  'swim': '游泳',
  'walk': '快走',
  'rope': '跳绳',
  'ball': '球类',
};

final BehaviorDef cardioBehavior = BehaviorDef(
  code: 'cardio',
  name: '有氧',
  category: BehaviorCategory.positive,
  valence: Valence.positive,
  axis: ProjectAxis.cardio,
  iconName: 'heart',
  aliases: const [
    '跑步', '跑了', '骑行', '骑车', '游泳', '快走', '跳绳', '打球', '有氧',
    '慢跑', '跑了步', '跑步机', '椭圆机', '划船机',
  ],
  keywords: const ['公里', '配速', '心率', '喘', '出汗'],
  standardDefinition:
      '1 分钟有氧 = 心率明显上升且能持续说话的连续运动时长。'
      '中途停下超过 3 分钟则按两段计算。',
  misconception: '"走了 1 万步"和"跑了 3 公里"在心率区间上不是一回事，本项目按强度分档。',
  targetDose: 30,
  doseUnit: '分钟',
  needsPlanGate: true,
  questions: [
    choiceQ('type', '哪种有氧？', '不同类型的心肺刺激强度不同。', const [
      QuestionOption('run', '跑步'),
      QuestionOption('cycle', '骑行'),
      QuestionOption('swim', '游泳'),
      QuestionOption('walk', '快走'),
      QuestionOption('rope', '跳绳'),
      QuestionOption('ball', '球类'),
    ]),
    minutesQ('minutes', '动了多久？', '时长是心肺刺激量的底盘。', initial: 30, rangeHint: '常规 20–45 分钟'),
    choiceQ('intensity', '强度大概什么样？', '同样时长，强度差一倍，刺激也差一倍。', const [
      QuestionOption('low', '还能正常聊天'),
      QuestionOption('mid', '微喘，说话变短'),
      QuestionOption('high', '很喘，说不出整句'),
    ], rangeHint: '中等强度对多数人最可持续'),
    numQ('distance', '大概多远？', '有距离就能反推配速，可跳过。',
        min: 0, max: 100, initial: 0, step: 0.5, decimals: 1, unit: ' km', inherit: false),
  ],
  derive: (ctx) {
    final type = ctx.strOr('type', 'run');
    final minutes = ctx.numOr('minutes', 0);
    final intensity = ctx.strOr('intensity', 'mid');
    final idx = switch (intensity) { 'low' => 0, 'high' => 2, _ => 1 };
    final met = (_cardioMet[type] ?? _cardioMet['run']!)[idx] *
        ctx.config.metCardioFactor;
    final kcal = metKcal(met: met, weightKg: ctx.profile.weightKg, minutes: minutes);
    // 心肺刺激量：MET × 分钟。单位是"MET·分钟"，只是相对量，不是绝对生理量。
    final stimulus = met * minutes;
    final label = _cardioLabel[type] ?? '有氧';
    final distance = ctx.numOr('distance', 0);
    final intensityLabel = switch (intensity) {
      'low' => '轻松',
      'high' => '很喘',
      _ => '中等',
    };

    return buildDoseResult(
      ctx: ctx,
      slotKey: type,
      dose: minutes,
      target: 30,
      unit: '分钟',
      interpretation: '$label $minutes 分钟（$intensityLabel）',
      lines: [
        ReceiptLine('项目', label),
        ReceiptLine('时长', '${minutes.toStringAsFixed(0)} 分钟'),
        ReceiptLine('强度档位', 'MET ${met.toStringAsFixed(1)}（简化档位）'),
        ReceiptLine('估算消耗', '约 ${kcal.roundTo(0).toStringAsFixed(0)} kcal'),
        ReceiptLine(
          '心肺刺激量',
          '${stimulus.roundTo(0).toStringAsFixed(0)} MET·分钟',
          emphasis: true,
        ),
        if (distance > 0)
          ReceiptLine(
            '平均配速',
            '${(minutes / distance).toStringAsFixed(1)} 分钟/公里',
          ),
      ],
      metrics: {
        'minutes': minutes,
        'met': met,
        'kcal': kcal,
        'stimulus': stimulus,
        'distance_km': distance,
      },
      confidence: Confidence.formula,
      notes: [
        if (minutes > 90) '超过 90 分钟的连续有氧，注意补液与足部负荷。',
      ],
    );
  },
);

// ---------------------------------------------------------------- 柔韧

final BehaviorDef flexibilityBehavior = BehaviorDef(
  code: 'flexibility',
  name: '柔韧 / 拉伸',
  category: BehaviorCategory.positive,
  valence: Valence.positive,
  axis: ProjectAxis.strength,
  iconName: 'stretch',
  aliases: const ['拉伸', '柔韧', '瑜伽', '泡沫轴', '放松', '开肩', '压腿'],
  keywords: const ['筋膜', '活动度', '酸痛'],
  standardDefinition:
      '1 分钟有效拉伸 = 目标肌群有明显牵拉感且保持呼吸的持续时长。'
      '只是摆个姿势拍照不算。',
  misconception: '拉伸的收益来自"持续张力下的时间"，不是幅度越大越好，弹振式拉伸反而容易伤。',
  targetDose: 10,
  doseUnit: '分钟',
  questions: [
    choiceQ('kind', '做的哪种？', '不同类型对活动度的影响路径不同。', const [
      QuestionOption('static', '静态拉伸'),
      QuestionOption('yoga', '瑜伽'),
      QuestionOption('foam', '泡沫轴放松'),
      QuestionOption('dynamic', '动态热身'),
    ]),
    minutesQ('minutes', '做了多久？', '时长是唯一的剂量单位。', initial: 10, rangeHint: '常规 8–15 分钟'),
    choiceQ('coverage', '覆盖范围', '只拉一个部位和全身过一遍不一样。', const [
      QuestionOption('full', '全身过了一遍'),
      QuestionOption('partial', '只处理了紧张的地方'),
    ]),
  ],
  derive: (ctx) {
    final minutes = ctx.numOr('minutes', 0);
    final full = ctx.strOr('coverage', 'partial') == 'full';
    final effective = full ? minutes : minutes * 0.7;
    return buildDoseResult(
      ctx: ctx,
      slotKey: ctx.strOr('kind', 'static'),
      dose: effective,
      target: 10,
      unit: '分钟',
      interpretation: '柔韧 ${minutes.toStringAsFixed(0)} 分钟${full ? '（全身）' : '（局部）'}',
      lines: [
        ReceiptLine('时长', '${minutes.toStringAsFixed(0)} 分钟'),
        ReceiptLine('折算有效时长', '${effective.toStringAsFixed(0)} 分钟'),
        ReceiptLine('活动度刺激', '+${(effective / 10).toStringAsFixed(1)} 单位', emphasis: true),
      ],
      metrics: {'minutes': minutes, 'effective_minutes': effective},
    );
  },
);

// ---------------------------------------------------------------- 蛋白质

final BehaviorDef proteinBehavior = BehaviorDef(
  code: 'protein_intake',
  name: '蛋白质摄入',
  category: BehaviorCategory.positive,
  valence: Valence.neutral,
  axis: ProjectAxis.discipline,
  iconName: 'protein',
  aliases: const ['蛋白质', '蛋白', '吃肉', '鸡胸', '鸡蛋', '蛋白粉', '补充蛋白'],
  keywords: const ['掌心', '份', '克', 'g'],
  standardDefinition:
      '1 份 ≈ 一个掌心大小的肉/鱼/豆制品 ≈ 25 g 蛋白质。'
      '目标 = 体重(kg) × 1.6 g（常见增肌/保肌参考区间 1.6–2.2 g/kg）。',
  misconception: '一天只在晚餐猛补蛋白，不如分到 3 餐；单次超过约 40 g 的边际利用会下降（此为常用经验值）。',
  targetDose: 1,
  doseUnit: '达标',
  resolveValence: (d) {
    final ratio = d.metrics['protein_ratio'] ?? 0;
    if (ratio >= 0.8) return Valence.positive;
    if (ratio < 0.5) return Valence.negative;
    return Valence.neutral;
  },
  questions: [
    numQ('servings', '今天吃了几份蛋白？', '一份≈一个掌心，比称重更容易估。',
        min: 0, max: 12, initial: 3, step: 1, unit: ' 份', rangeHint: '常规 3–5 份'),
    choiceQ('distribution', '集中在几餐？', '分摊到多餐，利用率通常更好。', const [
      QuestionOption('3', '3 餐都有'),
      QuestionOption('2', '2 餐'),
      QuestionOption('1', '基本集中在一餐'),
    ]),
    choiceQ('ultra', '有没有超加工来源？', '香肠、培根这类也算蛋白，但同时带来别的负荷。', const [
      QuestionOption('no', '没有'),
      QuestionOption('some', '有一点'),
      QuestionOption('most', '主要是'),
    ]),
  ],
  derive: (ctx) {
    final servings = ctx.numOr('servings', 0);
    final grams = servings * 25;
    final targetG = ctx.profile.weightKg * 1.6;
    final ratio = targetG <= 0 ? 0.0 : (grams / targetG).clampRange(0, 2);
    final dist = ctx.intOr('distribution', 2);
    final ultra = ctx.strOr('ultra', 'no');
    final distFactor = switch (dist) { 3 => 1.0, 2 => 0.85, _ => 0.7 };
    final ultraFactor = switch (ultra) { 'no' => 1.0, 'some' => 0.9, _ => 0.75 };

    return buildDoseResult(
      ctx: ctx,
      slotKey: 'day',
      dose: ratio,
      target: 1,
      unit: '达标',
      interpretation: '约 $grams g 蛋白，目标是 ${targetG.round()} g',
      lines: [
        ReceiptLine('估算蛋白', '$grams g（$servings 份 × 25 g）'),
        ReceiptLine('目标', '${targetG.round()} g（体重 × 1.6）'),
        ReceiptLine('达成率', '${(ratio * 100).round()}%', emphasis: true),
        ReceiptLine('质量折算', '分餐 ×${distFactor.toStringAsFixed(2)} · 加工度 ×${ultraFactor.toStringAsFixed(2)}'),
      ],
      metrics: {
        'protein_g': grams,
        'protein_target_g': targetG,
        'protein_ratio': ratio,
        'quality_factor': distFactor * ultraFactor,
      },
      confidence: Confidence.formula,
      notes: [
        if (ratio < 0.8) '蛋白质额度还没到，不用一次补完，下一餐加一份就够。',
      ],
    );
  },
);

// ---------------------------------------------------------------- 蔬果

final BehaviorDef vegetableBehavior = BehaviorDef(
  code: 'vegetable_intake',
  name: '蔬果',
  category: BehaviorCategory.positive,
  valence: Valence.positive,
  axis: ProjectAxis.discipline,
  iconName: 'leaf',
  aliases: const ['蔬菜', '水果', '吃菜', '蔬果', '沙拉', '青菜'],
  keywords: const ['拳', '份'],
  standardDefinition: '1 份 ≈ 一个拳头大小的蔬菜，或一个中等水果。目标 3 份。',
  misconception: '果汁不算水果份数——纤维和咀嚼感都丢了。',
  targetDose: 3,
  doseUnit: '份',
  questions: [
    numQ('servings', '吃了几份蔬果？', '一份≈一个拳头。',
        min: 0, max: 12, initial: 2, step: 1, unit: ' 份', rangeHint: '目标 3 份以上'),
    choiceQ('variety', '颜色有几种？', '颜色越多，微量营养素谱越宽。', const [
      QuestionOption('3', '3 种以上'),
      QuestionOption('2', '2 种'),
      QuestionOption('1', '就一种'),
    ]),
  ],
  derive: (ctx) {
    final servings = ctx.numOr('servings', 0);
    final variety = ctx.intOr('variety', 1);
    return buildDoseResult(
      ctx: ctx,
      slotKey: 'day',
      dose: servings * (variety >= 3 ? 1.0 : 0.85),
      target: 3,
      unit: '份',
      interpretation: '蔬果 $servings 份，颜色 $variety 种',
      lines: [
        ReceiptLine('份数', '${servings.toStringAsFixed(0)} 份'),
        ReceiptLine('多样性', '$variety 种颜色'),
        ReceiptLine('折算', '${(servings * (variety >= 3 ? 1.0 : 0.85)).toStringAsFixed(1)} 份当量', emphasis: true),
      ],
      metrics: {'servings': servings, 'variety': variety.toDouble()},
    );
  },
);

// ---------------------------------------------------------------- 阅读

final BehaviorDef readingBehavior = BehaviorDef(
  code: 'reading',
  name: '阅读',
  category: BehaviorCategory.positive,
  valence: Valence.positive,
  axis: ProjectAxis.memory,
  iconName: 'read',
  aliases: const ['阅读', '看书', '读书', '读了几页', '看论文', '读原版'],
  keywords: const ['页', '章节', '书'],
  standardDefinition:
      '1 分钟有效阅读 = 注意力在文本上、且能复述出刚读内容的时间。'
      '滑手机式扫读不算。',
  misconception: '页数是最不可比的单位（一页小说和一页公式差十倍），本项目同时记录难度。',
  targetDose: 30,
  doseUnit: '分钟',
  questions: [
    minutesQ('minutes', '读了多久？', '时长比页数更能横向比较。', initial: 30, rangeHint: '常规 20–60 分钟'),
    choiceQ('difficulty', '读的东西难不难？', '难度决定认知负荷，也决定能撑多久。', const [
      QuestionOption('easy', '轻松，随便读'),
      QuestionOption('mid', '要专心'),
      QuestionOption('hard', '很吃力，要反复看'),
    ]),
    choiceQ('active', '有没有停下来想或记？', '主动加工比通读更容易留下东西。', const [
      QuestionOption('yes', '有，做了笔记/复述'),
      QuestionOption('some', '偶尔'),
      QuestionOption('no', '一口气读完'),
    ]),
  ],
  derive: (ctx) {
    final minutes = ctx.numOr('minutes', 0);
    final diff = switch (ctx.strOr('difficulty', 'mid')) {
      'easy' => 0.8,
      'hard' => 1.3,
      _ => 1.0,
    };
    final active = switch (ctx.strOr('active', 'some')) {
      'yes' => 1.2,
      'no' => 0.85,
      _ => 1.0,
    };
    final effective = minutes * diff * active;
    return buildDoseResult(
      ctx: ctx,
      slotKey: 'day',
      dose: effective,
      target: 30,
      unit: '分钟',
      interpretation: '阅读 $minutes 分钟，认知当量 ${effective.toStringAsFixed(0)} 分钟',
      lines: [
        ReceiptLine('时长', '${minutes.toStringAsFixed(0)} 分钟'),
        ReceiptLine('难度系数', '×${diff.toStringAsFixed(1)}'),
        ReceiptLine('主动加工', '×${active.toStringAsFixed(2)}'),
        ReceiptLine('认知当量', '${effective.toStringAsFixed(0)} 分钟', emphasis: true),
      ],
      metrics: {'minutes': minutes, 'cognitive_minutes': effective},
    );
  },
);

// ---------------------------------------------------------------- 写作

final BehaviorDef writingBehavior = BehaviorDef(
  code: 'writing',
  name: '写作',
  category: BehaviorCategory.positive,
  valence: Valence.positive,
  axis: ProjectAxis.writing,
  iconName: 'pen',
  aliases: const ['写作', '写东西', '码字', '写日记', '写文章', '写字'],
  keywords: const ['字', '篇', '稿'],
  standardDefinition:
      '1 字 = 最终定稿里的一个字。目标 500 字/次。'
      '写作增益同时看字数、表达多样性与持续性（是否隔天就断）。',
  misconception: '只堆字数不看结构，会练出"很能写但说不清"的手感。',
  targetDose: 500,
  doseUnit: '字',
  questions: [
    numQ('words', '写了多少字？', '字数是量的底。',
        min: 0, max: 20000, initial: 500, step: 100, unit: ' 字', rangeHint: '常规 300–1500 字'),
    choiceQ('diversity', '表达上有没有新的东西？', '重复自己最省力，但成长最少。', const [
      QuestionOption('high', '有新的结构或说法'),
      QuestionOption('mid', '老套路但顺手'),
      QuestionOption('low', '基本在凑字'),
    ]),
    choiceQ('finished', '写完了吗？', '未完成的稿子依然计入，但按完成度折算。', const [
      QuestionOption('yes', '完成了'),
      QuestionOption('partial', '写了一部分'),
    ]),
  ],
  derive: (ctx) {
    final words = ctx.numOr('words', 0);
    final div = switch (ctx.strOr('diversity', 'mid')) {
      'high' => 1.15,
      'low' => 0.8,
      _ => 1.0,
    };
    final done = ctx.strOr('finished', 'yes') == 'yes' ? 1.0 : 0.75;
    final effective = words * div * done;
    return buildDoseResult(
      ctx: ctx,
      slotKey: 'day',
      dose: effective,
      target: 500,
      unit: '字',
      interpretation: '写作 $words 字，折算 ${effective.round()} 字当量',
      lines: [
        ReceiptLine('字数', '${words.toStringAsFixed(0)} 字'),
        ReceiptLine('多样性', '×${div.toStringAsFixed(2)}'),
        ReceiptLine('完成度', '×${done.toStringAsFixed(2)}'),
        ReceiptLine('折算当量', '${effective.round()} 字', emphasis: true),
      ],
      metrics: {'words': words, 'effective_words': effective},
    );
  },
);

// ---------------------------------------------------------------- 冥想

final BehaviorDef meditationBehavior = BehaviorDef(
  code: 'meditation',
  name: '冥想',
  category: BehaviorCategory.positive,
  valence: Valence.positive,
  axis: ProjectAxis.discipline,
  iconName: 'lotus',
  aliases: const ['冥想', '打坐', '正念', '呼吸练习', '静坐'],
  keywords: const ['专注', '呼吸'],
  standardDefinition: '1 分钟 = 注意力放在呼吸/身体感受上的时间，走神后拉回即可继续计。',
  misconception: '冥想不是"什么都不想"，走神再拉回的过程本身就是练习。',
  targetDose: 10,
  doseUnit: '分钟',
  questions: [
    minutesQ('minutes', '坐了多久？', '短而稳比长而散更有用。', initial: 10, rangeHint: '常规 5–20 分钟'),
    choiceQ('anchor', '注意力放在哪？', '有没有锚点决定这次练习的质量。', const [
      QuestionOption('breath', '呼吸'),
      QuestionOption('body', '身体感受'),
      QuestionOption('sound', '声音/环境'),
      QuestionOption('none', '没定，随便坐着'),
    ]),
  ],
  derive: (ctx) {
    final minutes = ctx.numOr('minutes', 0);
    final anchored = ctx.strOr('anchor', 'breath') != 'none';
    return buildDoseResult(
      ctx: ctx,
      slotKey: 'day',
      dose: minutes * (anchored ? 1.0 : 0.75),
      target: 10,
      unit: '分钟',
      interpretation: '冥想 $minutes 分钟${anchored ? '（有锚点）' : '（无锚点）'}',
      lines: [
        ReceiptLine('时长', '${minutes.toStringAsFixed(0)} 分钟'),
        ReceiptLine('锚点', anchored ? '明确' : '无'),
        ReceiptLine('折算', '${(minutes * (anchored ? 1.0 : 0.75)).toStringAsFixed(0)} 分钟', emphasis: true),
      ],
      metrics: {'minutes': minutes},
    );
  },
);

// ---------------------------------------------------------------- 深度对话

final BehaviorDef deepTalkBehavior = BehaviorDef(
  code: 'deep_talk',
  name: '深度对话',
  category: BehaviorCategory.positive,
  valence: Valence.positive,
  axis: ProjectAxis.writing,
  iconName: 'chat',
  aliases: const ['深度对话', '聊天', '谈心', '聊了很久', '和朋友聊'],
  keywords: const ['交流', '沟通'],
  standardDefinition:
      '1 分钟有效对话 = 双方都在实质交换想法、没有一边刷手机的时间。'
      '一起看剧时的闲聊不算。',
  misconception: '社交数量不等于质量，十分钟真的在听，胜过两小时在场走神。',
  targetDose: 20,
  doseUnit: '分钟',
  questions: [
    minutesQ('minutes', '聊了多久？', '只算真正在交流的时间。', initial: 30, rangeHint: '常规 20–60 分钟'),
    choiceQ('depth', '聊到什么程度？', '越接近真实想法，回报越高。', const [
      QuestionOption('deep', '聊到了真实想法'),
      QuestionOption('mid', '日常话题'),
      QuestionOption('light', '寒暄'),
    ]),
  ],
  derive: (ctx) {
    final minutes = ctx.numOr('minutes', 0);
    final depth = switch (ctx.strOr('depth', 'mid')) {
      'deep' => 1.2,
      'light' => 0.6,
      _ => 1.0,
    };
    return buildDoseResult(
      ctx: ctx,
      slotKey: 'day',
      dose: minutes * depth,
      target: 20,
      unit: '分钟',
      interpretation: '对话 $minutes 分钟，深度系数 ${depth.toStringAsFixed(1)}',
      lines: [
        ReceiptLine('时长', '${minutes.toStringAsFixed(0)} 分钟'),
        ReceiptLine('深度', '×${depth.toStringAsFixed(1)}'),
        ReceiptLine('折算', '${(minutes * depth).toStringAsFixed(0)} 分钟', emphasis: true),
      ],
      metrics: {'minutes': minutes, 'depth': depth},
    );
  },
);

final List<BehaviorDef> positiveOthers = [
  cardioBehavior,
  flexibilityBehavior,
  proteinBehavior,
  vegetableBehavior,
  readingBehavior,
  writingBehavior,
  meditationBehavior,
  deepTalkBehavior,
];
