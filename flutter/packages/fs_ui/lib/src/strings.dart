// Libellés propres à FS Support (français seul). Volontairement hors de `src/lang/fr.rs`
// pour ne pas multiplier les conflits avec l'amont RustDesk.
class FsStrings {
  FsStrings._();

  static const String appName = 'FS Support';
  static const String byline = 'par FS Solutions';
  static const String poweredBy = 'Technologie RustDesk';
  static const String license = 'AGPL-3.0';
  static const String sourceUrl = 'https://github.com/EarthSalamander42/rustdesk';

  // Accueil
  static const String yourDevice = 'Votre poste';
  static const String oneTimePassword = 'Mot de passe à usage unique';
  static const String permanentPassword = 'Mot de passe permanent';
  static const String copyId = 'Copier l’ID';
  static const String idCopied = 'ID copié dans le presse-papiers';
  static const String passwordCopied = 'Mot de passe copié';
  static const String newPassword = 'Nouveau mot de passe';
  static const String edit = 'Modifier';
  static const String devices = 'Appareils';
  static const String recent = 'Récents';
  static const String favorites = 'Favoris';
  static const String addressBook = 'Carnet d’adresses';
  static const String discovered = 'Découverts';
  static const String accessible = 'Appareils accessibles';
  static const String plannedSlots = 'Emplacements prévus';
  static const String ticketsFs = 'Tickets FS';
  static const String interventions = 'Interventions';
  static const String soon = 'Bientôt';
  static const String settings = 'Paramètres';
  static const String remoteControl = 'Contrôler un poste à distance';
  static const String idHint = 'ID ou nom de l’appareil — ex. 148 290 731';
  static const String connect = 'Se connecter';
  static const String files = 'Fichiers';
  static const String fileTransfer = 'Transfert de fichiers';
  static const String byCompany = 'Par entreprise';
  static const String list = 'Liste';
  static const String cards = 'Cartes';
  static const String sort = 'Trier';
  static const String colDevice = 'Appareil';
  static const String colId = 'ID';
  static const String colLast = 'Dernière session';
  static const String control = 'Contrôler';
  static const String offline = 'Hors ligne';
  static const String more = 'Plus';
  static const String noneOnline = 'Aucun en ligne';
  static String nOnline(int n) => '$n en ligne';
  static String nDevices(int n) => '$n appareil${n > 1 ? 's' : ''}';
  static String devicesSummary(int total, int online) => '${nDevices(total)} · ${nOnline(online)}';
  static const String recentSub = 'Sessions récentes de ce poste';
  static const String favSub = 'Épinglés à la main';
  static const String lanSub = 'Réseau local';
  static const String slotSub = 'Emplacement prévu';
  static const String ready = 'Prêt';
  static const String connecting = 'Connexion…';
  static const String notReady = 'Hors service';
  static const String serverFs = 'Serveur FS Solutions';
  static const String startService = 'Démarrer le service';

  // Emplacements prévus
  static const String slotEyebrow = 'Emplacement prévu · rien n’est branché';
  static const String ticketsTitle = 'Les demandes de support du SaaS FS, ici.';
  static const String ticketsText =
      'La page existe déjà dans la navigation ; son contenu viendra plus tard de FS Full Flux. Aucun fonctionnement n’est décidé à ce stade.';
  static const String historyTitle = 'Historique d’interventions et notes par appareil.';
  static const String historyText =
      'Réservé pour l’historique des sessions par client et les notes de poste. Le contenu et sa source restent à décider.';

  // Vides
  static const String abTitle = 'Connectez-vous au serveur FS.';
  static const String abText =
      'Le carnet d’adresses partagé est une fonction RustDesk existante : il s’affiche dès qu’un compte est connecté au serveur d’API.';
  static const String lanTitle = 'Aucun appareil trouvé sur ce réseau.';
  static const String lanText = 'La découverte locale reste celle de RustDesk : seul son habillage change.';
  static const String relaunch = 'Relancer la recherche';
  static const String emptyTitle = 'Aucun appareil pour l’instant.';
  static const String emptyText = 'Saisissez un ID ci-dessus pour ouvrir une première session.';

  // Session
  static const String pinToolbar = 'Épingler la barre';
  static const String end = 'Terminer';
  static const String notes = 'Notes';

  // Android
  static const String shareMyScreen = 'Partager mon écran';
  static const String giveCode = 'Donnez ce code à votre technicien FS.';
  static const String yourCode = 'Votre code';
  static const String password = 'Mot de passe';
  static const String startSharing = 'Démarrer le partage';
  static const String stopSharing = 'Arrêter le partage';
  static const String sharingStopped = 'Partage arrêté';
  static const String sharingLive = 'Partage actif — en attente du technicien';
  static const String permissions = 'Autorisations';
  static const String screenCapture = 'Capture de l’écran';
  static const String remoteInput = 'Contrôle à distance';
  static const String accessibilityTodo = 'Accessibilité à activer';
  static const String audio = 'Son';
  static const String clipboard = 'Presse-papiers';
  static const String share = 'Partager';
  static const String connectTab = 'Se connecter';
  static const String settingsTab = 'Réglages';

  // Gestionnaire de connexions
  static const String waiting = 'En attente d’une connexion…';
  static const String technician = 'Technicien FS';
}
