// Rail de gauche de l'accueil (`.A-rail`) : marque, bloc « Votre poste », navigation, paramètres et crédit.
import 'package:flutter/material.dart';

import '../models.dart';
import '../strings.dart';
import '../tokens.dart';
import '../typography.dart';
import 'package:flutter/rendering.dart';

import 'primitives.dart';

/// Rail complet : 256 px, filet à droite, marges 20/18/14/20.
class FsRail extends StatelessWidget {
  const FsRail({
    super.key,
    required this.me,
    required this.nav,
    this.onSettings,
    this.version = '1.0.0',
    this.onCredit,
    this.extra,
  });

  final Widget me;
  final Widget nav;
  final VoidCallback? onSettings;
  final String version;

  /// Clic sur « Technologie RustDesk » (page « À propos », lien vers le code du fork).
  final VoidCallback? onCredit;

  /// Contenu facultatif glissé sous la navigation (cartes d'aide RustDesk : mise à jour, installation…).
  final Widget? extra;

  @override
  Widget build(BuildContext context) {
    final t = FsTokens.of(context);
    return AnimatedContainer(
      duration: FsMotion.theme,
      width: FsDims.rail,
      decoration: BoxDecoration(border: Border(right: BorderSide(color: t.line))),
      padding: const EdgeInsets.fromLTRB(20, 20, 18, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const FsBrand(),
          me,
          nav,
          if (extra != null)
            Expanded(child: SingleChildScrollView(padding: const EdgeInsets.only(top: 12, bottom: 12), child: extra!))
          else
            const Spacer(),
          FsRailFoot(onSettings: onSettings, version: version, onCredit: onCredit),
        ],
      ),
    );
  }
}

/// Marque : monogramme 38 px, « FS Support » et « par FS Solutions ».
class FsBrand extends StatelessWidget {
  const FsBrand({super.key});

  @override
  Widget build(BuildContext context) {
    final t = FsTokens.of(context);
    return Row(children: [
      const FsMark(size: 38),
      const SizedBox(width: 12),
      Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        FsText(FsStrings.appName, style: FsType.sans(19, FontWeight.w800, height: 1.1, em: -0.035, color: t.ink)),
        FsText(FsStrings.byline, style: FsType.sans(11.5, FontWeight.w400, color: t.muted), strut: FsType.strut(14)),
      ]),
    ]);
  }
}

/// Bloc « Votre poste » (`.A-me`) : ID en Archivo Black, mot de passe à usage unique, actions.
class FsMeBlock extends StatelessWidget {
  const FsMeBlock({
    super.key,
    required this.id,
    required this.password,
    this.passwordLabel = FsStrings.oneTimePassword,
    this.onCopyId,
    this.onCopyPassword,
    this.onRefresh,
    this.onEdit,
    this.showPassword = true,
  });

  final String id;
  final String password;
  final String passwordLabel;
  final VoidCallback? onCopyId;
  final VoidCallback? onCopyPassword;
  final VoidCallback? onRefresh;
  final VoidCallback? onEdit;
  final bool showPassword;

  @override
  Widget build(BuildContext context) {
    final t = FsTokens.of(context);
    return AnimatedContainer(
      duration: FsMotion.theme,
      margin: const EdgeInsets.only(top: 20, bottom: 14),
      padding: const EdgeInsets.only(top: 16, bottom: 14),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: t.ink), bottom: BorderSide(color: t.line))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const FsEyebrow(FsStrings.yourDevice),
        const SizedBox(height: 6),
        _CopyId(id: id, onCopy: onCopyId),
        const SizedBox(height: 8 + 6),
        if (showPassword) ...[
          FsEyebrow(passwordLabel),
          const SizedBox(height: 6),
          SizedBox(
            height: 32,
            child: Row(children: [
              Expanded(
                child: GestureDetector(
                  onDoubleTap: onCopyPassword,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: AnimatedSwitcher(
                      duration: FsMotion.fade,
                      switchInCurve: FsMotion.ease,
                      transitionBuilder: (child, a) => FadeTransition(
                        opacity: a,
                        child: AnimatedBuilder(
                          animation: a,
                          child: child,
                          builder: (context, c) => Transform.translate(offset: Offset(0, 6 * (1 - a.value)), child: c),
                        ),
                      ),
                      layoutBuilder: (cur, prev) => Stack(alignment: Alignment.centerLeft, children: [...prev, if (cur != null) cur]),
                      child: FsText(password,
                          key: ValueKey(password),
                          style: FsType.mono(17, FontWeight.w600, em: 0.14, color: t.ink)),
                    ),
                  ),
                ),
              ),
              if (onRefresh != null)
                FsIconButton(icon: Icons.refresh_rounded, tooltip: FsStrings.newPassword, onPressed: onRefresh, spinOnPress: true),
              if (onEdit != null) ...[
                const SizedBox(width: 4),
                FsIconButton(icon: Icons.edit_rounded, tooltip: FsStrings.edit, onPressed: onEdit),
              ],
            ]),
          ),
        ],
      ]),
    );
  }
}

