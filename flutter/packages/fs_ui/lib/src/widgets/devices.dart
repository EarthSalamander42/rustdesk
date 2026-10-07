// Liste filetée des appareils (`.A-cols`, `.A-group`, `.A-row`) : par entreprise ou à plat.
import 'package:flutter/material.dart';

import '../models.dart';
import '../strings.dart';
import '../svg_path.dart';
import '../tokens.dart';
import '../typography.dart';
import 'primitives.dart';

/// Rappels communs à toutes les lignes.
@immutable
class FsDeviceActions {
  const FsDeviceActions({this.onSelect, this.onConnect, this.onMore, this.onFiles});
  final void Function(FsDevice d)? onSelect;
  final void Function(FsDevice d)? onConnect;

  /// Menu « Plus » : position globale du clic pour ouvrir le menu contextuel au bon endroit.
  final void Function(FsDevice d, Offset globalPosition)? onMore;
  final void Function(FsDevice d)? onFiles;
}

/// Grille des colonnes : tuile 52, appareil (reste), ID 140, dernière session 150, actions 176.
class _Cols extends StatelessWidget {
  const _Cols({required this.cells});
  final List<Widget> cells;

  @override
  Widget build(BuildContext context) => Row(children: [
        SizedBox(width: FsDims.colTile, child: cells[0]),
        Expanded(child: cells[1]),
        SizedBox(width: FsDims.colId, child: cells[2]),
        SizedBox(width: FsDims.colLast, child: cells[3]),
        SizedBox(width: FsDims.colActs, child: cells[4]),
      ]);
}

/// En-tête des colonnes, souligné à l'encre.
class FsColumnsHeader extends StatelessWidget {
  const FsColumnsHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final t = FsTokens.of(context);
    Widget h(String s) => FsText(s, upper: true, style: FsType.eyebrow(t.muted, size: 10, em: 0.16), maxLines: 1, softWrap: false);
    return AnimatedContainer(
      duration: FsMotion.theme,
      padding: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: t.ink))),
      child: _Cols(cells: [
        const SizedBox(),
        h(FsStrings.colDevice),
        h(FsStrings.colId),
        h(FsStrings.colLast),
        const SizedBox(),
      ]),
    );
  }
}

/// Tuile du système (`.A-ostile`) : pleine si en ligne, filaire sinon, pastille d'état en bas à droite.
class FsOsTile extends StatelessWidget {
  const FsOsTile({super.key, required this.os, required this.online, this.size = 34});
  final FsOs os;
  final bool online;
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = FsTokens.of(context);
    final path = switch (os) {
      FsOs.android => FsOsPaths.android,
      FsOs.mac => FsOsPaths.apple,
      FsOs.linux => FsOsPaths.linux,
      _ => FsOsPaths.windows,
    };
    return SizedBox.square(
      dimension: size,
      child: Stack(clipBehavior: Clip.none, children: [
        Positioned.fill(
          child: AnimatedContainer(
            duration: FsMotion.theme,
            decoration: BoxDecoration(
              color: online ? t.acc : t.acc.withOpacity(0),
              border: online ? null : Border.all(color: t.line),
            ),
            alignment: Alignment.center,
            child: FsPathIcon(path, size: 18, color: online ? t.accFg : t.muted),
          ),
        ),
        Positioned(
          right: -6,
          bottom: -6,
          child: AnimatedContainer(
            duration: FsMotion.theme,
            width: 14,
            height: 14,
            decoration: BoxDecoration(color: t.bg, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: FsDot(color: online ? t.on : t.off, size: 10),
          ),
        ),
      ]),
    );
  }
}

/// Ligne d'appareil (`.A-row`) : 58 px, filet léger au-dessus (ou au-dessous en liste à plat).
class FsDeviceRow extends StatelessWidget {
  const FsDeviceRow({
    super.key,
    required this.device,
    this.selected = false,
    this.actions = const FsDeviceActions(),
    this.flat = false,
    this.forceHover = false,
  });

  final FsDevice device;
  final bool selected;
  final FsDeviceActions actions;
  final bool flat;
  final bool forceHover;

