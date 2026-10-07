// FS Support — barre du bas Android de l'Atelier.
//
// Sous-classe de BottomNavigationBar : le code RustDesk qui lit `navigationBarKey.currentWidget` comme un
// BottomNavigationBar (onglet courant, ouverture du chat) continue de fonctionner ; seul le rendu change.
import 'package:flutter/material.dart';
import 'package:fs_ui/fs_ui.dart';

class FsMobileBottomBar extends BottomNavigationBar {
  FsMobileBottomBar({
    super.key,
    required super.items,
    super.currentIndex,
    super.onTap,
  });

  @override
  State<BottomNavigationBar> createState() => _FsMobileBottomBarState();
}

class _FsMobileBottomBarState extends State<BottomNavigationBar> {
  @override
  Widget build(BuildContext context) => FsBottomNav(
        items: [for (final it in widget.items) FsBottomItem.widget(it.icon, it.label ?? '')],
        index: widget.currentIndex,
        onTap: widget.onTap,
        bottomInset: MediaQuery.of(context).padding.bottom,
      );
}
