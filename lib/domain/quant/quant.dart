/// Quant 层的统一出口。上层（数据层 / UI）只 import 这一个文件。
///
/// 一个门，四个房间：
///   * `dose_shape`    怎么折算（四种形状）
///   * `quant_measure` 量什么 + 落在哪些维度
///   * `quant_spec`    规格本身（折算出口在这一层）
///   * `quant_validate` 四道闸
///   * `axis_registry` 维度注册表
///   * `quant_request` / `quant_response` 离线提案协议的两端
library;

export 'axis_registry.dart';
export 'dose_shape.dart';
export 'quant_measure.dart';
export 'quant_request.dart';
export 'quant_response.dart';
export 'quant_spec.dart';
export 'quant_validate.dart';
