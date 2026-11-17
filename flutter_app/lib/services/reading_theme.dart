import 'package:flutter/material.dart';

/// Couleur de page du lecteur (comme sur une liseuse) : 'auto' suit le thème
/// clair/sombre de l'app, les autres imposent un fond et un texte précis.
final ValueNotifier<String> pageThemeNotifier = ValueNotifier('auto');

/// Filtre chaud (0 = aucun, 1 = maximum) : réduit la lumière bleue, sur
/// toute l'app — texte, couvertures, images.
final ValueNotifier<double> warmthNotifier = ValueNotifier(0);

/// Assombrissement supplémentaire (0 = aucun, 1 = maximum), au-delà du
/// minimum de luminosité du téléphone, sur toute l'app.
final ValueNotifier<double> dimNotifier = ValueNotifier(0);

class PageTheme {
  final String id;
  final Color background;
  final Color text;
  final Color accent;
  final Brightness brightness;
  const PageTheme(this.id, this.background, this.text, this.accent, this.brightness);
}

const pageThemes = <PageTheme>[
  PageTheme('white', Color(0xFFFFFFFF), Color(0xFF1A1A1A), Colors.blue, Brightness.light),
  PageTheme('paper', Color(0xFFF4ECD8), Color(0xFF3B2F23), Color(0xFF8B5E34), Brightness.light),
  PageTheme('green', Color(0xFFD3E8D0), Color(0xFF1E2D1F), Color(0xFF3F7D45), Brightness.light),
  PageTheme('gray', Color(0xFF3E3F42), Color(0xFFE4E2DD), Color(0xFF9DB4D3), Brightness.dark),
  PageTheme('night', Color(0xFF000000), Color(0xFFB9B0A0), Color(0xFFC9A46B), Brightness.dark),
];

PageTheme? pageThemeById(String id) {
  for (final t in pageThemes) {
    if (t.id == id) return t;
  }
  return null;
}

/// Thème du lecteur pour la couleur de page [id] (le thème de l'app tel quel
/// pour 'auto').
ThemeData readerThemeData(ThemeData base, String id) {
  final p = pageThemeById(id);
  if (p == null) return base;
  final dark = p.brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(seedColor: p.accent, brightness: p.brightness).copyWith(
    surface: p.background,
    onSurface: p.text,
    onSurfaceVariant: p.text.withValues(alpha: 0.7),
    surfaceContainerHighest: Color.alphaBlend(
        (dark ? Colors.white : Colors.black).withValues(alpha: 0.07), p.background),
    surfaceContainerHigh: Color.alphaBlend(
        (dark ? Colors.white : Colors.black).withValues(alpha: 0.05), p.background),
    surfaceContainer: Color.alphaBlend(
        (dark ? Colors.white : Colors.black).withValues(alpha: 0.04), p.background),
  );
  return base.copyWith(
    colorScheme: scheme,
    brightness: p.brightness,
    scaffoldBackgroundColor: p.background,
    canvasColor: p.background,
    appBarTheme: base.appBarTheme.copyWith(
      backgroundColor: p.background,
      foregroundColor: p.text,
      surfaceTintColor: Colors.transparent,
    ),
    iconTheme: base.iconTheme.copyWith(color: p.text),
    textTheme: base.textTheme.apply(bodyColor: p.text, displayColor: p.text),
  );
}

/// Calque posé sur toute l'app (MaterialApp.builder) : filtre chaud et
/// assombrissement. Ne capte aucun toucher.
class ComfortFilter extends StatelessWidget {
  final Widget child;
  const ComfortFilter({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        Positioned.fill(
          child: IgnorePointer(
            child: ValueListenableBuilder<double>(
              valueListenable: warmthNotifier,
              builder: (context, warmth, _) => ValueListenableBuilder<double>(
                valueListenable: dimNotifier,
                builder: (context, dim, _) {
                  if (warmth <= 0 && dim <= 0) return const SizedBox.shrink();
                  // Voile orange (moins de bleu), puis voile noir pour assombrir.
                  return Stack(children: [
                    if (warmth > 0)
                      Positioned.fill(
                        child: ColoredBox(
                          color: const Color(0xFFFF9A3C).withValues(alpha: 0.28 * warmth),
                        ),
                      ),
                    if (dim > 0)
                      Positioned.fill(
                        child: ColoredBox(color: Colors.black.withValues(alpha: 0.65 * dim)),
                      ),
                  ]);
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}
