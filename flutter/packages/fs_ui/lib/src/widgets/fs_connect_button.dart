// Bouton « Continuer avec FS Connect » (15/10/2026) : le même que sur la page de connexion du SaaS
// (app.fs-solutions.fr/login, `views/auth/signin/Basic.vue`, classe `.fs-identity-button`).
//
// Repris du CSS du SaaS : pleine largeur, 46 px de haut au moins, coins arrondis (0,65 rem ≈ 10 px), fond clair,
// filet fin (olive à 28 %), petit carré sombre de 28 px (rayon 8) à gauche avec le monogramme, 12 px d'écart,
// texte encre. Survol / focus : filet plus marqué, ombre douce `0 8px 24px` et levée de 1 px, en 160 ms.
// Désactivé : opacité 0,65. Mode sombre : le CSS sombre du SaaS met un texte olive foncé sur fond ardoise
// (contraste insuffisant) ; ici on suit les jetons Atelier / Ardoise : fond relevé, texte encre claire, carré à
// l'accent (lime / sauge) et lettres sombres, comme le monogramme lime de la charte.
//
// Le « FS » écrit du SaaS devient le monogramme officiel : `assets/brand/mark-glyphes.png`, les lettres seules
// tirées de `mark-paper.png` (outil `tool/generer-glyphes-monogramme.cjs`), teintées à la couleur voulue.
//
// États : chargement (cercle dans le carré, « Connexion en cours… », lien « Annuler » sous le bouton), erreur
// (encadré sous le bouton, le bouton sert à réessayer), désactivé. Focus clavier visible (anneau de 3 px,
// repris de `.fs-identity-button.is-required`), Entrée / Espace activent. Mouvements coupés si le système
// demande de réduire les animations.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../strings.dart';
import '../tokens.dart';
import '../typography.dart';

/// Couleurs du bouton pour un jeu de jetons (fonction pure : testée pour le contraste AA).
@immutable
class FsConnectColors {
  const FsConnectColors({
    required this.background,
    required this.border,
    required this.borderHover,
    required this.label,
    required this.tile,
    required this.glyph,
    required this.ring,
    required this.shadow,
    required this.link,
    required this.linkHover,
    required this.errorBackground,
    required this.errorBorder,
    required this.errorAccent,
    required this.errorText,
    required this.errorDetail,
  });

  /// Fond du bouton (`#f7f8f3` au SaaS) : champ clair en clair, surface relevée en sombre.
  final Color background;

  /// Filet au repos (`rgba(67, 73, 52, .28)`).
  final Color border;

  /// Filet au survol et au focus (`--fs-auth-khaki-soft`) ; plein accent au focus clavier.
  final Color borderHover;

  /// Texte du bouton : encre.
  final Color label;

  /// Petit carré du monogramme (`--fs-auth-khaki`).
  final Color tile;

  /// Lettres du monogramme sur le carré.
  final Color glyph;

  /// Anneau de focus (`0 0 0 3px rgba(58, 66, 45, .35)`).
  final Color ring;

  /// Ombre du survol (`0 8px 24px rgba(46, 52, 36, .14)`).
  final Color shadow;

  /// Lien « Annuler ».
  final Color link;
  final Color linkHover;

  /// Encadré d'erreur (`.fs-login-error` du SaaS, aux couleurs des jetons).
  final Color errorBackground;
  final Color errorBorder;
  final Color errorAccent;
  final Color errorText;
  final Color errorDetail;

  factory FsConnectColors.of(FsTokens t) {
    final dark = t.isDark;
    // Fond de l'encadré d'erreur : le rouge des jetons à 9 % sur le papier.
    final errorBg = Color.alphaBlend(t.danger.withOpacity(dark ? 0.14 : 0.09), t.bg);
    return FsConnectColors(
      background: dark ? t.bg2 : t.field,
      border: dark ? t.line : t.acc.withOpacity(0.28),
      borderHover: t.muted,
      label: t.ink,
      tile: t.acc,
      glyph: t.accFg,
      ring: t.acc.withOpacity(dark ? 0.45 : 0.35),
      shadow: dark ? const Color.fromRGBO(0, 0, 0, 0.45) : const Color.fromRGBO(46, 52, 36, 0.14),
      link: t.muted,
      linkHover: t.ink,
      errorBackground: errorBg,
      errorBorder: t.danger.withOpacity(dark ? 0.45 : 0.32),
      errorAccent: t.danger,
      errorText: t.ink,
      errorDetail: t.muted,
    );
  }
}

