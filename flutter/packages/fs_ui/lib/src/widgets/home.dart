// Accueil de l'Atelier : champ de connexion, en-têtes de panneau, panneaux en fondu, emplacements
// « Bientôt », états vides, barre d'état, barre de titre — et leur assemblage [FsHomeView].
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../strings.dart';
import '../svg_path.dart';
import '../models.dart';
import '../tokens.dart';
import '../typography.dart';
import 'primitives.dart';

/// Bloc « Contrôler un poste à distance » (`.A-connect`).
class FsConnectBar extends StatefulWidget {
  const FsConnectBar({
    super.key,
    this.controller,
    this.focusNode,
    this.onConnect,
    this.onFiles,
    this.onChanged,
    this.field,
    this.trailing,
    this.hint = FsStrings.idHint,
  });

  final TextEditingController? controller;
  final FocusNode? focusNode;
  final ValueChanged<String>? onConnect;
  final ValueChanged<String>? onFiles;

  /// Saisie en cours (le client s'en sert pour filtrer la liste des appareils).
  final ValueChanged<String>? onChanged;

  /// Champ fourni par l'appelant (autocomplétion RustDesk) ; il est posé dans le cadre de l'Atelier.
  final Widget? field;

  /// Bouton supplémentaire après « Fichiers » (menu « autres modes » de RustDesk).
  final Widget? trailing;
  final String hint;

  @override
  State<FsConnectBar> createState() => _FsConnectBarState();
}

class _FsConnectBarState extends State<FsConnectBar> {
  late final TextEditingController _c = widget.controller ?? TextEditingController();
  late final FocusNode _f = widget.focusNode ?? FocusNode();

  @override
  void initState() {
    super.initState();
    _f.addListener(_onFocus);
  }

  void _onFocus() => setState(() {});

  @override
  void dispose() {
    _f.removeListener(_onFocus);
    if (widget.controller == null) _c.dispose();
    if (widget.focusNode == null) _f.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = FsTokens.of(context);
    final focused = _f.hasFocus;
    return AnimatedContainer(
      duration: FsMotion.theme,
      padding: const EdgeInsets.only(bottom: 22),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: t.line))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const FsEyebrow(FsStrings.remoteControl),
        const SizedBox(height: 10),
        SizedBox(
          height: FsDims.field,
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(
              child: GestureDetector(
                onTap: () => _f.requestFocus(),
                child: AnimatedContainer(
                  duration: FsMotion.quick,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: t.field,
                    border: Border.all(color: focused ? t.acc : t.line),
                    boxShadow: [BoxShadow(color: focused ? t.sel : t.sel.withOpacity(0), spreadRadius: 3)],
                  ),
                  child: Row(children: [
                    Icon(Icons.search_rounded, size: 20, color: t.muted),
                    const SizedBox(width: 10),
                    Expanded(child: widget.field ?? FsIdField(controller: _c, focusNode: _f, hint: widget.hint, onSubmitted: widget.onConnect, onChanged: widget.onChanged)),
                  ]),
                ),
              ),
            ),
            const SizedBox(width: 10),
            FsButton(label: FsStrings.connect, trailing: Icons.arrow_forward_rounded, onPressed: () => widget.onConnect?.call(_c.text)),
            const SizedBox(width: 10),
            FsButton(
                label: FsStrings.files,
                leading: Icons.drive_file_move_rounded,
                kind: FsButtonKind.ghost,
                onPressed: widget.onFiles == null ? null : () => widget.onFiles!(_c.text)),
            if (widget.trailing != null) ...[const SizedBox(width: 10), widget.trailing!],
          ]),
        ),
      ]),
    );
  }
}

/// Champ de saisie nu (texte 500 16 px), sans cadre : le cadre est celui de [FsConnectBar].
class FsIdField extends StatelessWidget {
  const FsIdField({super.key, required this.controller, required this.focusNode, this.hint = FsStrings.idHint, this.onSubmitted, this.inputFormatters, this.onChanged});
  final TextEditingController controller;
  final FocusNode focusNode;
  final String hint;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  final List<TextInputFormatter>? inputFormatters;

  @override
  Widget build(BuildContext context) {
    final t = FsTokens.of(context);
    return TextField(
      controller: controller,
      focusNode: focusNode,
      onSubmitted: onSubmitted,
      onChanged: onChanged,
      inputFormatters: inputFormatters,
      cursorColor: t.acc,
      cursorWidth: 1.5,
      style: FsType.sans(16, FontWeight.w500, height: 1.375, color: t.ink),
      decoration: InputDecoration(
        isCollapsed: true,
        contentPadding: EdgeInsets.zero,
        filled: false,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        hintText: hint,
        hintStyle: FsType.sans(16, FontWeight.w500, height: 1.375, color: t.muted.withOpacity(0.75)),
      ),
    );
  }
}

