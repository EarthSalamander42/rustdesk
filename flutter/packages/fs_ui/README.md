# fs_ui — habillage « A · Atelier » de FS Support

Paquet Flutter local, sans dépendance au moteur RustDesk : jetons (`FsTokens`), thème Material
(`fsAtelierTheme`), typographie embarquée (Inter, Archivo Black, JetBrains Mono — licence OFL,
voir `assets/fonts/OFL-*.txt`) et widgets de présentation (rail, bloc « Votre poste », champ de
connexion, liste filetée par entreprise, barre d'état, barre de session, écran Android de partage,
emplacements « Bientôt »).

Le client l'utilise par `path: packages/fs_ui` ; les adaptateurs de `flutter/lib/fs/` branchent les
vraies données. Le banc d'essai web (hors dépôt) compare chaque écran à la maquette
`fs-support-branding/direction-a-atelier.html`.