class _CopyId extends StatelessWidget {
  const _CopyId({required this.id, this.onCopy});
  final String id;
  final VoidCallback? onCopy;

  @override
  Widget build(BuildContext context) {
    final t = FsTokens.of(context);
    return Tooltip(
      message: FsStrings.copyId,
      waitDuration: const Duration(milliseconds: 600),
      child: FsHover(
        onTap: onCopy,
        builder: (context, hover, _) => Row(children: [
          Flexible(
            child: FsText(id,
                maxLines: 1,
                overflow: TextOverflow.fade,
                softWrap: false,
                style: FsType.display(27, color: t.ink)),
          ),
          const SizedBox(width: 8),
          AnimatedOpacity(
            opacity: hover ? 1 : 0,
            duration: FsMotion.quick,
            child: AnimatedSlide(
              offset: Offset(hover ? 0 : -4 / 17, 0),
              duration: FsMotion.fade,
              curve: FsMotion.ease,
              child: Icon(Icons.content_copy_rounded, size: 17, color: t.muted),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Navigation du rail (`.A-nav`) : indicateur coulissant, compteurs, emplacements « Bientôt ».
class FsRailNav extends StatelessWidget {
  const FsRailNav({super.key, required this.items, required this.selected, required this.onSelect, this.soonHeading = FsStrings.plannedSlots});

  final List<FsNavItem> items;
  final String selected;
  final ValueChanged<String> onSelect;
  final String soonHeading;

  static const double _item = FsDims.navItem;
  static const double _gap = 2;
  // titre « Emplacements prévus » : marge 14 + ligne 14,7 + marge 4
  static const double _heading = 14 + 10.5 * 1.4 + 4;

  @override
  Widget build(BuildContext context) {
    final t = FsTokens.of(context);
    final tops = <String, double>{};
    final children = <Widget>[];
    var y = 0.0;
    var headed = false;
    for (final it in items) {
      if (it.soon && !headed) {
        headed = true;
        if (children.isNotEmpty) {
          children.add(const SizedBox(height: _gap));
          y += _gap;
        }
        children.add(Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 0, 4),
          child: FsEyebrow(soonHeading),
        ));
        y += _heading;
      }
      if (children.isNotEmpty) {
        children.add(const SizedBox(height: _gap));
        y += _gap;
      }
      tops[it.key] = y;
      children.add(_NavButton(item: it, on: it.key == selected, onTap: () => onSelect(it.key)));
      y += _item;
    }
    final top = tops[selected];
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth;
      return Stack(clipBehavior: Clip.none, children: [
        if (top != null)
          AnimatedPositioned(
            duration: FsMotion.accordion,
            curve: FsMotion.ease,
            top: top,
            left: 0,
            width: w,
            height: _item,
            child: AnimatedContainer(
              duration: FsMotion.theme,
              decoration: BoxDecoration(
                color: t.sel,
                border: Border(left: BorderSide(color: t.acc, width: 3)),
              ),
            ),
          ),
        // Comme dans la maquette (grille CSS), la colonne prend la largeur du plus long élément
        // si elle dépasse celle du rail.
        _WidenToContent(
          child: IntrinsicWidth(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
          ),
        ),
      ]);
    });
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({required this.item, required this.on, required this.onTap});
  final FsNavItem item;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = FsTokens.of(context);
    return FsHover(
      onTap: onTap,
      builder: (context, hover, _) {
        final fg = (hover || on) && !item.soon ? t.ink : t.muted;
        return SizedBox(
          height: FsDims.navItem,
          child: Padding(
            padding: const EdgeInsets.only(left: 14, right: 10),
            child: TweenAnimationBuilder<Color?>(
              tween: ColorTween(end: item.soon && hover ? t.ink : fg),
              duration: FsMotion.quick,
              builder: (context, c, _) => Row(children: [
                Icon(item.icon, size: 19, color: c),
                const SizedBox(width: 12),
                FsText(item.label, style: FsType.sans(14, FontWeight.w600, color: c), maxLines: 1, softWrap: false),
                const Spacer(),
                if (item.count != null) ...[
                  const SizedBox(width: 12),
                  FsText('${item.count}',
                      style: FsType.sans(12, FontWeight.w600, color: t.muted, tabular: true)),
                ],
                if (item.soon) ...[
                  const SizedBox(width: 12),
                  const FsSoonTag(),
                ],
              ]),
            ),
          ),
        );
      },
    );
  }
}

/// Étiquette « Bientôt » en pointillés.
class FsSoonTag extends StatelessWidget {
  const FsSoonTag({super.key, this.label = FsStrings.soon});
  final String label;

  @override
  Widget build(BuildContext context) {
    final t = FsTokens.of(context);
    return FsDashedBox(
      color: t.line,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      child: FsText(label, upper: true, style: FsType.sans(9, FontWeight.w900, em: 0.14, color: t.muted)),
    );
  }
}

/// Pied du rail : « Paramètres » et crédit RustDesk (obligation AGPL : reste visible).
class FsRailFoot extends StatelessWidget {
  const FsRailFoot({super.key, this.onSettings, this.version = '1.0.0', this.onCredit});
  final VoidCallback? onSettings;
  final String version;
  final VoidCallback? onCredit;

  @override
  Widget build(BuildContext context) {
    final t = FsTokens.of(context);
    return AnimatedContainer(
      duration: FsMotion.theme,
      padding: const EdgeInsets.only(top: 12),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: t.line))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        FsHover(
          onTap: onSettings,
          builder: (context, hover, _) => TweenAnimationBuilder<Color?>(
            tween: ColorTween(end: hover ? t.ink : t.muted),
            duration: FsMotion.quick,
            builder: (context, c, _) => SizedBox(
              height: 36,
              child: Row(children: [
                const SizedBox(width: 14),
                Icon(Icons.settings_rounded, size: 20, color: c),
                const SizedBox(width: 12),
                FsText(FsStrings.settings, style: FsType.sans(14, FontWeight.w600, color: c)),
              ]),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 8, left: 14),
          child: FsCredit(version: version, onTap: onCredit),
        ),
      ]),
    );
  }
}

/// « Technologie RustDesk · AGPL-3.0 » puis « FS Support x.y.z », 11 px, interligne 1,55.
class FsCredit extends StatelessWidget {
  const FsCredit({super.key, required this.version, this.onTap, this.oneLine = false, this.center = false});
  final String version;
  final VoidCallback? onTap;
  final bool oneLine;
  final bool center;

