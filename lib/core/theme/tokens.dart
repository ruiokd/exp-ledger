import 'package:flutter/material.dart';

/// 设计令牌。所有圆角、间距、阴影、字号只从这里取，
/// 保证 7 个页面看起来是同一个 App，而不是七个人做的。
class Tokens {
  const Tokens._();

  // ---- 圆角：圆润、有人味 ----
  static const double radiusCard = 20;
  static const double radiusButton = 16;
  static const double radiusChip = 14;
  static const double radiusSheet = 28;
  static const double radiusSmall = 10;

  // ---- 间距 ----
  static const double gapXs = 4;
  static const double gapS = 8;
  static const double gapM = 12;
  static const double gapL = 16;
  static const double gapXl = 24;
  static const double gapXxl = 32;

  // ---- 页面留白 ----
  static const EdgeInsets pagePadding =
      EdgeInsets.symmetric(horizontal: 20, vertical: 12);
  static const EdgeInsets cardPadding = EdgeInsets.all(18);

  // ---- 字号 ----
  static const double fontCaption = 12;
  static const double fontSmall = 13;
  static const double fontBody = 15;
  static const double fontTitle = 18;
  static const double fontHeadline = 22;
  static const double fontDisplay = 30;

  // ---- 数字与刻度 ----
  /// 图表刻度、技术性小字（"今天"标记、坐标值）。比 caption 再小一档。
  static const double fontMicro = 10;

  /// 步进器上的单位标记。
  static const double fontNano = 11;

  /// 明细页的净 EXP。
  static const double fontMetric = 32;

  /// 首页的净 EXP。整个 App 最大的一个数字。
  static const double fontHero = 40;

  /// 步进器里被拨动的大数字。
  static const double fontHeroLarge = 46;

  // ---- 动效：克制，200–300ms 回弹 ----
  static const Duration motionFast = Duration(milliseconds: 200);
  static const Duration motionBase = Duration(milliseconds: 260);
  static const Duration motionSlow = Duration(milliseconds: 300);
  static const Curve motionCurve = Curves.easeOutCubic;
  static const Curve motionSpring = Curves.easeOutBack;
}

/// 颜色。暖白背景 + 低饱和蓝/暖橙，负向用石板蓝灰而不是红色。
class AppColors {
  const AppColors._();

  static const Color background = Color(0xFFFBF8F4);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceMuted = Color(0xFFF4F0EA);

  static const Color ink = Color(0xFF2B2B2E);
  static const Color inkSoft = Color(0xFF6E6A66);
  static const Color inkFaint = Color(0xFF9C9791);

  static const Color accent = Color(0xFFE8975A); // 暖橙：正向
  static const Color accentSoft = Color(0xFFFBEDE0);

  static const Color calm = Color(0xFF6C8EBF); // 低饱和蓝：信息
  static const Color calmSoft = Color(0xFFE8EEF6);

  /// 负向不用红。用低饱和石板蓝灰——它是"信息色"，不是"警报色"。
  static const Color negative = Color(0xFF7A8699);
  static const Color negativeSoft = Color(0xFFEDEFF3);

  static const Color neutral = Color(0xFF8C8578);
  static const Color neutralSoft = Color(0xFFF0EDE7);

  static const Color divider = Color(0xFFEDE8E1);

  static const Color confidenceCalibrated = Color(0xFF4F8A6B);
  static const Color confidenceFormula = Color(0xFF6C8EBF);
  static const Color confidenceSelfReport = Color(0xFF9C9791);
}

/// 柔和弥散阴影：不用硬黑边，用大模糊 + 低透明度。
class SoftShadow {
  const SoftShadow._();

  static const List<BoxShadow> card = [
    BoxShadow(
      color: Color(0x0F2B2B2E),
      blurRadius: 24,
      offset: Offset(0, 8),
      spreadRadius: -4,
    ),
    BoxShadow(
      color: Color(0x082B2B2E),
      blurRadius: 4,
      offset: Offset(0, 2),
    ),
  ];

  static const List<BoxShadow> raised = [
    BoxShadow(
      color: Color(0x1A2B2B2E),
      blurRadius: 32,
      offset: Offset(0, 14),
      spreadRadius: -6,
    ),
  ];

  static const List<BoxShadow> sheet = [
    BoxShadow(
      color: Color(0x222B2B2E),
      blurRadius: 40,
      offset: Offset(0, -8),
      spreadRadius: -8,
    ),
  ];
}
