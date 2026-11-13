/// 刻度标定层（Anchor Layer）的唯一入口。
///
/// 数据层与 UI 只 import 这个文件，不逐个 import 内部文件——
/// 以后拆文件、改文件名都不会波及调用方。
///
/// 边界提醒：
///   - 本层不写库（没有 DAO / Repository），不碰 Flutter。
///   - 本层不参与 `SettlementPipeline`：它只产出先验与展示用权重。
///   - 想加"AI 估算"之类的新来源，只许加 [ImpactSource] 的成员，
///     不许绕过 [AnchorEngine] 直接构造权重。
library;

export 'anchor_config.dart';
export 'anchor_engine.dart';
export 'anchor_models.dart';
export 'onboarding_flow.dart';
export 'proposal_codec.dart';
export 'reference_ranges.dart';