/// Dimensions reprises du CSS du SaaS.
class FsConnectDims {
  FsConnectDims._();
  static const double minHeight = 46;
  static const double radius = 10;
  static const double tile = 28;
  static const double tileRadius = 8;
  static const double glyph = 18;
  static const double gap = 12;
  static const double fontSize = 15;
  static const Duration hover = Duration(milliseconds: 160);
}

/// Bouton « Continuer avec FS Connect ». À poser dans un parent de largeur bornée (il prend toute la largeur).
class FsConnectButton extends StatefulWidget {
  const FsConnectButton({
    super.key,
    this.onPressed,
    this.onCancel,
    this.loading = false,
    this.error,
    this.errorDetail,
    this.label = FsStrings.fsConnectContinue,
    this.loadingLabel = FsStrings.fsConnectInProgress,
    this.autofocus = false,
    this.forceHover = false,
    this.forceFocus = false,
  });

  /// Démarre la connexion ; `null` = désactivé.
  final VoidCallback? onPressed;

  /// Annule la connexion en cours ; affiche le lien « Annuler » pendant le chargement.
  final VoidCallback? onCancel;

  /// Connexion en cours : cercle dans le carré, libellé [loadingLabel], bouton inerte.
  final bool loading;

  /// Message d'erreur (encadré sous le bouton) ; le bouton reste actif pour réessayer.
  final String? error;

  /// Détail technique facultatif, en petit sous le message.
  final String? errorDetail;

  final String label;
  final String loadingLabel;
  final bool autofocus;

  /// Captures et banc d'essai : état survolé / focus clavier forcé.
  final bool forceHover;
  final bool forceFocus;

  @override
  State<FsConnectButton> createState() => _FsConnectButtonState();
}

class _FsConnectButtonState extends State<FsConnectButton> {
  bool _hover = false;
  bool _focus = false;
  bool _down = false;

  bool get _enabled => widget.onPressed != null && !widget.loading;

  void _activate() {
    if (!_enabled) return;
    widget.onPressed!.call();
  }

