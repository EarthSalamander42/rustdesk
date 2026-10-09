// Bandeau d'installation de l'accueil (Windows) : installer FS Support sur le poste, mettre à jour une
// installation plus ancienne, ou rappeler qu'une version installée existe. Posé en tête de la colonne
// principale, au-dessus du champ de connexion, là où il ne peut pas passer inaperçu (les cartes
// d'aide de RustDesk, dans le rail, finissaient écrasées sous la navigation).
import 'package:flutter/material.dart';

import '../strings.dart';
import '../tokens.dart';
import '../typography.dart';
import 'primitives.dart';

class FsInstallBanner extends StatelessWidget {
  const FsInstallBanner({
    super.key,
    required this.title,
    required this.text,
    this.icon = Icons.install_desktop_rounded,
    this.eyebrow = FsStrings.installEyebrow,
    this.action,
    this.actionIcon,
    this.onAction,
    this.note,
  });

  final String title;
  final String text;
  final IconData icon;
  final String eyebrow;

  /// Bouton principal, plein et large (« Installer FS Support sur ce poste »…).
  final String? action;
  final IconData? actionIcon;
  final VoidCallback? onAction;

  /// Précision sous les boutons (autorisation Windows, suite de l'opération).
  final String? note;

  /// En dessous de cette largeur, les boutons passent sous le texte.
  static const double _wide = 720;

  @override
  Widget build(BuildContext context) {
    final t = FsTokens.of(context);
    final texts = Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      FsEyebrow(eyebrow),
      const SizedBox(height: 6),
      FsText(title, style: FsType.sans(20, FontWeight.w800, em: -0.03, color: t.ink)),
      const SizedBox(height: 4),
      FsText(text, style: FsType.sans(13, FontWeight.w400, color: t.muted)),
    ]);
    final buttons = <Widget>[
      if (action != null)
        FsButton(
          label: action!,
          leading: actionIcon,
          onPressed: onAction,
          height: 52,
          fontSize: 16,
          iconSize: 20,
          hPadding: 24,
        ),
    ];
    final mark = Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Icon(icon, size: 30, color: t.acc),
    );
    return AnimatedContainer(
      duration: FsMotion.theme,
      margin: const EdgeInsets.only(bottom: 22),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      decoration: BoxDecoration(
        color: t.bg2,
        border: Border(
          top: BorderSide(color: t.acc, width: 2),
          left: BorderSide(color: t.line),
          right: BorderSide(color: t.line),
          bottom: BorderSide(color: t.line),
        ),
      ),
      child: LayoutBuilder(builder: (context, c) {
        final wide = c.maxWidth >= _wide;
        final row = Row(crossAxisAlignment: wide ? CrossAxisAlignment.center : CrossAxisAlignment.start, children: [
          mark,
          const SizedBox(width: 16),
          Expanded(child: texts),
          if (wide && buttons.isNotEmpty) ...[
            const SizedBox(width: 20),
            Row(mainAxisSize: MainAxisSize.min, children: [
              for (var i = 0; i < buttons.length; i++) ...[
                if (i > 0) const SizedBox(width: 10),
                buttons[i],
              ],
            ]),
          ],
        ]);
        // Étroit : boutons et précision sur toute la largeur, sous le texte.
        final indent = EdgeInsets.only(left: wide ? 30 + 16 : 0);
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          row,
          if (!wide && buttons.isNotEmpty) ...[
            const SizedBox(height: 14),
            Wrap(spacing: 10, runSpacing: 8, children: buttons),
          ],
          if (note != null) ...[
            const SizedBox(height: 10),
            Padding(
              padding: indent,
              child: FsText(note!, style: FsType.sans(12, FontWeight.w400, color: t.muted)),
            ),
          ],
        ]);
      }),
    );
  }
}
