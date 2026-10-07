// Barre de session (`.A-tb`) et son menu (`.A-tbmenu`).
// Dans le client, la barre réelle reste celle de RustDesk (`remote_toolbar.dart`) : seules ses couleurs
// et dimensions passent par [FsToolbarStyle]. Ces widgets servent de référence visuelle (banc).
import 'package:flutter/material.dart';

import '../strings.dart';
import '../tokens.dart';
import '../typography.dart';
import 'primitives.dart';

/// Couleurs et mesures de la barre de session, lues par `_ToolbarTheme` côté client.
class FsToolbarStyle {
  FsToolbarStyle._();
  static Color background(BuildContext c) => FsTokens.of(c).bg;
  static Color border(BuildContext c) => FsTokens.of(c).line;
  static Color icon(BuildContext c) => FsTokens.of(c).ink;
  static Color label(BuildContext c) => FsTokens.of(c).muted;
  static Color active(BuildContext c) => FsTokens.of(c).acc;
  static Color hover(BuildContext c) => FsTokens.of(c).hov;
  static Color danger(BuildContext c) => FsTokens.of(c).danger;

  /// Accent fixe (les constantes de `_ToolbarTheme` sont statiques) : olive.
  static const Color accent = Color(0xFF3A422D);
  static const Color accentHover = Color(0xFF2B3121);
  static const Color red = Color(0xFFA8432C);
  static const Color redHover = Color(0xFF8E3825);
  static const Color inactive = Color(0xFF515844);
  static const Color inactiveHover = Color(0xFF3C4232);
  static const double radius = 0;
}

enum FsTbKind { normal, pin, soon, end }

@immutable
class FsTbItem {
  const FsTbItem({required this.icon, this.label = '', this.kind = FsTbKind.normal, this.on = false, this.open = false, this.onTap, this.separator = false, this.anchor = false});
  const FsTbItem.sep()
      : icon = Icons.more_vert,
        label = '',
        kind = FsTbKind.normal,
        on = false,
        open = false,
        onTap = null,
        separator = true,
        anchor = false;

  final IconData icon;
  final String label;
  final FsTbKind kind;
  final bool on;
  final bool open;
  final VoidCallback? onTap;
  final bool separator;

  /// Bouton qui porte le menu déroulant (ancre du [LayerLink]).
  final bool anchor;
}

/// Barre de session flottante, collée au bord haut, avec sa poignée.
class FsSessionToolbar extends StatelessWidget {
  const FsSessionToolbar({super.key, required this.items, this.menuLink});
  final List<FsTbItem> items;

  /// Ancre posée sur le bouton « ouvert » : le menu (CompositedTransformFollower) se place sous lui.
  final LayerLink? menuLink;

  @override
  Widget build(BuildContext context) {
    final t = FsTokens.of(context);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      AnimatedContainer(
        duration: FsMotion.theme,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          color: t.bg,
          border: Border(left: BorderSide(color: t.line), right: BorderSide(color: t.line), bottom: BorderSide(color: t.line)),
          boxShadow: [BoxShadow(color: t.shadow, offset: const Offset(0, 14), blurRadius: 34, spreadRadius: -14)],
        ),
        child: SizedBox(
          height: 54,
          child: Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final it in items)
            if (it.separator)
              Container(width: 1, margin: const EdgeInsets.symmetric(horizontal: 5, vertical: 8), color: t.line)
            else
              it.anchor && menuLink != null
                  ? CompositedTransformTarget(link: menuLink!, child: _TbButton(item: it))
                  : _TbButton(item: it),
        ]),
        ),
      ),
    ]);
  }
}

/// Poignée sous la barre (`.A-handle`).
class FsToolbarHandle extends StatelessWidget {
  const FsToolbarHandle({super.key});

  @override
  Widget build(BuildContext context) {
    final t = FsTokens.of(context);
    return AnimatedContainer(
      duration: FsMotion.theme,
      width: 46,
      height: 14,
      decoration: BoxDecoration(
        color: t.bg,
        border: Border(left: BorderSide(color: t.line), right: BorderSide(color: t.line), bottom: BorderSide(color: t.line)),
      ),
      alignment: Alignment.center,
      child: OverflowBox(maxHeight: 16, child: Icon(Icons.expand_less_rounded, size: 16, color: t.muted)),
    );
  }
}

class _TbButton extends StatelessWidget {
  const _TbButton({required this.item});
  final FsTbItem item;

