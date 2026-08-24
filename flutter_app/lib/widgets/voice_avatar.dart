import 'package:flutter/material.dart';
import '../data/voice_characters.dart';

/// Avatar photo réaliste représentant le personnage fictif d'une voix.
class VoiceAvatar extends StatelessWidget {
  final VoiceCharacter character;
  final double size;

  const VoiceAvatar({super.key, required this.character, this.size = 32});

  @override
  Widget build(BuildContext context) {
    if (character.isLocal && character.photoAsset.isEmpty) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.blueGrey[100],
          shape: BoxShape.circle,
        ),
        child: Icon(Icons.phone_android_rounded, size: size * 0.6, color: Colors.blueGrey[700]),
      );
    }

    // Voix sans portrait dédié (ex: Chirp3-HD) — cercle coloré avec
    // l'initiale du prénom, couleur dérivée du nom pour rester stable.
    if (character.photoAsset.isEmpty) {
      final palette = [
        Colors.indigo, Colors.teal, Colors.deepOrange, Colors.purple,
        Colors.green, Colors.pink, Colors.blue, Colors.brown,
        Colors.cyan, Colors.deepPurple,
      ];
      final color = palette[character.name.hashCode.abs() % palette.length];
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        child: Center(
          child: Text(
            character.name.isNotEmpty ? character.name[0].toUpperCase() : '?',
            style: TextStyle(
              color: Colors.white,
              fontSize: size * 0.4,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      );
    }

    return ClipOval(
      child: Image.asset(
        character.photoAsset,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => Container(
          width: size,
          height: size,
          color: Colors.grey[300],
          child: Icon(Icons.person, size: size * 0.6, color: Colors.grey[600]),
        ),
      ),
    );
  }
}
