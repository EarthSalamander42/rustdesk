// Thème Material de l'Atelier. Construit à partir du thème existant de l'application (il en garde
// les extensions : `ColorThemeExtension`, `TabbarTheme` de RustDesk…) et y ajoute [FsTokens].
// Côté client, deux lignes dans `MyTheme` suffisent : `fsAtelierTheme(base, Brightness.light)`.
import 'package:flutter/material.dart';

import 'tokens.dart';
import 'typography.dart';

/// Rayon commun : angles droits partout.
const BorderRadius fsRadius = BorderRadius.zero;

ThemeData fsAtelierTheme([ThemeData? base, Brightness brightness = Brightness.light]) {
  final t = FsTokens.forBrightness(brightness);
  base ??= ThemeData(brightness: brightness, useMaterial3: false);
  const square = RoundedRectangleBorder(borderRadius: fsRadius);
  final textBase = (brightness == Brightness.dark ? Typography.material2018().white : Typography.material2018().black)
      .apply(fontFamily: FsType.interFamily, bodyColor: t.ink, displayColor: t.ink);
  final text = textBase.copyWith(
    titleLarge: textBase.titleLarge?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.5),
    titleMedium: textBase.titleMedium?.copyWith(fontWeight: FontWeight.w700),
    labelLarge: textBase.labelLarge?.copyWith(fontWeight: FontWeight.w600, color: t.ink),
    bodySmall: textBase.bodySmall?.copyWith(color: t.muted),
  );
  final scheme = (brightness == Brightness.dark ? const ColorScheme.dark() : const ColorScheme.light()).copyWith(
    primary: t.acc,
    onPrimary: t.accFg,
    secondary: t.acc,
    onSecondary: t.accFg,
    tertiary: t.on,
    error: t.danger,
    onError: Colors.white,
    surface: t.bg,
    onSurface: t.ink,
    // ignore: deprecated_member_use
    background: t.bg,
    // ignore: deprecated_member_use
    onBackground: t.ink,
    surfaceTint: Colors.transparent,
    outline: t.line,
    outlineVariant: t.line2,
    primaryContainer: t.sel,
    onPrimaryContainer: t.ink,
    secondaryContainer: t.bg2,
    onSecondaryContainer: t.ink,
  );
  final inputBorder = OutlineInputBorder(borderRadius: fsRadius, borderSide: BorderSide(color: t.line));
  final btnText = WidgetStatePropertyAll(FsType.sans(14, FontWeight.w700));
  final exts = base.extensions.values.where((e) => e is! FsTokens).followedBy([t]);
  return base.copyWith(
    brightness: brightness,
    colorScheme: scheme,
    primaryColor: t.acc,
    scaffoldBackgroundColor: t.bg,
    canvasColor: t.bg,
    cardColor: t.bg2,
    dividerColor: t.line,
    hoverColor: t.hov,
    highlightColor: t.sel,
    splashColor: t.sel,
    focusColor: t.sel,
    disabledColor: t.off,
    hintColor: t.muted,
    unselectedWidgetColor: t.muted,
    splashFactory: InkRipple.splashFactory,
    textTheme: text,
    primaryTextTheme: text,
    iconTheme: IconThemeData(color: t.ink),
    primaryIconTheme: IconThemeData(color: t.accFg),
    dividerTheme: DividerThemeData(color: t.line, thickness: 1, space: 1),
    appBarTheme: AppBarTheme(
      backgroundColor: t.bg,
      foregroundColor: t.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      iconTheme: IconThemeData(color: t.muted),
      titleTextStyle: FsType.sans(18, FontWeight.w800, em: -0.03, color: t.ink),
      shape: Border(bottom: BorderSide(color: t.line)),
    ),
    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      backgroundColor: t.bg,
      selectedItemColor: t.acc,
      unselectedItemColor: t.muted,
      selectedLabelStyle: FsType.sans(12, FontWeight.w600),
      unselectedLabelStyle: FsType.sans(12, FontWeight.w600),
      elevation: 0,
    ),
    tabBarTheme: TabBarTheme(
      labelColor: t.ink,
      unselectedLabelColor: t.muted,
      indicatorColor: t.acc,
      dividerColor: t.line,
      indicator: UnderlineTabIndicator(borderSide: BorderSide(color: t.acc, width: 2)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: t.field,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: inputBorder,
      enabledBorder: inputBorder,
      focusedBorder: inputBorder.copyWith(borderSide: BorderSide(color: t.acc)),
      errorBorder: inputBorder.copyWith(borderSide: BorderSide(color: t.danger)),
      labelStyle: TextStyle(color: t.muted),
      hintStyle: TextStyle(color: t.muted.withOpacity(0.75)),
      prefixIconColor: t.muted,
      suffixIconColor: t.muted,
    ),
    textSelectionTheme: TextSelectionThemeData(cursorColor: t.acc, selectionColor: t.acc.withOpacity(0.25), selectionHandleColor: t.acc),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.disabled) ? t.off : t.acc),
        foregroundColor: WidgetStatePropertyAll(t.accFg),
        overlayColor: WidgetStatePropertyAll(t.accFg.withOpacity(0.08)),
        elevation: const WidgetStatePropertyAll(0),
        shadowColor: const WidgetStatePropertyAll(Colors.transparent),
        shape: const WidgetStatePropertyAll(square),
        textStyle: btnText,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: ButtonStyle(
        foregroundColor: WidgetStatePropertyAll(t.ink),
        overlayColor: WidgetStatePropertyAll(t.hov),
        side: WidgetStatePropertyAll(BorderSide(color: t.line)),
        shape: const WidgetStatePropertyAll(square),
        textStyle: btnText,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: ButtonStyle(
        foregroundColor: WidgetStatePropertyAll(t.acc),
        overlayColor: WidgetStatePropertyAll(t.hov),
        shape: const WidgetStatePropertyAll(square),
        textStyle: WidgetStatePropertyAll(FsType.sans(14, FontWeight.w600)),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(style: ButtonStyle(foregroundColor: WidgetStatePropertyAll(t.muted))),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? t.acc : Colors.transparent),
      checkColor: WidgetStatePropertyAll(t.accFg),
      side: BorderSide(color: t.muted, width: 1.5),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(1))),
    ),
    radioTheme: RadioThemeData(fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? t.acc : t.muted)),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? t.accFg : t.muted),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? t.acc : t.bg2),
      trackOutlineColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? t.acc : t.line),
    ),
    sliderTheme: SliderThemeData(activeTrackColor: t.acc, inactiveTrackColor: t.line, thumbColor: t.acc, overlayColor: t.sel),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: t.acc, linearTrackColor: t.line2, circularTrackColor: t.line2),
    dialogTheme: DialogTheme(
      backgroundColor: t.bg,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: fsRadius, side: BorderSide(color: t.line)),
      titleTextStyle: FsType.sans(18, FontWeight.w800, em: -0.02, color: t.ink),
      contentTextStyle: FsType.sans(14, FontWeight.w400, color: t.ink),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: t.bg,
      surfaceTintColor: Colors.transparent,
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: fsRadius, side: BorderSide(color: t.line)),
      textStyle: FsType.sans(13.5, FontWeight.w400, color: t.ink),
    ),
    menuTheme: MenuThemeData(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(t.bg),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: fsRadius, side: BorderSide(color: t.line))),
      ),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(color: t.ink),
      textStyle: FsType.sans(12, FontWeight.w600, color: t.bg),
      waitDuration: const Duration(milliseconds: 500),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: t.ink,
      contentTextStyle: FsType.sans(13, FontWeight.w600, color: t.bg),
      shape: square,
      behavior: SnackBarBehavior.floating,
    ),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStatePropertyAll(t.line),
      thickness: const WidgetStatePropertyAll(6),
      radius: Radius.zero,
    ),
    listTileTheme: ListTileThemeData(iconColor: t.muted, textColor: t.ink, selectedColor: t.acc, selectedTileColor: t.sel),
    chipTheme: ChipThemeData(
      backgroundColor: t.bg,
      selectedColor: t.ink,
      side: BorderSide(color: t.line),
      shape: square,
      labelStyle: FsType.sans(13, FontWeight.w600, color: t.ink),
    ),
    cardTheme: CardTheme(color: t.bg2, surfaceTintColor: Colors.transparent, elevation: 0, shape: square),
    drawerTheme: DrawerThemeData(backgroundColor: t.bg),
    bottomSheetTheme: BottomSheetThemeData(backgroundColor: t.bg, shape: square),
    extensions: exts,
  );
}
