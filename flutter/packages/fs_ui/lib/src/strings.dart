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
  static const String scrollUp = 'Faire défiler vers le haut';
  static const String scrollDown = 'Faire défiler vers le bas';
  static const String remoteControl = 'Contrôler un poste à distance';
  static const String idHint = 'ID ou nom de l’appareil — ex. 148 290 731';
  static const String connect = 'Se connecter';
  static const String files = 'Fichiers';
  static const String fileTransfer = 'Transfert de fichiers';
  static const String byCompany = 'Par entreprise';
  static const String list = 'Liste';
  static const String cards = 'Cartes';
  static const String tiles = 'Tuiles compactes';
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

  // Installation (Windows) : bandeau en tête de l'accueil
  static const String installEyebrow = 'Installation';
  static const String installTitle = 'FS Support n’est pas installé sur ce poste.';
  static const String installText =
      'Cette copie s’arrête dès qu’on la ferme et ne peut pas agir sur les fenêtres d’administration de Windows (UAC). Installez FS Support pour un dépannage complet.';
  static const String installButton = 'Installer FS Support sur ce poste';
  static const String upgradeTitle = 'Une version plus ancienne de FS Support est installée sur ce poste.';
  static const String upgradeText =
      'Le service installé n’accepte pas cette copie téléchargée (état « Hors service », mot de passe indisponible). Mettez l’installation à jour avec cette version.';
  static const String upgradeButton = 'Mettre à jour l’installation';
  static const String installedTitle = 'FS Support est déjà installé sur ce poste.';
  static const String installedText =
      'Cette copie téléchargée ne peut pas utiliser le service installé (état « Hors service », mot de passe indisponible). Fermez-la, puis ouvrez FS Support depuis le menu Démarrer.';
  static const String closeCopy = 'Fermer cette copie';
  static const String installNote =
      'Windows demande une autorisation. FS Support s’ouvre ensuite depuis son installation et cette copie se ferme ; sinon, ouvrez FS Support depuis le menu Démarrer.';

  // Emplacements prévus
  static const String slotEyebrow = 'Emplacement prévu · rien n’est branché';
  static const String ticketsTitle = 'Les demandes de support du SaaS FS, ici.';
  static const String ticketsText =
      'La page existe déjà dans la navigation ; son contenu viendra plus tard de FS Full Flux. Aucun fonctionnement n’est décidé à ce stade.';
  static const String historyTitle = 'Historique d’interventions et notes par appareil.';
  static const String historyText =
      'Réservé pour l’historique des sessions par client et les notes de poste. Le contenu et sa source restent à décider.';

  // Compte FS Solutions (FS Connect) : appareils rangés dans le SaaS (14/10/2026)
  static const String saasSignedIn = 'Rangés dans FS Solutions';
  static const String saasSignIn = 'Retrouvez vos appareils sur tous vos postes';
  static const String signInFsConnect = 'Se connecter avec FS Connect';
  static const String signOut = 'Se déconnecter';
  static const String saasUnreachable = 'FS Solutions injoignable : appareils de ce poste';
  static const String saasEmptyTitle = 'Aucun appareil dans votre compte FS Solutions.';
  static const String saasEmptyText =
      'Ouvrez une session vers un poste : il est rangé ici, et vous le retrouvez sur tous les postes où vous êtes connecté.';
  static const String fsConnectUnavailable = 'Connexion FS Connect indisponible pour le moment.';

  // Fenêtre « Se connecter » : état de la demande au serveur FS (14/10/2026)
  static const String loginLoading = 'Connexion au serveur FS…';
  static const String loginUnreachable =
      'Impossible de joindre le serveur FS. Vérifiez la connexion Internet puis réessayez.';
  static String loginServerError(int? code) =>
      'Le serveur FS ne répond pas correctement pour le moment${code == null ? '' : ' (code $code)'}. Réessayez dans un instant.';
  static const String retry = 'Réessayer';

  // Synchronisation des appareils avec le compte FS Solutions (14/10/2026)
  static const String syncLocalOnlyPc =
      'Appareils enregistrés sur ce PC seulement — connectez-vous pour les sauvegarder';
  static const String syncLocalOnlyDevice =
      'Appareils enregistrés sur cet appareil seulement — connectez-vous pour les sauvegarder';
  static const String syncInProgress = 'Synchronisation…';
  static const String syncDone = 'Synchronisé';
  static const String syncFailed = 'Synchronisation impossible, nouvel essai…';
  static String syncLastAt(String heure) => 'Dernière synchronisation : $heure';

  // Couleur de l'interface (14/10/2026)
  static const String paletteWord = 'Couleur';
  static const String paletteTitle = 'Choisissez la couleur de FS Support';
  static const String paletteText =
      'Deux couleurs, chacune en clair et en sombre. Vous pourrez la changer à tout moment dans Paramètres.';
  static String paletteContinue(String nom) => 'Continuer avec $nom';
  static const String paletteSettingsTitle = 'Couleur de l’interface';
  static const String paletteSettingsText =
      'Atelier ou Ardoise ; le mode clair, sombre ou automatique se règle juste au-dessus.';
  static const String techDetails = 'Détails techniques';

  // Tickets FS (superadmin) : demandes reçues par FS Solutions
  static const String ticketsSub = 'Demandes reçues par FS Solutions';
  static const String ticketsOnsite = 'Sur site';
  static const String ticketsAll = 'Toutes';
  static const String ticketsOpen = 'En cours';
  static const String ticketsArchived = 'Archivées';
  static const String ticketsEmpty = 'Aucune demande pour ce filtre.';
  static const String ticketsPick = 'Choisissez une demande pour l’ouvrir.';
  static const String ticketsDenied = 'Tickets FS : réservé aux superadmins FS Solutions.';
  static const String takeControl = 'Prendre la main';
  static const String reply = 'Répondre';
  static const String replyHint = 'Message au fil de la demande (visible dans FS Solutions)';
  static const String refresh = 'Actualiser';
  static const String status = 'Statut';
  static const String slots = 'Créneaux souhaités';
  static const String address = 'Adresse';
  static const String phone = 'Téléphone';
  static const String email = 'E-mail';
  static const String requester = 'Demandeur';
  static const String fsSupportId = 'ID FS Support';
  static const Map<String, String> ticketStatus = {
    'new': 'Nouveau',
    'triage': 'Qualification',
    'waiting_customer': 'Attente client',
    'planned': 'Planifié',
    'done': 'Terminé',
    'cancelled': 'Refusé',
  };
  static const Map<String, String> ticketCategory = {
    'onsite_request': 'Assistance sur site',
    'server_request': 'Demande de serveur',
    'mailbox_create': 'Création de boîte mail',
    'mailbox_change': 'Modification de boîte mail',
    'alias_create': 'Création d’alias',
    'quota_upgrade': 'Augmentation de quota',
    'domain_help': 'Aide domaine',
    'dns_change': 'Changement DNS',
    'access_change': 'Modification d’accès Hosting',
    'general': 'Demande',
  };

  // Demande d'intervention sur site (client, sans compte)
  static const String onsiteTitle = 'Besoin d’un technicien sur place ?';
  static const String onsiteText = 'FS Solutions vous rappelle pour fixer le rendez-vous.';
  static const String onsiteButton = 'Demander une intervention';
  static const String onsiteDialog = 'Intervention sur site';
  static const String onsiteReason = 'Motif de la demande';
  static const String onsiteReasonHint = 'Ce qui ne va pas, ce qu’il faut installer…';
  static const String onsiteSlots = 'Créneaux souhaités (facultatif)';
  static const String onsiteSlotsHint = 'Ex. mardi matin, jeudi après 14 h';
  static const String onsiteAddress = 'Adresse de l’intervention (facultatif)';
  static const String onsitePhone = 'Téléphone (facultatif)';
  static const String onsiteName = 'Votre nom (facultatif)';
  static const String onsiteEmail = 'E-mail (facultatif)';
  static const String onsiteNote = 'L’identifiant FS Support de ce poste est joint à la demande.';
  static const String onsiteSend = 'Envoyer la demande';
  static const String onsiteSent = 'Demande envoyée';
  static const String onsiteReasonMissing = 'Décrivez le besoin en quelques mots.';

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
  static const String overlay = 'Afficher par-dessus les applis';
  static const String overlayTodo = 'À autoriser pour voir les demandes partout';
  static const String share = 'Partager';
  static const String connectTab = 'Se connecter';
  static const String settingsTab = 'Réglages';

  // Gestionnaire de connexions
  static const String waiting = 'En attente d’une connexion…';
  static const String technician = 'Technicien FS';
}