  @override
  void didUpdateWidget(covariant FsConnectButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_enabled) _down = false;
  }

  @override
  Widget build(BuildContext context) {
    final t = FsTokens.of(context);
    final c = FsConnectColors.of(t);
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    Duration d(Duration x) => still ? Duration.zero : x;

    final hover = _enabled && (_hover || widget.forceHover);
    final focus = _enabled && (_focus || widget.forceFocus);
    final lifted = (hover || focus) && !_down;
    final label = widget.loading ? widget.loadingLabel : widget.label;

    final shadows = <BoxShadow>[
      BoxShadow(
        color: lifted ? c.shadow : c.shadow.withOpacity(0),
        blurRadius: 24,
        offset: const Offset(0, 8),
      ),
      // Anneau de focus clavier (3 px, sans flou).
      BoxShadow(color: focus ? c.ring : c.ring.withOpacity(0), spreadRadius: 3),
    ];

    final tile = AnimatedContainer(
      duration: d(FsMotion.theme),
      curve: FsMotion.cssEase,
      width: FsConnectDims.tile,
      height: FsConnectDims.tile,
      decoration: BoxDecoration(
        color: c.tile,
        borderRadius: BorderRadius.circular(FsConnectDims.tileRadius),
      ),
      alignment: Alignment.center,
      child: AnimatedSwitcher(
        duration: d(FsMotion.fade),
        switchInCurve: FsMotion.ease,
        switchOutCurve: FsMotion.ease,
        transitionBuilder: (child, anim) => FadeTransition(
          opacity: anim,
          child: ScaleTransition(scale: Tween(begin: 0.6, end: 1.0).animate(anim), child: child),
        ),
        child: widget.loading
            ? SizedBox(
                key: const ValueKey('chargement'),
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2, color: c.glyph),
              )
            : FsConnectMonogram(key: const ValueKey('monogramme'), size: FsConnectDims.glyph, color: c.glyph),
      ),
    );

    final face = AnimatedContainer(
      duration: d(FsConnectDims.hover),
      curve: FsMotion.cssEase,
      constraints: const BoxConstraints(minHeight: FsConnectDims.minHeight),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      transform: Matrix4.translationValues(0, lifted ? -1 : 0, 0),
      decoration: BoxDecoration(
        color: c.background,
        borderRadius: BorderRadius.circular(FsConnectDims.radius),
        border: Border.all(color: focus ? t.acc : (hover ? c.borderHover : c.border)),
        boxShadow: shadows,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          tile,
          const SizedBox(width: FsConnectDims.gap),
          Flexible(
            child: AnimatedSwitcher(
              duration: d(FsMotion.fade),
              switchInCurve: FsMotion.ease,
              switchOutCurve: FsMotion.ease,
              layoutBuilder: (current, previous) => Stack(
                alignment: Alignment.centerLeft,
                children: [...previous, if (current != null) current],
              ),
              child: FsText(
                label,
                key: ValueKey(label),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                softWrap: true,
                style: FsType.sans(FsConnectDims.fontSize, FontWeight.w600, color: c.label),
              ),
            ),
          ),
        ],
      ),
    );

    final button = Semantics(
      container: true,
      button: true,
      enabled: _enabled,
      label: label,
      liveRegion: widget.loading,
      onTap: _enabled ? _activate : null,
      child: ExcludeSemantics(
        child: FocusableActionDetector(
          enabled: _enabled,
          autofocus: widget.autofocus,
          mouseCursor: _enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
          onShowFocusHighlight: (v) => setState(() => _focus = v),
          onShowHoverHighlight: (v) => setState(() {
            _hover = v;
            if (!v) _down = false;
          }),
          shortcuts: const {
            SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
            SingleActivator(LogicalKeyboardKey.numpadEnter): ActivateIntent(),
            SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
          },
          actions: {ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) => _activate())},
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _enabled ? _activate : null,
            onTapDown: _enabled ? (_) => setState(() => _down = true) : null,
            onTapUp: _enabled ? (_) => setState(() => _down = false) : null,
            onTapCancel: _enabled ? () => setState(() => _down = false) : null,
            child: AnimatedOpacity(
              duration: d(FsConnectDims.hover),
              opacity: widget.onPressed == null && !widget.loading ? 0.65 : 1,
              child: AnimatedScale(
                duration: d(const Duration(milliseconds: 120)),
                curve: FsMotion.cssEase,
                scale: _down ? 0.985 : 1,
                child: face,
              ),
            ),
          ),
        ),
      ),
    );

    final error = (widget.error ?? '').trim();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        button,
        AnimatedSize(
          duration: d(FsMotion.slide),
          curve: FsMotion.ease,
          alignment: Alignment.topCenter,
          child: widget.loading && widget.onCancel != null
              ? Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Center(child: _CancelLink(onPressed: widget.onCancel!, colors: c)),
                )
              : const SizedBox(width: double.infinity),
        ),
        AnimatedSize(
          duration: d(FsMotion.slide),
          curve: FsMotion.ease,
          alignment: Alignment.topCenter,
          child: AnimatedSwitcher(
            duration: d(FsMotion.fade),
            child: error.isEmpty || widget.loading
                ? const SizedBox(key: ValueKey('sans-erreur'), width: double.infinity)
                : Padding(
                    key: ValueKey('erreur-$error'),
                    padding: const EdgeInsets.only(top: 10),
                    child: FsConnectError(message: error, detail: widget.errorDetail, colors: c),
                  ),
          ),
        ),
      ],
    );
  }
}

