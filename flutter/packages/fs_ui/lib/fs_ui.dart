/// Habillage « A · Atelier » de FS Support : thème, typographie et widgets de présentation.
///
/// Paquet pur : aucune dépendance au moteur RustDesk (`gFFI`, `bind`). Les écrans reçoivent
/// leurs données et leurs rappels en paramètres ; le client les branche dans `flutter/lib/fs/`.
library fs_ui;

export 'src/models.dart';
export 'src/strings.dart';
export 'src/svg_path.dart';
export 'src/theme.dart';
export 'src/tokens.dart';
export 'src/typography.dart';
export 'src/widgets/android.dart';
export 'src/widgets/cards.dart';
export 'src/widgets/devices.dart';
export 'src/widgets/home.dart';
export 'src/widgets/install.dart';
export 'src/widgets/primitives.dart';
export 'src/widgets/rail.dart';
export 'src/widgets/session.dart';
