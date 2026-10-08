// FS Support — accueil du bureau, habillage « A · Atelier ».
//
// Accroche unique dans `desktop/pages/desktop_home_page.dart` (`build`) : hors mode « réception seule »,
// l'accueil RustDesk (volet gauche + ConnectionPage + PeerTabPage) est remplacé par [FsDesktopHome].
// Tout le comportement reste celui de RustDesk : ID et mot de passe (`ServerModel`), connexion (`connect`),
// vues d'appareils (`RecentPeersView`…, menus, état en ligne), carnet d'adresses, découverte locale,
// cartes d'aide (mise à jour, installation) et état du service (`OnlineStatusWidget`, monté hors écran).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fs_ui/fs_ui.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';

import '../common.dart';
import '../common/widgets/address_book.dart';
import '../common/widgets/fs_company_groups.dart';
import '../common/widgets/login.dart';
import '../common/widgets/peer_card.dart';
import '../common/widgets/peers_view.dart';
import '../consts.dart';
import '../desktop/pages/connection_page.dart' show OnlineStatusWidget;
import '../desktop/pages/desktop_setting_page.dart';
import '../models/peer_model.dart';
import '../models/peer_tab_model.dart';
import '../models/platform_model.dart';
import '../models/server_model.dart';
import '../models/state_model.dart';
import 'fs_peer_row.dart';

/// Active l'accueil de l'Atelier (repli possible sur l'accueil RustDesk en passant à `false`).
const bool kFsAtelierHome = true;

const String _kOptionFsHomePanel = 'fs-home-panel';

class FsDesktopHome extends StatefulWidget {
  const FsDesktopHome({super.key, this.helpCards, this.warning});

  /// Cartes d'aide RustDesk (mise à jour, installation, autorisations), posées dans le rail.
  final Widget? helpCards;

  /// Avertissement « mot de passe prédéfini » de RustDesk.
  final Widget? warning;

  @override
  State<FsDesktopHome> createState() => _FsDesktopHomeState();
}

class _FsDesktopHomeState extends State<FsDesktopHome> {
  String _panel = 'devices';
  final _idController = TextEditingController();
  final _idFocus = FocusNode();
  String _version = '';

  static const _panels = {
    'devices': PeerTabIndex.recent,
    'recent': PeerTabIndex.recent,
    'fav': PeerTabIndex.fav,
    'ab': PeerTabIndex.ab,
    'lan': PeerTabIndex.lan,
  };

  @override
  void initState() {
    super.initState();
    fsLoadCompanyOptions();
    // Liste filetée par défaut ; un choix fait à la main (liste, tuiles, cartes) est respecté.
    final uiType = bind.getLocalFlutterOption(k: kOptionPeerCardUiType);
    peerCardUiType.value = uiType == ''
        ? PeerUiType.list
        : (int.tryParse(uiType) == 0
            ? PeerUiType.grid
            : int.tryParse(uiType) == 1
                ? PeerUiType.tile
                : PeerUiType.list);
    hideAbTagsPanel.value = bind.mainGetLocalOption(key: kOptionHideAbTagsPanel) == 'Y';
    peerSearchText.value = '';
    final saved = bind.getLocalFlutterOption(k: _kOptionFsHomePanel);
    if (saved.isNotEmpty && (_panels.containsKey(saved) || saved.startsWith('soon-'))) _panel = saved;
    _syncTab();
    bind.mainGetVersion().then((v) {
      if (mounted) setState(() => _version = v);
    });
  }

  @override
  void dispose() {
    _idController.dispose();
    _idFocus.dispose();
    super.dispose();
  }

  void _syncTab() {
    final tab = _panels[_panel];
    if (tab == null) return;
    if (tab.index != gFFI.peerTabModel.currentTab) {
      gFFI.peerTabModel.setCurrentTabCachedPeers([]);
    }
    gFFI.peerTabModel.setCurrentTab(tab.index);
    if (tab == PeerTabIndex.ab) {
      gFFI.abModel.pullAb(force: null, quiet: true);
    }
  }

  void _select(String key) {
    if (key == _panel) return;
    setState(() => _panel = key);
    bind.setLocalFlutterOption(k: _kOptionFsHomePanel, v: key);
    fsSelectedPeerId.value = '';
    _syncTab();
  }

  // --- connexion ---------------------------------------------------------