/// Lettres « fs » du monogramme officiel, teintées (fondu enchaîné au changement de thème).
class FsConnectMonogram extends StatelessWidget {
  const FsConnectMonogram({super.key, required this.size, required this.color});
  final double size;
  final Color color;

  /// Clé de l'image dans le paquet.
  static const String asset = 'assets/brand/mark-glyphes.png';

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<Color?>(
      tween: ColorTween(end: color),
      duration: FsMotion.theme,
      builder: (context, c, _) => Image.asset(
        asset,
        package: FsType.package,
        // Échelle fixe : une seule résolution, pas de lecture du manifeste des ressources.
        scale: 1,
        width: size,
        height: size,
        color: c,
        colorBlendMode: BlendMode.srcIn,
        filterQuality: FilterQuality.medium,
        isAntiAlias: true,
        gaplessPlayback: true,
        excludeFromSemantics: true,
      ),
    );
  }
}

/// Encadré d'erreur sous le bouton (`.fs-login-error` du SaaS) : filet gauche de 3 px, pictogramme, message.
class FsConnectError extends StatelessWidget {
  const FsConnectError({super.key, required this.message, this.detail, required this.colors});
  final String message;
  final String? detail;
  final FsConnectColors colors;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    final det = (detail ?? '').trim();
    return Semantics(
      liveRegion: true,
      container: true,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: c.errorBackground,
            border: Border.all(color: c.errorBorder),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Stack(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  width: 22,
                  height: 22,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: c.errorAccent.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Icon(Icons.error_outline_rounded, size: 15, color: c.errorAccent),
                ),
                const SizedBox(width: 9),
                Flexible(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: FsText(message, style: FsType.sans(13, FontWeight.w600, height: 1.35, color: c.errorText)),
                    ),
                    if (det.isNotEmpty && det != message)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: SelectableText(det, style: FsType.sans(11.5, FontWeight.w400, color: c.errorDetail)),
                      ),
                  ]),
                ),
              ]),
            ),
            Positioned(left: 0, top: 0, bottom: 0, width: 3, child: ColoredBox(color: c.errorAccent)),
          ]),
        ),
      ),
    );
  }
}

/// Lien « Annuler » sous le bouton pendant la connexion : focusable, souligné au survol et au focus.
class _CancelLink extends StatefulWidget {
  const _CancelLink({required this.onPressed, required this.colors});
  final VoidCallback onPressed;
  final FsConnectColors colors;

  @override
  State<_CancelLink> createState() => _CancelLinkState();
}

class _CancelLinkState extends State<_CancelLink> {
  bool _hover = false;
  bool _focus = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.colors;
    final t = FsTokens.of(context);
    final on = _hover || _focus;
    return Semantics(
      button: true,
      label: FsStrings.fsConnectCancel,
      onTap: widget.onPressed,
      child: ExcludeSemantics(
        child: FocusableActionDetector(
          mouseCursor: SystemMouseCursors.click,
          onShowFocusHighlight: (v) => setState(() => _focus = v),
          onShowHoverHighlight: (v) => setState(() => _hover = v),
          actions: {ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) => widget.onPressed())},
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onPressed,
            child: AnimatedContainer(
              duration: FsConnectDims.hover,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: _focus ? t.acc : t.acc.withOpacity(0), width: 1.5),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.close_rounded, size: 15, color: on ? c.linkHover : c.link),
                const SizedBox(width: 5),
                Text(
                  FsStrings.fsConnectCancel,
                  textScaler: TextScaler.noScaling,
                  style: FsType.sans(13, FontWeight.w600, color: on ? c.linkHover : c.link).copyWith(
                    decoration: on ? TextDecoration.underline : TextDecoration.none,
                    decorationColor: on ? c.linkHover : c.link,
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// Rapport de contraste WCAG entre deux couleurs opaques (1 à 21).
double fsContrastRatio(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}