  @override
  Widget build(BuildContext context) {
    final t = FsTokens.of(context);
    final it = item;
    final w = switch (it.kind) { FsTbKind.pin => 40.0, FsTbKind.end => 82.0, _ => 62.0 };
    return Padding(
      padding: EdgeInsets.only(left: it.kind == FsTbKind.end ? 4 : 0),
      child: FsHover(
        onTap: it.onTap,
        builder: (context, hover, _) {
          Color bg = t.hov.withOpacity(0);
          Color fg = t.ink;
          Color lab = it.on ? t.ink : t.muted;
          if (hover) bg = t.hov;
          if (it.open) {
            bg = t.ink;
            fg = t.bg;
            lab = t.bg;
          }
          if (it.kind == FsTbKind.end) {
            bg = hover ? Color.alphaBlend(Colors.white.withOpacity(0.08), t.danger) : t.danger;
            fg = Colors.white;
            lab = Colors.white;
          }
          if (it.kind == FsTbKind.soon) fg = t.muted;
          Widget body = Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(it.icon, size: it.kind == FsTbKind.pin ? 18 : 21, color: it.kind == FsTbKind.pin ? t.acc : fg),
            if (it.label.isNotEmpty) ...[
              const SizedBox(height: 3),
              FsText(it.label, style: FsType.sans(10.5, FontWeight.w600, color: lab)),
            ],
          ]);
          return AnimatedContainer(
            duration: FsMotion.hover,
            width: w,
            height: 54,
            decoration: BoxDecoration(color: bg, border: it.kind == FsTbKind.soon ? Border.all(color: t.line) : null),
            child: Stack(clipBehavior: Clip.none, children: [
              if (it.kind == FsTbKind.soon) Positioned.fill(child: CustomPaint(painter: FsHatch(t.hov, period: 7))),
              Positioned.fill(child: body),
              if (it.kind == FsTbKind.soon)
                Positioned(
                  top: 2,
                  right: 2,
                  child: FsText(FsStrings.soon, upper: true, style: FsType.sans(7.5, FontWeight.w900, em: 0.12, color: t.muted)),
                ),
              if (it.on && !it.open)
                Positioned(left: 14, right: 14, bottom: 2, child: Container(height: 2, color: t.acc)),
            ]),
          );
        },
      ),
    );
  }
}

/// Menu déroulant de la barre (`.A-tbmenu`) : rubriques en capitales, coches d'accent.
class FsToolbarMenu extends StatelessWidget {
  const FsToolbarMenu({super.key, required this.sections, this.width = 292, this.open = true});

  /// Rubriques successives : (titre facultatif, entrées).
  final List<(String?, List<FsMenuEntry>)> sections;
  final double width;
  final bool open;

  @override
  Widget build(BuildContext context) {
    final t = FsTokens.of(context);
    final children = <Widget>[];
    for (var i = 0; i < sections.length; i++) {
      if (i > 0) children.add(Container(height: 1, margin: const EdgeInsets.symmetric(vertical: 6), color: t.line));
      final (title, entries) = sections[i];
      if (title != null) {
        children.add(Padding(padding: const EdgeInsets.fromLTRB(14, 8, 14, 4), child: FsEyebrow(title)));
      }
      for (final e in entries) {
        children.add(_MenuRow(entry: e));
      }
    }
    return IgnorePointer(
      ignoring: !open,
      child: AnimatedOpacity(
        opacity: open ? 1 : 0,
        duration: const Duration(milliseconds: 220),
        child: AnimatedSlide(
          offset: Offset(0, open ? 0 : -6 / 365),
          duration: FsMotion.slide,
          curve: FsMotion.ease,
          child: AnimatedContainer(
            duration: FsMotion.theme,
            width: width,
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(
              color: t.bg,
              border: Border.all(color: t.line),
              boxShadow: [BoxShadow(color: t.shadow, offset: const Offset(0, 18), blurRadius: 40, spreadRadius: -16)],
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: children),
          ),
        ),
      ),
    );
  }
}

@immutable
class FsMenuEntry {
  const FsMenuEntry(this.label, {this.checked = false, this.onTap});
  final String label;
  final bool checked;
  final VoidCallback? onTap;
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({required this.entry});
  final FsMenuEntry entry;

  @override
  Widget build(BuildContext context) {
    final t = FsTokens.of(context);
    return FsHover(
      onTap: entry.onTap,
      builder: (context, hover, _) => AnimatedContainer(
        duration: FsMotion.hover,
        height: 34,
        color: hover ? t.hov : t.hov.withOpacity(0),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(children: [
          AnimatedOpacity(
            opacity: entry.checked ? 1 : 0,
            duration: FsMotion.hover,
            child: Icon(Icons.check_rounded, size: 18, color: t.acc),
          ),
          const SizedBox(width: 10),
          FsText(entry.label, style: FsType.sans(13.5, FontWeight.w400, color: t.ink)),
        ]),
      ),
    );
  }
}
