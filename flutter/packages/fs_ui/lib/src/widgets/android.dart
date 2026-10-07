// Écran Android « Partager mon écran » de l'Atelier (`.A-ph`) : barre d'appli, code, partage,
// autorisations, crédit, barre de navigation du bas. Données et rappels fournis par le client.
import 'package:flutter/material.dart';

import '../strings.dart';
import '../tokens.dart';
import '../typography.dart';
import 'primitives.dart';
import 'rail.dart';

/// Barre d'appli (`.A-ph-app`) : 56 px, monogramme 28 px, « FS Support », actions.
class FsMobileAppBar extends StatelessWidget implements PreferredSizeWidget {
  const FsMobileAppBar({super.key, this.title = FsStrings.appName, this.actions = const []});
  final String title;
  final List<Widget> actions;

  @override
  Size get preferredSize => const Size.fromHeight(56);

  @override
  Widget build(BuildContext context) {
    final t = FsTokens.of(context);
    return AnimatedContainer(
      duration: FsMotion.theme,
      height: 56,
      padding: const EdgeInsets.only(left: 22, right: 18),
      decoration: BoxDecoration(color: t.bg, border: Border(bottom: BorderSide(color: t.line))),
      child: Row(children: [
        const FsMark(size: 28),
        const SizedBox(width: 10),
        Expanded(child: FsText(title, style: FsType.sans(18, FontWeight.w800, em: -0.03, color: t.ink))),
        if (actions.isEmpty) Icon(Icons.more_vert_rounded, size: 20, color: t.muted) else ...actions,
      ]),
    );
  }
}

/// Une autorisation Android (`.A-ph-perms li`).
@immutable
class FsPermission {
  const FsPermission({required this.icon, required this.label, required this.value, this.warning, this.onChanged});
  final IconData icon;
  final String label;
  final bool value;

  /// Rappel en rouge sous le libellé tant que l'autorisation manque (« Accessibilité à activer »).
  final String? warning;
  final ValueChanged<bool>? onChanged;
}

/// Corps de l'écran de partage (sans barre d'appli ni navigation).
class FsShareBody extends StatelessWidget {
  const FsShareBody({
    super.key,
    required this.id,
    required this.password,
    required this.running,
    required this.permissions,
    required this.version,
    this.onToggle,
    this.onRefresh,
    this.onCopyId,
    this.onCredit,
    this.connections,
    this.bottomPadding = 18,
  });

  final String id;
  final String password;

  /// Service de partage démarré.
  final bool running;
  final List<FsPermission> permissions;
  final String version;
  final VoidCallback? onToggle;
  final VoidCallback? onRefresh;
  final VoidCallback? onCopyId;
  final VoidCallback? onCredit;

  /// Liste des connexions en cours (gestionnaire RustDesk), posée sous le bouton.
  final Widget? connections;
  final double bottomPadding;

  @override
  Widget build(BuildContext context) {
    final t = FsTokens.of(context);
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(22, 22, 22, bottomPadding),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const FsEyebrow(FsStrings.shareMyScreen),
          const SizedBox(height: 6),
          FsText(FsStrings.giveCode, style: FsType.sans(27, FontWeight.w800, height: 1.05, em: -0.045, color: t.ink)),
          const SizedBox(height: 18),
          AnimatedContainer(
            duration: FsMotion.theme,
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(border: Border(top: BorderSide(color: t.ink, width: 2), bottom: BorderSide(color: t.line))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const FsEyebrow(FsStrings.yourCode),
              const SizedBox(height: 2),
              GestureDetector(
                onLongPress: onCopyId,
                onDoubleTap: onCopyId,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: FsText(id, style: FsType.display(44, height: 1.12, color: t.ink)),
                ),
              ),
              const SizedBox(height: 8),
              Row(children: [
                const FsEyebrow(FsStrings.password, strut: null),
                const SizedBox(width: 12),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: FsMotion.fade,
                    layoutBuilder: (cur, prev) => Stack(alignment: Alignment.centerLeft, children: [...prev, if (cur != null) cur]),
                    child: FsText(password, key: ValueKey(password), style: FsType.mono(19, FontWeight.w600, em: 0.14, color: t.ink)),
                  ),
                ),
                const SizedBox(width: 12),
                if (onRefresh != null)
                  GestureDetector(onTap: onRefresh, child: Icon(Icons.refresh_rounded, size: 20, color: t.muted)),
              ]),
            ]),
          ),
          const SizedBox(height: 18),
          FsShareButton(running: running, onPressed: onToggle),
          Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 20),
            child: SizedBox(
              height: 20,
              child: Row(children: [
                FsPulseDot(color: running ? t.on : t.off, live: running),
                const SizedBox(width: 8),
                AnimatedSwitcher(
                  duration: FsMotion.fade,
                  child: FsText(running ? FsStrings.sharingLive : FsStrings.sharingStopped,
                      key: ValueKey(running), style: FsType.sans(13, FontWeight.w400, color: t.muted)),
                ),
              ]),
            ),
          ),
          if (connections != null) ...[connections!, const SizedBox(height: 20)],
          const FsEyebrow(FsStrings.permissions),
          const SizedBox(height: 6),
          AnimatedContainer(
            duration: FsMotion.theme,
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: t.line))),
            child: Column(children: [for (final p in permissions) _PermRow(p: p)]),
          ),
          const SizedBox(height: 18),
          FsCredit(version: version, onTap: onCredit, oneLine: true, center: true),
        ]),
      ),
    );
  }
}