  @override
  Widget build(BuildContext context) {
    final t = FsTokens.of(context);
    final st = FsType.sans(11, FontWeight.w400, height: 1.55, color: t.muted);
    final strut = FsType.strut(11, height: 1.55);
    final tech = MouseRegion(
      cursor: onTap == null ? MouseCursor.defer : SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: CustomPaint(
          foregroundPainter: oneLine ? null : _DottedUnderline(t.muted),
          child: FsText(FsStrings.poweredBy, style: st, strut: strut),
        ),
      ),
    );
    if (oneLine) {
      return GestureDetector(
        onTap: onTap,
        child: FsText('${FsStrings.poweredBy} · ${FsStrings.license} · ${FsStrings.appName} $version',
            textAlign: center ? TextAlign.center : TextAlign.start,
            style: FsType.sans(11, FontWeight.w400, color: t.muted)),
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [tech, FsText(' · ${FsStrings.license}', style: st, strut: strut)]),
      FsText('${FsStrings.appName} $version', style: st, strut: strut),
    ]);
  }
}

class _DottedUnderline extends CustomPainter {
  _DottedUnderline(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // `text-decoration: underline dotted ; text-underline-offset: 2px` : points de 1 px, pas de 2 px
    final p = Paint()..color = color;
    final y = (size.height + 11) / 2 + 1.5;
    for (double x = 0; x < size.width - 0.5; x += 2) {
      canvas.drawRect(Rect.fromLTWH(x, y, 1, 1), p);
    }
  }

  @override
  bool shouldRepaint(_DottedUnderline oldDelegate) => oldDelegate.color != color;
}

/// Donne à l'enfant au moins la largeur disponible, davantage si son contenu l'exige (débord à droite,
/// sans avertissement), et garde pour soi la largeur disponible.
class _WidenToContent extends SingleChildRenderObjectWidget {
  const _WidenToContent({super.child});
  @override
  RenderObject createRenderObject(BuildContext context) => _RenderWiden();
}

class _RenderWiden extends RenderShiftedBox {
  _RenderWiden() : super(null);

  @override
  void performLayout() {
    final c = constraints;
    child!.layout(BoxConstraints(minWidth: c.maxWidth, maxWidth: double.infinity, maxHeight: c.maxHeight), parentUsesSize: true);
    size = c.constrain(Size(c.maxWidth, child!.size.height));
    (child!.parentData as BoxParentData).offset = Offset.zero;
  }
}