  @override
  Widget build(BuildContext context) {
    final t = FsTokens.of(context);
    final d = device;
    return FsHover(
      forceHover: forceHover,
      cursor: SystemMouseCursors.basic,
      onTap: actions.onSelect == null ? null : () => actions.onSelect!(d),
      onDoubleTap: d.online && actions.onConnect != null ? () => actions.onConnect!(d) : null,
      onSecondaryTapDown: actions.onMore == null ? null : (e) => actions.onMore!(d, e.globalPosition),
      builder: (context, hover, _) {
        final reveal = hover || selected;
        return AnimatedContainer(
          duration: FsMotion.hover,
          height: FsDims.row,
          decoration: BoxDecoration(
            color: selected ? t.sel : (hover ? t.hov : t.hov.withOpacity(0)),
            border: flat ? Border(bottom: BorderSide(color: t.line2)) : Border(top: BorderSide(color: t.line2)),
          ),
          child: Stack(children: [
            _Cols(cells: [
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Align(alignment: Alignment.centerLeft, child: FsOsTile(os: d.os, online: d.online)),
              ),
              Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                FsText(d.label,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: FsType.sans(14.5, FontWeight.w600, color: t.ink)),
                if (d.user.isNotEmpty)
                  FsText(d.user,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: FsType.sans(12.5, FontWeight.w400, color: t.muted)),
              ]),
              FsText(fsFormatId(d.id), maxLines: 1, softWrap: false, style: FsType.mono(13, FontWeight.w400, color: t.ink)),
              FsText(d.lastSession, maxLines: 1, overflow: TextOverflow.ellipsis, style: FsType.sans(13, FontWeight.w400, color: t.muted)),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                  _GoButton(device: d, reveal: reveal, onConnect: actions.onConnect),
                  const SizedBox(width: 4),
                  Builder(
                    builder: (bctx) => FsIconButton(
                      icon: Icons.more_vert_rounded,
                      tooltip: FsStrings.more,
                      onPressed: actions.onMore == null
                          ? null
                          : () {
                              final box = bctx.findRenderObject() as RenderBox?;
                              final pos = box == null ? Offset.zero : box.localToGlobal(Offset(0, box.size.height));
                              actions.onMore!(d, pos);
                            },
                    ),
                  ),
                ]),
              ),
            ]),
            // barre d'accent de la sélection (box-shadow inset 3px)
            Positioned(
              left: 0,
              top: flat ? 0 : 1,
              bottom: flat ? 1 : 0,
              child: AnimatedContainer(
                duration: FsMotion.fade,
                width: 3,
                color: selected ? t.acc : t.acc.withOpacity(0),
              ),
            ),
          ]),
        );
      },
    );
  }
}

class _GoButton extends StatelessWidget {
  const _GoButton({required this.device, required this.reveal, this.onConnect});
  final FsDevice device;
  final bool reveal;
  final void Function(FsDevice d)? onConnect;

