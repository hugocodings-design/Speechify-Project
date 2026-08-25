import 'package:flutter/material.dart';

/// Petit intitulé de section (ex. « APPARENCE »), utilisé dans les écrans
/// Profil/Paramètres — repris tel quel depuis l'ancien settings_screen.dart.
class SectionHeader extends StatelessWidget {
  final String label;
  const SectionHeader({Key? key, required this.label}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: Theme.of(context).colorScheme.primary,
          letterSpacing: 1.1,
        ),
      ),
    );
  }
}