  String _resolveId(String text) {
    final raw = text.trim();
    if (raw.isEmpty) return '';
    final digits = raw.replaceAll(' ', '');
    if (RegExp(r'^\d+$').hasMatch(digits)) return digits;
    final all = <Peer>[
      ...gFFI.recentPeersModel.peers,
      ...gFFI.favoritePeersModel.peers,
      ...gFFI.abModel.peersModel.peers,
      ...gFFI.lanPeersModel.peers,
    ];
    final lower = raw.toLowerCase();
    for (final p in all) {
      if (p.alias.toLowerCase() == lower || p.hostname.toLowerCase() == lower) return p.id;
    }
    // Un seul appareil correspond à la recherche : on le prend.
    final hits = all.where((p) => p.alias.toLowerCase().contains(lower) || p.id.contains(digits)).map((p) => p.id).toSet();
    if (hits.length == 1) return hits.first;
    return digits;
  }

  void _connect(String text, {bool files = false}) {
    final id = _resolveId(text);
    if (id.isEmpty) {
      _idFocus.requestFocus();
      return;
    }
    connect(context, id, isFileTransfer: files);
  }

  // --- rail --------------------------------------------------------------

  Widget _meBlock() {
    if (bind.isOutgoingOnly()) return const SizedBox(height: 20);
    return ChangeNotifierProvider.value(
      value: gFFI.serverModel,
      child: Consumer<ServerModel>(builder: (context, model, _) {
        final showOneTime = model.approveMode != 'click' && model.verificationMethod != kUsePermanentPassword;
        final id = model.serverId.text.replaceAll(' ', '');
        final canEdit = !bind.isDisableSettings();
        return Builder(
          builder: (context) => FsMeBlock(
            id: fsFormatId(id),
            password: showOneTime ? model.serverPasswd.text : '••••••',
            passwordLabel: showOneTime ? FsStrings.oneTimePassword : FsStrings.permanentPassword,
            onCopyId: () => fsCopy(context, id, FsStrings.idCopied),
            onCopyPassword: showOneTime ? () => fsCopy(context, model.serverPasswd.text, FsStrings.passwordCopied) : null,
            onRefresh: showOneTime ? () => bind.mainUpdateTemporaryPassword() : null,
            onEdit: canEdit ? () => DesktopSettingPage.switch2page(SettingsTabKey.safety) : null,
          ),
        );
      }),
    );
  }

  Widget _nav() => AnimatedBuilder(
        animation: Listenable.merge([gFFI.recentPeersModel, gFFI.favoritePeersModel]),
        builder: (context, _) {
          final items = [
            FsNavItem(key: 'devices', icon: Icons.devices_rounded, label: FsStrings.devices, count: gFFI.recentPeersModel.peers.length),
            const FsNavItem(key: 'recent', icon: Icons.history_rounded, label: FsStrings.recent),
            FsNavItem(key: 'fav', icon: Icons.star_outline_rounded, label: FsStrings.favorites, count: gFFI.favoritePeersModel.peers.length),
            if (!bind.isDisableAb()) const FsNavItem(key: 'ab', icon: Icons.contacts_rounded, label: FsStrings.addressBook),
            const FsNavItem(key: 'lan', icon: Icons.lan_rounded, label: FsStrings.discovered),
            const FsNavItem(key: 'soon-tickets', icon: Icons.confirmation_number_rounded, label: FsStrings.ticketsFs, soon: true),
            const FsNavItem(key: 'soon-hist', icon: Icons.event_note_rounded, label: FsStrings.interventions, soon: true),
          ];
          return FsRailNav(items: items, selected: _panel, onSelect: _select);
        },
      );

  // --- panneaux ----------------------------------------------------------

  Widget _summary(Peers peers, String fallback) => AnimatedBuilder(
        animation: peers,
        builder: (context, _) {
          final total = peers.peers.length;
          final online = peers.peers.where((p) => p.online).length;
          return FsText(total == 0 ? fallback : FsStrings.devicesSummary(total, online),
              style: FsType.sans(13, FontWeight.w400, color: FsTokens.of(context).muted));
        },
      );

