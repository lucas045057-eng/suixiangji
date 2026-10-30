import 'package:flutter/material.dart';

/// 方向 A「灰白纸感」设计令牌（V1.0.8 P0）。
///
/// 规范见 design/ui-redesign/ui-spec-direction-a.md §2、§3；页面级硬编码色
/// 在 P1/P2 分期逐页替换为这里引用的 token。
const paBg = Color(0xFFF7F7F5); // 纸底
const paSurface = Color(0xFFFFFFFF); // 卡片面 / 导航条
const paHairline = Color(0xFFECEAE4); // 1px 发丝线
const paInk = Color(0xFF1F1F1D); // 主文字 / 大数字（炭黑）
const paInkSub = Color(0xFF8A8A85); // 次要文字
const paInkFaint = Color(0xFFA5A49E); // 三级注释 / 占位
const paIncome = Color(0xFF4A7C59); // 收入金额（唯一正色）
const paExpense = paInk; // 支出金额不加色
const paAi = Color(0xFF6B6B4F); // 随口记 AI 标识（橄榄绿）
const paWarn = Color(0xFFB3543F); // 超支等唯一警示色

/// 数字一律等宽（对应 CSS `font-variant-numeric: tabular-nums`）。
const List<FontFeature> paTabularFigures = <FontFeature>[
  FontFeature.tabularFigures(),
];

/// 首页结余类大数字：w300 + 44~46px。
const TextStyle paNumberLarge = TextStyle(
  fontSize: 45,
  fontWeight: FontWeight.w300,
  color: paInk,
  height: 1.1,
  letterSpacing: -1,
  fontFeatures: paTabularFigures,
);

/// 行内金额：w600 + 15~16px。
const TextStyle paAmountInline = TextStyle(
  fontSize: 15,
  fontWeight: FontWeight.w600,
  color: paExpense,
  fontFeatures: paTabularFigures,
);

/// 分区标题：小字号 + 加宽字距。
const TextStyle paSectionLabel = TextStyle(
  fontSize: 11,
  fontWeight: FontWeight.w600,
  color: paInkSub,
  letterSpacing: 3,
);

TextStyle _tabular(TextStyle? style, Color color) => (style ?? const TextStyle())
    .copyWith(color: color, fontFeatures: paTabularFigures);

TextTheme _tabularTextTheme(TextTheme base) => TextTheme(
      displayLarge: _tabular(base.displayLarge, paInk),
      displayMedium: _tabular(base.displayMedium, paInk),
      displaySmall: _tabular(base.displaySmall, paInk),
      headlineLarge: _tabular(base.headlineLarge, paInk),
      headlineMedium: _tabular(base.headlineMedium, paInk),
      headlineSmall: _tabular(base.headlineSmall, paInk),
      titleLarge: _tabular(base.titleLarge, paInk),
      titleMedium: _tabular(base.titleMedium, paInk),
      titleSmall: _tabular(base.titleSmall, paInk),
      bodyLarge: _tabular(base.bodyLarge, paInk),
      bodyMedium: _tabular(base.bodyMedium, paInk),
      bodySmall: _tabular(base.bodySmall, paInkSub),
      labelLarge: _tabular(base.labelLarge, paInk),
      labelMedium: _tabular(base.labelMedium, paInk),
      labelSmall: _tabular(base.labelSmall, paInkSub),
    );

ThemeData wealthMateTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: paInkSub,
    brightness: Brightness.light,
  ).copyWith(
    primary: paInk,
    onPrimary: Colors.white,
    secondary: paIncome,
    onSecondary: Colors.white,
    tertiary: paAi,
    surface: paSurface,
    onSurface: paInk,
    onSurfaceVariant: paInkSub,
    outline: paHairline,
    outlineVariant: paHairline,
    error: paWarn,
    onError: Colors.white,
  );
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: paBg,
  );
  return base.copyWith(
    textTheme: _tabularTextTheme(base.textTheme),
    appBarTheme: const AppBarTheme(
      backgroundColor: paBg,
      foregroundColor: paInk,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      color: paSurface,
      elevation: 0,
      margin: EdgeInsets.zero,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: paHairline),
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: paHairline,
      thickness: 1,
      space: 1,
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: paSurface,
      surfaceTintColor: Colors.transparent,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: paSurface,
      hintStyle: const TextStyle(color: paInkFaint),
      labelStyle: const TextStyle(color: paInkSub),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: paHairline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: paHairline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: paInk, width: 1.5),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: paSurface,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      elevation: 0,
      // 去胶囊指示器：选中态只靠字重 + 炭黑表达。
      indicatorColor: Colors.transparent,
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          size: 22,
          color: states.contains(WidgetState.selected) ? paInk : paInkFaint,
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: 11,
          color: states.contains(WidgetState.selected) ? paInk : paInkFaint,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w700
              : FontWeight.w400,
        ),
      ),
    ),
    navigationRailTheme: const NavigationRailThemeData(
      backgroundColor: paBg,
      indicatorColor: Colors.transparent,
      selectedIconTheme: IconThemeData(color: paInk, size: 20),
      unselectedIconTheme: IconThemeData(color: paInkFaint, size: 20),
      selectedLabelTextStyle: TextStyle(
          color: paInk, fontSize: 13, fontWeight: FontWeight.w700),
      unselectedLabelTextStyle: TextStyle(
          color: paInkFaint, fontSize: 13, fontWeight: FontWeight.w400),
    ),
  );
}