  @override
  Widget build(BuildContext context) {
    final t = FsTokens.of(context);
    final on = device.online;
    return IgnorePointer(
      ignoring: !on || !reveal,
      child: AnimatedOpacity(
        opacity: reveal ? (on ? 1 : 0.45) : 0,
        duration: FsMotion.quick,
        child: AnimatedSlide(
          offset: Offset(reveal ? 0 : 6 / 107, 0),
          duration: FsMotion.slide,
          curve: FsMotion.ease,
          child: FsHover(
            onTap: onConnect == null ? null : () => onConnect!(device),
            builder: (context, hover, _) {
              final fg = hover ? t.accFg : t.ink;
              return AnimatedContainer(
                duration: FsMotion.hover,
                height: 32,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: hover ? t.acc : t.acc.withOpacity(0),
                  border: Border.all(color: hover ? t.acc : t.line),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  FsText(on ? FsStrings.control : FsStrings.offline, style: FsType.sans(13, FontWeight.w600, color: fg)),
                  const SizedBox(width: 6),
                  Icon(on ? Icons.arrow_forward_rounded : Icons.cloud_off_rounded, size: 16, color: fg),
                ]),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Groupe d'une entreprise (`.A-group`) : en-tête repliable animé (hauteur réelle, 420 ms).
class FsCompanyGroup extends StatefulWidget {
  const FsCompanyGroup({
    super.key,
    required this.company,
    required this.rowBuilder,
    this.initiallyOpen,
    this.onToggle,
  });

  final FsCompany company;
  final Widget Function(FsDevice d) rowBuilder;
  final bool? initiallyOpen;
  final ValueChanged<bool>? onToggle;

  @override
  State<FsCompanyGroup> createState() => _FsCompanyGroupState();
}

class _FsCompanyGroupState extends State<FsCompanyGroup> with SingleTickerProviderStateMixin {
  late bool _open = widget.initiallyOpen ?? !widget.company.unclassified;
  late final AnimationController _c = AnimationController(vsync: this, duration: FsMotion.accordion, value: _open ? 1 : 0);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _open = !_open);
    _open ? _c.forward() : _c.reverse();
    widget.onToggle?.call(_open);
  }

  @override
  Widget build(BuildContext context) {
    final t = FsTokens.of(context);
    final c = widget.company;
    final on = c.onlineCount;
    return AnimatedContainer(
      duration: FsMotion.theme,
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: t.line))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        FsHover(
          onTap: _toggle,
          builder: (context, hover, _) => SizedBox(
            height: FsDims.groupHead,
            child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              AnimatedRotation(
                turns: _open ? 0 : -0.25,
                duration: const Duration(milliseconds: 400),
                curve: FsMotion.ease,
                child: Icon(Icons.expand_more_rounded, size: 20, color: t.muted),
              ),
              const SizedBox(width: 10),
              FsText(c.name, style: FsType.sans(15, FontWeight.w800, em: -0.02, color: t.ink)),
              const SizedBox(width: 10),
              FsText(FsStrings.nDevices(c.devices.length), style: FsType.sans(12, FontWeight.w600, color: t.muted)),
              const Spacer(),
              if (on > 0) ...[FsDot(color: t.on), const SizedBox(width: 6)],
              FsText(on > 0 ? FsStrings.nOnline(on) : FsStrings.noneOnline, style: FsType.sans(12, FontWeight.w400, color: t.muted)),
              const SizedBox(width: 12),
            ]),
          ),
        ),
        SizeTransition(
          sizeFactor: CurvedAnimation(parent: _c, curve: FsMotion.ease),
          axisAlignment: -1,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (final d in c.devices) widget.rowBuilder(d),
          ]),
        ),
      ]),
    );
  }
}

/// Défilement fin, discret au repos (`scrollbar-width: thin`).
class FsScroll extends StatefulWidget {
  const FsScroll({super.key, required this.builder, this.controller});
  final Widget Function(ScrollController c) builder;
  final ScrollController? controller;

  @override
  State<FsScroll> createState() => _FsScrollState();
}

class _FsScrollState extends State<FsScroll> {
  late final ScrollController _c = widget.controller ?? ScrollController();

  @override
  void dispose() {
    if (widget.controller == null) _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = FsTokens.of(context);
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: RawScrollbar(
        controller: _c,
        thickness: 6,
        thumbColor: t.line,
        fadeDuration: FsMotion.fade,
        timeToFade: const Duration(milliseconds: 900),
        child: widget.builder(_c),
      ),
    );
  }
}

/// Liste par entreprise : groupes successifs, marge basse de 24 px.
class FsGroupedDeviceList extends StatelessWidget {
  const FsGroupedDeviceList({
    super.key,
    required this.companies,
    required this.rowBuilder,
    this.isOpen,
    this.onToggle,
    this.controller,
  });

  final List<FsCompany> companies;
  final Widget Function(FsDevice d) rowBuilder;
  final bool? Function(FsCompany c)? isOpen;
  final void Function(FsCompany c, bool open)? onToggle;
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) => FsScroll(
        controller: controller,
        builder: (sc) => ListView.builder(
          controller: sc,
          padding: const EdgeInsets.only(bottom: 24),
          itemCount: companies.length,
          itemBuilder: (context, i) {
            final c = companies[i];
            return FsCompanyGroup(
              key: ValueKey('fs-company-${c.name}'),
              company: c,
              rowBuilder: rowBuilder,
              initiallyOpen: isOpen?.call(c),
              onToggle: onToggle == null ? null : (o) => onToggle!(c, o),
            );
          },
        ),
      );
}

/// Liste à plat (Récents, Favoris…).
class FsFlatDeviceList extends StatelessWidget {
  const FsFlatDeviceList({super.key, required this.devices, required this.rowBuilder, this.controller});
  final List<FsDevice> devices;
  final Widget Function(FsDevice d) rowBuilder;
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) => FsScroll(
        controller: controller,
        builder: (sc) => ListView.builder(
          controller: sc,
          padding: const EdgeInsets.only(bottom: 24),
          itemCount: devices.length,
          itemBuilder: (context, i) => rowBuilder(devices[i]),
        ),
      );
}