  void _sortMenu(Offset pos) async {
    final t = FsTokens.of(context);
    final v = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(pos.dx - 160, pos.dy + 4, pos.dx, pos.dy),
      items: [
        for (final s in PeerSortType.values)
          PopupMenuItem<String>(
            value: s,
            height: 34,
            child: Row(children: [
              Icon(Icons.check_rounded, size: 18, color: peerSort.value == s ? t.acc : Colors.transparent),
              const SizedBox(width: 10),
              FsText(translate(s), style: FsType.sans(13.5, FontWeight.w400, color: t.ink)),
            ]),
          ),
      ],
    );
    if (v != null) {
      peerSort.value = v;
      bind.setLocalFlutterOption(k: kOptionPeerSorting, v: v);
    }
  }

  void _setUiType(PeerUiType type) {
    peerCardUiType.value = type;
    bind.setLocalFlutterOption(k: kOptionPeerCardUiType, v: type.index.toString());
  }

  Widget _tools({bool company = false}) => Obx(() => FsListTools(
        byCompany: fsGroupByCompany.value,
        onByCompany: company ? () => fsSetGroupByCompany(!fsGroupByCompany.value) : null,
        listView: peerCardUiType.value == PeerUiType.list,
        onList: () => _setUiType(PeerUiType.list),
        onCards: () => _setUiType(PeerUiType.grid),
        onSort: _sortMenu,
        extra: [
          if (company && fsGroupByCompany.value) ...[
            const FsChip(label: 'Entreprises…', icon: Icons.edit_note_rounded, onPressed: fsManageCompaniesDialog),
            const SizedBox(width: 6),
          ],
        ],
      ));

  Widget _peersPanel({required String title, required Widget sub, required Widget view, bool company = false, Widget? empty, Peers? source}) {
    Widget body = view;
    if (empty != null && source != null) {
      body = AnimatedBuilder(
        animation: source,
        child: view,
        builder: (context, child) => Stack(children: [
          Positioned.fill(child: child!),
          if (source.peers.isEmpty)
            Positioned.fill(child: ColoredBox(color: FsTokens.of(context).bg, child: Align(alignment: Alignment.topLeft, child: empty))),
        ]),
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 12),
        child: Row(children: [
          FsText(title, style: FsType.sans(26, FontWeight.w800, em: -0.04, color: FsTokens.of(context).ink)),
          const SizedBox(width: 14),
          sub,
          const Spacer(),
          if (company) _tools(company: true) else _tools(),
        ]),
      ),
      Obx(() => AnimatedSwitcher(
            duration: FsMotion.fade,
            child: peerCardUiType.value == PeerUiType.list
                ? const FsColumnsHeader(key: ValueKey('cols'), lastLabel: 'Système')
                : const SizedBox(key: ValueKey('nocols'), width: double.infinity),
          )),
      Expanded(child: body),
    ]);
  }

  Widget _panelBody(BuildContext context) {
    const pad = kDesktopMenuPadding;
    switch (_panel) {
      case 'recent':
        return _peersPanel(
          title: FsStrings.recent,
          sub: FsText(FsStrings.recentSub, style: FsType.sans(13, FontWeight.w400, color: FsTokens.of(context).muted)),
          view: FsGroupingScope(enabled: false, child: RecentPeersView(menuPadding: pad)),
          source: gFFI.recentPeersModel,
          empty: const FsEmptyState(title: FsStrings.emptyTitle, text: FsStrings.emptyText),
        );
      case 'fav':
        return _peersPanel(
          title: FsStrings.favorites,
          sub: FsText(FsStrings.favSub, style: FsType.sans(13, FontWeight.w400, color: FsTokens.of(context).muted)),
          view: FsGroupingScope(enabled: false, child: FavoritePeersView(menuPadding: pad)),
        );
      case 'ab':
        return Obx(() {
          if (!gFFI.userModel.isLogin) {
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const FsPanelHead(title: FsStrings.addressBook),
              FsEmptyState(
                title: FsStrings.abTitle,
                text: FsStrings.abText,
                action: Row(children: [FsButton(label: FsStrings.connect, trailing: Icons.login_rounded, onPressed: () => loginDialog())]),
              ),
            ]);
          }
          return _peersPanel(
            title: FsStrings.addressBook,
            sub: const SizedBox(),
            view: FsGroupingScope(enabled: false, child: AddressBook(menuPadding: pad)),
          );
        });
      case 'lan':
        return _peersPanel(
          title: FsStrings.discovered,
          sub: FsText(FsStrings.lanSub, style: FsType.sans(13, FontWeight.w400, color: FsTokens.of(context).muted)),
          view: FsGroupingScope(enabled: false, child: DiscoveredPeersView(menuPadding: pad)),
          source: gFFI.lanPeersModel,
          empty: FsEmptyState(
            title: FsStrings.lanTitle,
            text: FsStrings.lanText,
            action: Row(children: [
              FsButton(label: FsStrings.relaunch, leading: Icons.radar_rounded, kind: FsButtonKind.ghost, onPressed: () => bind.mainDiscover()),
            ]),
          ),
        );
      case 'soon-tickets':
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const FsPanelHead(title: FsStrings.ticketsFs, sub: FsStrings.slotSub),
          FsSlot(title: FsStrings.ticketsTitle, text: FsStrings.ticketsText, cols: [
            ('Où', TextSpan(children: [const TextSpan(text: 'Nouvelle page '), fsInlineCode(context, 'fs_tickets_page.dart'), const TextSpan(text: ', entrée du rail')])),
            ('Source', const TextSpan(text: 'API FS (à définir)')),
            ('Impact amont', const TextSpan(text: 'Aucun fichier RustDesk touché')),
          ]),
        ]);
      case 'soon-hist':
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const FsPanelHead(title: FsStrings.interventions, sub: FsStrings.slotSub),
          FsSlot(title: FsStrings.historyTitle, text: FsStrings.historyText, cols: [
            ('Où', TextSpan(children: [const TextSpan(text: 'Nouvelle page '), fsInlineCode(context, 'fs_history_page.dart')])),
            ('Source', const TextSpan(text: 'Journal local ou SaaS FS (à définir)')),
            ('Impact amont', const TextSpan(text: 'Aucun fichier RustDesk touché')),
          ]),
        ]);
      default:
        return _peersPanel(
          title: FsStrings.devices,
          sub: _summary(gFFI.recentPeersModel, ''),
          company: true,
          view: FsGroupingScope(enabled: true, child: RecentPeersView(menuPadding: pad)),
          source: gFFI.recentPeersModel,
          empty: const FsEmptyState(title: FsStrings.emptyTitle, text: FsStrings.emptyText),
        );
    }
  }

  // --- barre d'état ------------------------------------------------------

  Widget _status() {
    final stopped = Get.isRegistered<RxBool>(tag: 'stop-service') ? Get.find<RxBool>(tag: 'stop-service') : false.obs;
    return Stack(children: [
      // L'état du service est relevé par le widget RustDesk (minuterie d'une seconde) : on le garde actif hors écran.
      const Offstage(child: OnlineStatusWidget()),
      Obx(() {
        final st = stopped.value
            ? FsServiceState.stopped
            : switch (stateGlobal.svcStatus.value) {
                SvcStatus.ready => FsServiceState.ready,
                SvcStatus.connecting => FsServiceState.connecting,
                SvcStatus.notReady => FsServiceState.notReady,
              };
        final t = FsTokens.of(context);
        return FsStatusBar(
          state: st,
          action: stopped.value
              ? FsHover(
                  onTap: () => start_service(true),
                  builder: (context, hover, _) => FsText(FsStrings.startService,
                      style: FsType.sans(12.5, FontWeight.w600, color: hover ? t.ink : t.acc)),
                )
              : null,
        );
      }),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final rail = FsRail(
      me: _meBlock(),
      nav: _nav(),
      version: _version,
      extra: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (widget.warning != null) widget.warning!,
        if (widget.helpCards != null) widget.helpCards!,
      ]),
      onSettings: bind.isDisableSettings() || DesktopSettingPage.tabKeys.isEmpty
          ? null
          : () => DesktopSettingPage.switch2page(DesktopSettingPage.tabKeys.first),
      onCredit: () => DesktopSettingPage.switch2page(SettingsTabKey.about),
    );
    return Shortcuts(
      shortcuts: const {SingleActivator(LogicalKeyboardKey.keyF, control: true): _FocusSearch()},
      child: Actions(
        actions: {_FocusSearch: CallbackAction<_FocusSearch>(onInvoke: (_) => _idFocus.requestFocus())},
        child: FsHomeView(
          rail: rail,
          connect: FsConnectBar(
            controller: _idController,
            focusNode: _idFocus,
            onChanged: (v) => peerSearchText.value = v.trim(),
            onConnect: (v) => _connect(v),
            onFiles: (v) => _connect(v, files: true),
          ),
          panel: FsPanelSwitcher(panelKey: _panel, child: Builder(builder: _panelBody)),
          status: _status(),
        ),
      ),
    );
  }
}

class _FocusSearch extends Intent {
  const _FocusSearch();
}
