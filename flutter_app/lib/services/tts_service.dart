class Voice {
  final String name;
  final String displayName;
  final String languageCode;
  /// Vrai pour une voix locale (moteur du téléphone, hors ligne) plutôt
  /// qu'une voix IA locale (sherpa-onnx). Plus aucune voix cloud payante.
  final bool isLocal;
  /// Faux pour les voix qui ne renvoient pas de marqueurs SSML (ex: Chirp3-HD
  /// de Google, qui accepte le SSML mais ignore silencieusement les <mark>)
  /// — le surlignage se limite alors à la phrase entière, pas mot par mot.
  final bool hasWordTiming;

  const Voice({
    required this.name,
    required this.displayName,
    required this.languageCode,
    this.isLocal = false,
    this.hasWordTiming = true,
  });

  factory Voice.fromJson(Map<String, dynamic> json) {
    return Voice(
      name: json['name'] as String,
      displayName: json['display_name'] as String,
      languageCode: json['language_code'] as String,
    );
  }
}