/// En-tête d'un panneau (`.A-head`) : titre 26 px, sous-titre, outils à droite.
class FsPanelHead extends StatelessWidget {
  const FsPanelHead({super.key, required this.title, this.sub, this.tools = const []});
  final String title;
  final String? sub;
  final List<Widget> tools;

  @override
  Widget build(BuildContext context) {
    final t = FsTokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 12),
      child: Row(children: [
        FsText(title, style: FsType.sans(26, FontWeight.w800, em: -0.04, color: t.ink)),
        if (sub != null) ...[
          const SizedBox(width: 14),
          FsText(sub!, style: FsType.sans(13, FontWeight.w400, color: t.muted)),
        ],
        const Spacer(),
        ...tools,
      ]),
    );
  }
}

/// Outils de la liste : « Par entreprise », liste / tuiles compactes / cartes, tri.
class FsListTools extends StatelessWidget {
  const FsListTools({super.key, required this.byCompany, this.onByCompany, this.listView = true, this.tileView = false, this.onList, this.onTiles, this.onCards, this.onSort, this.extra = const []});
  final bool byCompany;
  final VoidCallback? onByCompany;
  final bool listView;

  /// Tuiles compactes (mode « tile » de RustDesk) ; les cartes sont actives quand ni liste ni tuiles.
  final bool tileView;
  final VoidCallback? onList;
  final VoidCallback? onTiles;
  final VoidCallback? onCards;
  final void Function(Offset globalPosition)? onSort;
  final List<Widget> extra;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        ...extra,
        FsChip(label: FsStrings.byCompany, icon: Icons.corporate_fare_rounded, on: byCompany, onPressed: onByCompany),
        const SizedBox(width: 6 + 6),
        FsIconButton(icon: Icons.view_list_rounded, tooltip: FsStrings.list, on: listView, onPressed: onList),
        const SizedBox(width: 6),
        if (onTiles != null) ...[
          FsIconButton(icon: Icons.view_module_rounded, tooltip: FsStrings.tiles, on: tileView, onPressed: onTiles),
          const SizedBox(width: 6),
        ],
        FsIconButton(icon: Icons.grid_view_rounded, tooltip: FsStrings.cards, on: !listView && !tileView, onPressed: onCards),
        const SizedBox(width: 6),
        Builder(
          builder: (bctx) => FsIconButton(
            icon: Icons.sort_rounded,
            tooltip: FsStrings.sort,
            onPressed: onSort == null
                ? null
                : () {
                    final box = bctx.findRenderObject() as RenderBox?;
                    onSort!(box == null ? Offset.zero : box.localToGlobal(Offset(0, box.size.height)));
                  },
          ),
        ),
      ]);
}

/// Pile de panneaux : seul le panneau actif est construit, l'ancien s'efface en glissant (8 px).
class FsPanelSwitcher extends StatelessWidget {
  const FsPanelSwitcher({super.key, required this.panelKey, required this.child});
  final String panelKey;
  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
        duration: FsMotion.theme,
        reverseDuration: FsMotion.fade,
        switchInCurve: FsMotion.ease,
        switchOutCurve: FsMotion.ease,
        layoutBuilder: (cur, prev) => Stack(fit: StackFit.expand, children: [...prev, if (cur != null) cur]),
        transitionBuilder: (child, a) => AnimatedBuilder(
          animation: a,
          child: child,
          builder: (context, c) {
            final o = const Interval(0.1, 0.85, curve: Curves.ease).transform(a.value);
            return Opacity(opacity: o, child: Transform.translate(offset: Offset(0, 8 * (1 - a.value)), child: c));
          },
        ),
        child: KeyedSubtree(key: ValueKey(panelKey), child: child),
      );
}

/// État vide (`.A-empty`) : filet d'encre, titre, texte, action.
class FsEmptyState extends StatelessWidget {
  const FsEmptyState({super.key, required this.title, required this.text, this.action});
  final String title;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final t = FsTokens.of(context);
    return Align(
      alignment: Alignment.topLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 520),
        margin: const EdgeInsets.only(top: 26),
        padding: const EdgeInsets.symmetric(vertical: 30),
        decoration: BoxDecoration(border: Border(top: BorderSide(color: t.ink))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          FsText(title, style: FsType.sans(22, FontWeight.w800, em: -0.035, color: t.ink)),
          const SizedBox(height: 10),
          FsText(text, style: FsType.sans(14, FontWeight.w400, color: t.muted)),
          if (action != null) ...[const SizedBox(height: 10), action!],
        ]),
      ),
    );
  }
}

