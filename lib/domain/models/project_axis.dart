
/// 五个能力维度。权重在 BalanceConfig 里，这里只做身份标识。
enum ProjectAxis {
  strength('体能'),
  cardio('心肺'),
  memory('词汇'),
  writing('写作'),
  discipline('自律');

  const ProjectAxis(this.label);

  final String label;

  static ProjectAxis parse(String raw) =>
      ProjectAxis.values.firstWhere((e) => e.name == raw, orElse: () => strength);
}
