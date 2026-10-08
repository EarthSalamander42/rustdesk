// Appareils en cartes (220 × 140) et en tuiles compactes (220 × 42), à la charte de l'Atelier :
// papier, filet 1 px, angles droits, tuile système olive (pleine en ligne, filaire hors ligne),
// identifiant en chasse fixe. Remplacent les cartes pastel de RustDesk (couleur tirée de l'ID).
import 'package:flutter/material.dart';

import '../models.dart';
import '../strings.dart';
import '../tokens.dart';
import '../typography.dart';
import 'devices.dart';
import 'primitives.dart';

/// Bouton « Plus » qui renvoie la position globale de son bord bas (menu contextuel).
class _MoreButton extends StatelessWidget {
  const _MoreButton({required this.device, this.onMore, this.size = FsDims.iconButton});
  final FsDevice device;
  final void Function(FsDevice d, Offset globalPosition)? onMore;
  final double size;

  @override
  Widget build(BuildContext context) => Builder(
        builder: (bctx) => FsIconButton(
          icon: Icons.more_vert_rounded,
          tooltip: FsStrings.more,
          size: size,
          onPressed: onMore == null
              ? null
              : () {
                  final box = bctx.findRenderObject() as RenderBox?;
                  final pos = box == null ? Offset.zero : box.localToGlobal(Offset(0, box.size.height));
                  onMore!(device, pos);
                },
        ),
      );
}

/// Cadre commun : papier, filet (encre au survol, olive à la sélection), barre d'accent en haut.
class _Frame extends StatelessWidget {
  const _Frame({required this.hover, required this.selected, required this.child});
  final bool hover;
  final bool selected;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = FsTokens.of(context);
    return AnimatedContainer(
      duration: FsMotion.hover,
      decoration: BoxDecoration(
        color: selected ? t.sel : (hover ? t.hov : t.bg2),
        border: Border.all(color: selected ? t.acc : (hover ? t.ink : t.line)),
      ),
      child: Stack(children: [
        Positioned.fill(child: child),
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          child: AnimatedContainer(
            duration: FsMotion.fade,
            height: 3,
            color: selected ? t.acc : t.acc.withOpacity(0),
          ),
        ),
      ]),
    );
  }
}

/// Carte d'appareil (220 × 140) : tuile système, nom, utilisateur, identifiant ; « Contrôler » au survol.
class FsDeviceCard extends StatelessWidget {
  const FsDeviceCard({
    super.key,
    required this.device,
    this.selected = false,
    this.actions = const FsDeviceActions(),
    this.allowOffline = false,
    this.leading,
  });

  final FsDevice device;
  final bool selected;
  final FsDeviceActions actions;
  final bool allowOffline;

  /// Remplace le bouton « Plus » (case de multi-sélection, par exemple).
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final t = FsTokens.of(context);
    final d = device;
    final canGo = (d.online || allowOffline) && actions.onConnect != null;
    return FsHover(
      cursor: SystemMouseCursors.basic,
      onTap: actions.onSelect == null ? null : () => actions.onSelect!(d),
      onDoubleTap: canGo ? () => actions.onConnect!(d) : null,
      onSecondaryTapDown: actions.onMore == null ? null : (e) => actions.onMore!(d, e.globalPosition),
      builder: (context, hover, _) {
        final reveal = hover || selected;
        return _Frame(
          hover: hover,
          selected: selected,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 6, 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                FsOsTile(os: d.os, online: d.online),
                const Spacer(),
                leading ?? _MoreButton(device: d, onMore: actions.onMore, size: 28),
              ]),
              const SizedBox(height: 12),
              FsText(d.label,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: FsType.sans(14.5, FontWeight.w700, em: -0.01, color: t.ink)),
              if (d.user.isNotEmpty)
                FsText(d.user,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: FsType.sans(12, FontWeight.w400, color: t.muted)),
              const Spacer(),
              Row(children: [
                Expanded(
                  child: FsText(fsFormatId(d.id),
                      maxLines: 1, softWrap: false, overflow: TextOverflow.fade, style: FsType.mono(12.5, FontWeight.w400, color: t.ink)),
                ),
                AnimatedSwitcher(
                  duration: FsMotion.quick,
                  child: reveal && canGo
                      ? FsIconButton(
                          key: const ValueKey('go'),
                          icon: d.online ? Icons.arrow_forward_rounded : Icons.cloud_off_rounded,
                          tooltip: d.online ? FsStrings.control : FsStrings.offline,
                          size: 28,
                          on: d.online,
                          onPressed: () => actions.onConnect!(d),
                        )
                      : SizedBox(
                          key: const ValueKey('os'),
                          height: 28,
                          child: Center(
                            child: Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: FsText(d.lastSession, maxLines: 1, style: FsType.sans(12, FontWeight.w400, color: t.muted)),
                            ),
                          ),
                        ),
                ),
              ]),
            ]),
          ),
        );
      },
    );
  }
}

/// Tuile compacte d'appareil (220 × 42) : tuile système, nom, identifiant.
class FsDeviceTile extends StatelessWidget {
  const FsDeviceTile({
    super.key,
    required this.device,
    this.selected = false,
    this.actions = const FsDeviceActions(),
    this.allowOffline = false,
    this.leading,
  });

  final FsDevice device;
  final bool selected;
  final FsDeviceActions actions;
  final bool allowOffline;

  /// Remplace le bouton « Plus » (case de multi-sélection, par exemple).
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final t = FsTokens.of(context);
    final d = device;
    final canGo = (d.online || allowOffline) && actions.onConnect != null;
    return FsHover(
      cursor: SystemMouseCursors.basic,
      onTap: actions.onSelect == null ? null : () => actions.onSelect!(d),
      onDoubleTap: canGo ? () => actions.onConnect!(d) : null,
      onSecondaryTapDown: actions.onMore == null ? null : (e) => actions.onMore!(d, e.globalPosition),
      builder: (context, hover, _) => _Frame(
        hover: hover,
        selected: selected,
        child: Row(children: [
          const SizedBox(width: 8),
          FsOsTile(os: d.os, online: d.online, size: 26),
          const SizedBox(width: 12),
          Expanded(
            child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
              FsText(d.label,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: FsType.sans(13, FontWeight.w600, color: t.ink)),
              FsText(fsFormatId(d.id),
                  maxLines: 1, softWrap: false, overflow: TextOverflow.fade, style: FsType.mono(11, FontWeight.w400, color: t.muted)),
            ]),
          ),
          leading ?? _MoreButton(device: d, onMore: actions.onMore, size: 28),
          const SizedBox(width: 4),
        ]),
      ),
    );
  }
}