/// Emplacement prévu (`.A-slot`) : pointillés, hachures, trois colonnes « Où / Source / Impact ».
class FsSlot extends StatelessWidget {
  const FsSlot({super.key, required this.title, required this.text, this.cols = const []});
  final String title;
  final String text;
  final List<(String, InlineSpan)> cols;

  @override
  Widget build(BuildContext context) {
    final t = FsTokens.of(context);
    return Align(
      alignment: Alignment.topLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 760),
        margin: const EdgeInsets.only(top: 26),
        child: CustomPaint(
          painter: FsHatch(t.hov),
          child: FsDashedBox(
            color: t.line,
            padding: const EdgeInsets.fromLTRB(36 - 1, 34 - 1, 36 - 1, 34 - 1),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              const FsEyebrow(FsStrings.slotEyebrow),
              const SizedBox(height: 10),
              FsText(title, style: FsType.sans(24, FontWeight.w800, em: -0.04, color: t.ink)),
              const SizedBox(height: 10),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: FsText(text, style: FsType.sans(14, FontWeight.w400, color: t.muted)),
              ),
              if (cols.isNotEmpty) ...[
                const SizedBox(height: 10 + 12),
                Container(
                  decoration: BoxDecoration(border: Border(top: BorderSide(color: t.line))),
                  child: IntrinsicHeight(
                    child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      for (var i = 0; i < cols.length; i++)
                        Expanded(
                          child: Container(
                            padding: EdgeInsets.fromLTRB(i == 0 ? 0 : 14, 12, 14, 0),
                            decoration: i == 0 ? null : BoxDecoration(border: Border(left: BorderSide(color: t.line))),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              FsText(cols[i].$1, style: FsType.sans(13.5, FontWeight.w700, color: t.ink)),
                              const SizedBox(height: 2),
                              Text.rich(cols[i].$2,
                                  style: FsType.sans(13, FontWeight.w400, color: t.muted),
                                  textHeightBehavior: FsType.heightBehavior,
                                  textScaler: TextScaler.noScaling),
                            ]),
                          ),
                        ),
                    ]),
                  ),
                ),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

/// Code en ligne (`code` dans les textes des emplacements) : chasse fixe, taille réduite comme un navigateur
/// (13 px × 13/16), sans fond.
InlineSpan fsInlineCode(BuildContext context, String code) {
  final t = FsTokens.of(context);
  return TextSpan(text: code, style: FsType.mono(13 * 13 / 16, FontWeight.w400, color: t.muted));
}

enum FsServiceState { ready, connecting, notReady, stopped }

/// Barre d'état (`.A-status`) : pastille, « Prêt », filet, serveur.
class FsStatusBar extends StatelessWidget {
  const FsStatusBar({super.key, required this.state, this.server = FsStrings.serverFs, this.label, this.action, this.trailing});
  final FsServiceState state;
  final String server;
  final String? label;
  final Widget? action;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final t = FsTokens.of(context);
    final (color, text) = switch (state) {
      FsServiceState.ready => (t.on, FsStrings.ready),
      FsServiceState.connecting => (const Color(0xFFD9A43A), FsStrings.connecting),
      FsServiceState.notReady => (t.danger, FsStrings.notReady),
      FsServiceState.stopped => (t.off, FsStrings.notReady),
    };
    final st = FsType.sans(12.5, FontWeight.w400, color: t.muted);
    return AnimatedContainer(
      duration: FsMotion.theme,
      height: FsDims.statusBar,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(color: t.bg2, border: Border(top: BorderSide(color: t.line))),
      child: Row(children: [
        FsDot(color: color),
        const SizedBox(width: 10),
        FsText(label ?? text, style: FsType.sans(12.5, FontWeight.w600, color: t.ink)),
        const SizedBox(width: 10),
        Container(width: 1, height: 12, color: t.line),
        const SizedBox(width: 10),
        FsText(server, style: st),
        if (action != null) ...[const SizedBox(width: 10), action!],
        const Spacer(),
        if (trailing != null) trailing!,
      ]),
    );
  }
}

/// Onglet de la barre de titre (`.A-tab`).
@immutable
class FsTitleTabData {
  const FsTitleTabData({required this.label, this.icon, this.os, this.on = false, this.secure = false, this.closable = false});
  final String label;
  final IconData? icon;
  final FsOs? os;
  final bool on;
  final bool secure;
  final bool closable;
}