/// Grand bouton « Démarrer / Arrêter le partage » (`.A-ph-start`) : olive puis encre.
class FsShareButton extends StatelessWidget {
  const FsShareButton({super.key, required this.running, this.onPressed});
  final bool running;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final t = FsTokens.of(context);
    final bg = running ? t.ink : t.acc;
    final fg = running ? t.bg : t.accFg;
    return GestureDetector(
      onTap: onPressed,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 400),
        curve: FsMotion.cssEase,
        height: 56,
        color: bg,
        child: AnimatedSwitcher(
          duration: FsMotion.fade,
          child: Row(
            key: ValueKey(running),
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(running ? Icons.stop_rounded : Icons.play_arrow_rounded, size: 20, color: fg),
              const SizedBox(width: 10),
              FsText(running ? FsStrings.stopSharing : FsStrings.startSharing, style: FsType.sans(16, FontWeight.w700, color: fg)),
            ],
          ),
        ),
      ),
    );
  }
}

class _PermRow extends StatelessWidget {
  const _PermRow({required this.p});
  final FsPermission p;

  @override
  Widget build(BuildContext context) {
    final t = FsTokens.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: p.onChanged == null ? null : () => p.onChanged!(!p.value),
      child: AnimatedContainer(
        duration: FsMotion.theme,
        constraints: const BoxConstraints(minHeight: 54),
        decoration: BoxDecoration(border: Border(top: BorderSide(color: t.line))),
        child: Row(children: [
          Icon(p.icon, size: 21, color: t.muted),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              FsText(p.label, style: FsType.sans(15, FontWeight.w600, color: t.ink)),
              if (p.warning != null)
                AnimatedOpacity(
                  opacity: p.value ? 0 : 1,
                  duration: FsMotion.fade,
                  child: FsText(p.warning!, style: FsType.sans(12, FontWeight.w500, color: t.danger)),
                ),
            ]),
          ),
          const SizedBox(width: 12),
          FsToggle(value: p.value, onChanged: p.onChanged),
        ]),
      ),
    );
  }
}

/// Entrée de la barre de navigation du bas.
@immutable
class FsBottomItem {
  const FsBottomItem(this.icon, this.label);
  final IconData icon;
  final String label;
}

/// Barre de navigation du bas (`.A-ph-nav`) : filet, indicateur d'accent coulissant.
class FsBottomNav extends StatelessWidget {
  const FsBottomNav({super.key, required this.items, required this.index, this.onTap, this.bottomInset = 12});
  final List<FsBottomItem> items;
  final int index;
  final ValueChanged<int>? onTap;
  final double bottomInset;

  @override
  Widget build(BuildContext context) {
    final t = FsTokens.of(context);
    return AnimatedContainer(
      duration: FsMotion.theme,
      height: 60 + bottomInset,
      padding: EdgeInsets.only(bottom: bottomInset),
      decoration: BoxDecoration(color: t.bg, border: Border(top: BorderSide(color: t.line))),
      child: LayoutBuilder(builder: (context, c) {
        final w = c.maxWidth / items.length;
        return Stack(clipBehavior: Clip.none, children: [
          Row(children: [
            for (var i = 0; i < items.length; i++)
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onTap == null ? null : () => onTap!(i),
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(end: i == index ? 1 : 0),
                    duration: FsMotion.quick,
                    builder: (context, v, _) => Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(items[i].icon, size: 20, color: Color.lerp(t.muted, t.acc, v)),
                      const SizedBox(height: 2),
                      FsText(items[i].label, style: FsType.sans(12, FontWeight.w600, color: Color.lerp(t.muted, t.ink, v))),
                    ]),
                  ),
                ),
              ),
          ]),
          AnimatedPositioned(
            duration: FsMotion.accordion,
            curve: FsMotion.ease,
            top: -1,
            left: w * index,
            width: w,
            height: 2,
            child: AnimatedContainer(duration: FsMotion.theme, color: t.acc),
          ),
        ]);
      }),
    );
  }
}