/// Barre de titre de l'Atelier (`.A-title`) : monogramme, onglets, boutons de fenêtre.
/// Utilisée par le banc ; dans le client, la barre est celle de RustDesk (`DesktopTab`) recolorée.
class FsTitleBar extends StatelessWidget {
  const FsTitleBar({super.key, required this.tabs, this.showAdd = false, this.onTab});
  final List<FsTitleTabData> tabs;
  final bool showAdd;
  final ValueChanged<int>? onTab;

  @override
  Widget build(BuildContext context) {
    final t = FsTokens.of(context);
    return AnimatedContainer(
      duration: FsMotion.theme,
      height: FsDims.titleBar,
      color: t.bg2,
      child: Stack(children: [
        Positioned(left: 0, right: 0, bottom: 0, child: AnimatedContainer(duration: FsMotion.theme, height: 1, color: t.line)),
        Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Padding(padding: EdgeInsets.fromLTRB(14, 10, 8, 0), child: Align(alignment: Alignment.topLeft, child: FsMark(size: 18))),
          for (var i = 0; i < tabs.length; i++) FsTitleTab(data: tabs[i], onTap: onTab == null ? null : () => onTab!(i)),
          if (showAdd)
            Padding(
              padding: const EdgeInsets.only(left: 12, right: 12, bottom: 1),
              child: Icon(Icons.add_rounded, size: 17, color: t.muted),
            ),
          const Spacer(),
          for (final i in [Icons.remove_rounded, Icons.crop_square_rounded, Icons.close_rounded])
            SizedBox(width: 46, child: Icon(i, size: 17, color: t.muted)),
        ]),
      ]),
    );
  }
}

/// Onglet de la barre de titre : l'onglet actif porte un trait d'accent de 2 px et « s'ouvre » sur la page.
class FsTitleTab extends StatelessWidget {
  const FsTitleTab({super.key, required this.data, this.onTap});
  final FsTitleTabData data;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = FsTokens.of(context);
    final d = data;
    final fg = d.on ? t.ink : t.muted;
    return GestureDetector(
      onTap: onTap,
      child: Stack(children: [
        AnimatedContainer(
          duration: FsMotion.theme,
          height: FsDims.titleBar - 1,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: d.on ? t.bg : t.bg.withOpacity(0),
            border: Border(right: BorderSide(color: t.line)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (d.icon != null) Icon(d.icon, size: 17, color: fg),
            if (d.os != null) FsPathIcon(d.os == FsOs.android ? FsOsPaths.android : FsOsPaths.windows, size: 14, color: fg),
            const SizedBox(width: 8),
            FsText(d.label, style: FsType.sans(13, FontWeight.w600, color: fg)),
            if (d.secure) ...[const SizedBox(width: 8), Icon(Icons.lock_rounded, size: 14, color: t.on)],
            if (d.closable) ...[const SizedBox(width: 8 + 4), Icon(Icons.close_rounded, size: 15, color: t.muted)],
          ]),
        ),
        Positioned(
          left: 0,
          right: 1,
          top: 0,
          child: AnimatedContainer(duration: FsMotion.theme, height: 2, color: d.on ? t.acc : t.acc.withOpacity(0)),
        ),
        Positioned(
          left: 0,
          right: 1,
          top: FsDims.titleBar - 1,
          child: AnimatedContainer(duration: FsMotion.theme, height: 1, color: d.on ? t.bg : t.bg.withOpacity(0)),
        ),
      ]),
    );
  }
}

/// Fenêtre d'accueil complète (sans barre de titre) : rail, colonne principale, barre d'état.
class FsHomeView extends StatelessWidget {
  const FsHomeView({super.key, required this.rail, required this.connect, required this.panel, required this.status});
  final Widget rail;
  final Widget connect;
  final Widget panel;
  final Widget status;

  @override
  Widget build(BuildContext context) {
    final t = FsTokens.of(context);
    return AnimatedContainer(
      duration: FsMotion.theme,
      color: t.bg,
      child: DefaultTextStyle.merge(
        style: FsType.sans(14, FontWeight.w400, color: t.ink),
        child: FsToastHost(
          child: Column(children: [
            Expanded(
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                rail,
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(32, 24, 32, 0),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      connect,
                      Expanded(child: panel),
                    ]),
                  ),
                ),
              ]),
            ),
            status,
          ]),
        ),
      ),
    );
  }
}
