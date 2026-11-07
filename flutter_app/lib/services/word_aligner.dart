import 'dart:math' as math;
import 'dart:typed_data';

/// Aligne les mots d'une phrase sur l'audio qu'une voix IA locale vient de
/// produire, et renvoie l'instant de début (secondes) de chaque mot.
///
/// Le moteur (sherpa-onnx) ne fournit aucun horodatage ; on s'appuie donc sur
/// le signal lui-même :
///  1. on ignore le silence de début et de fin (l'ancienne estimation le
///     comptait comme de la parole, d'où un surlignage en avance) ;
///  2. on repère les vraies pauses dans l'audio et on les attache aux
///     ponctuations du texte (virgule, point…) — chaque groupe de mots entre
///     deux pauses est ainsi calé exactement ;
///  3. à l'intérieur d'un groupe, on répartit le temps au prorata d'un poids
///     proche du nombre de syllabes, puis on recale chaque frontière sur le
///     creux d'énergie le plus proche (attaque du mot suivant).
List<double> alignWordsToAudio(String text, Float32List samples, int sampleRate) {
  final words = text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return const [];
  if (samples.isEmpty || sampleRate <= 0) return List.filled(words.length, 0.0);

  // ── Énergie par trame de 10 ms ─────────────────────────────────────────
  final hop = sampleRate ~/ 100;
  final nFrames = samples.length ~/ hop;
  if (nFrames < 3) return List.filled(words.length, 0.0);
  final rms = Float64List(nFrames);
  var peak = 0.0;
  for (var f = 0; f < nFrames; f++) {
    var acc = 0.0;
    final base = f * hop;
    for (var i = 0; i < hop; i++) {
      final s = samples[base + i];
      acc += s * s;
    }
    rms[f] = math.sqrt(acc / hop);
    if (rms[f] > peak) peak = rms[f];
  }
  if (peak <= 0) return List.filled(words.length, 0.0);
  final threshold = peak * 0.03; // ≈ -30 dB sous le pic
  bool silent(int f) => rms[f] < threshold;

  var speechStart = 0;
  while (speechStart < nFrames - 1 && silent(speechStart)) {
    speechStart++;
  }
  var speechEnd = nFrames - 1;
  while (speechEnd > speechStart && silent(speechEnd)) {
    speechEnd--;
  }
  speechEnd++; // exclusif

  // ── Poids des mots (≈ syllabes) ──────────────────────────────────────────
  final weights = words.map(_wordWeight).toList();

  // ── Pauses détectées (≥ 90 ms de silence à l'intérieur de la parole) ────
  final pauses = <_Pause>[];
  var f = speechStart;
  while (f < speechEnd) {
    if (silent(f)) {
      final s = f;
      while (f < speechEnd && silent(f)) {
        f++;
      }
      if (f - s >= 9) pauses.add(_Pause(s, f));
    } else {
      f++;
    }
  }

  // ── Ponctuations attendues (une pause probable après ces mots) ──────────
  final breaks = <int>[]; // index du mot APRÈS lequel la pause tombe
  for (var i = 0; i < words.length - 1; i++) {
    if (RegExp(r'[,;:.!?…—–)\]»"”]$').hasMatch(words[i])) breaks.add(i);
  }

  // Position attendue (en trames) de chaque ponctuation, à débit uniforme.
  final totalW = weights.fold<double>(0, (a, b) => a + b);
  final span = (speechEnd - speechStart).toDouble();
  final cum = <double>[0];
  for (final w in weights) {
    cum.add(cum.last + w);
  }
  double expectedFrame(int wordIdxAfter) =>
      speechStart + span * cum[wordIdxAfter + 1] / totalW;

  // Appariement monotone pauses ↔ ponctuations par programmation dynamique :
  // une pause longue appariée rapporte beaucoup, une pause longue laissée
  // sans ponctuation coûte cher (c'est presque toujours une ponctuation), une
  // ponctuation sans pause coûte peu (virgules souvent enchaînées), et
  // l'écart à la position attendue pénalise les appariements invraisemblables.
  final assigned = <int, _Pause>{}; // index dans breaks -> pause
  final nb = breaks.length, np = pauses.length;
  if (nb > 0 && np > 0) {
    double matchGain(int k, int j) {
      final p = pauses[j];
      final dist = (expectedFrame(breaks[k]) - p.center).abs() / span;
      return 10 + math.min(p.length, 40) * 0.4 - dist * 60;
    }

    double skipPause(int j) => -math.max(0, pauses[j].length - 14) * 0.6;
    const skipBreak = -4.0;
    // dp[k][j] : meilleur score avec k ponctuations et j pauses traitées.
    final dp = List.generate(nb + 1, (_) => List.filled(np + 1, -1e18));
    final from = List.generate(nb + 1, (_) => List.filled(np + 1, 0));
    dp[0][0] = 0;
    for (var k = 0; k <= nb; k++) {
      for (var j = 0; j <= np; j++) {
        final cur = dp[k][j];
        if (cur <= -1e17) continue;
        if (k < nb && cur + skipBreak > dp[k + 1][j]) {
          dp[k + 1][j] = cur + skipBreak;
          from[k + 1][j] = 1;
        }
        if (j < np && cur + skipPause(j) > dp[k][j + 1]) {
          dp[k][j + 1] = cur + skipPause(j);
          from[k][j + 1] = 2;
        }
        if (k < nb && j < np) {
          final v = cur + matchGain(k, j);
          if (v > dp[k + 1][j + 1]) {
            dp[k + 1][j + 1] = v;
            from[k + 1][j + 1] = 3;
          }
        }
      }
    }
    var k = nb, j = np;
    while (k > 0 || j > 0) {
      final step = from[k][j];
      if (step == 3) {
        assigned[k - 1] = pauses[j - 1];
        k--;
        j--;
      } else if (step == 1) {
        k--;
      } else {
        j--;
      }
    }
  }

  // ── Segments ancrés : [début, fin) en trames, mots [w0, w1) ──────────────
  final starts = List<double>.filled(words.length, 0);
  final anchors = assigned.entries.toList()
    ..sort((a, b) => a.key.compareTo(b.key));
  var segStartFrame = speechStart.toDouble();
  var segFirstWord = 0;
  void fillSegment(int w1, double endFrame) {
    final segW = cum[w1] - cum[segFirstWord];
    final len = endFrame - segStartFrame;
    for (var i = segFirstWord; i < w1; i++) {
      var pos = segW > 0
          ? segStartFrame + len * (cum[i] - cum[segFirstWord]) / segW
          : segStartFrame;
      // Signe isolé (« ; » précédé d'une espace) : rien à prononcer, il
      // reste collé à la fin du mot précédent, sans recalage.
      if (i > segFirstWord && weights[i] > 0) {
        pos = _snapToDip(rms, pos.round(), 6, segStartFrame.ceil() + 1,
                endFrame.floor() - 1)
            .toDouble();
      }
      starts[i] = pos;
    }
  }

  for (final a in anchors) {
    final lastWordBefore = breaks[a.key];
    fillSegment(lastWordBefore + 1, a.value.start.toDouble());
    segStartFrame = a.value.end.toDouble();
    segFirstWord = lastWordBefore + 1;
  }
  fillSegment(words.length, speechEnd.toDouble());

  // Monotonie stricte et conversion en secondes.
  final result = <double>[];
  var prev = -1.0;
  for (final s in starts) {
    final v = math.max(s, prev + 1);
    result.add(v / 100.0);
    prev = v;
  }
  return result;
}

class _Pause {
  _Pause(this.start, this.end);
  final int start;
  final int end;
  int get length => end - start;
  double get center => (start + end) / 2;
}

/// Poids d'un mot ≈ durée relative à l'oral : groupes de voyelles (syllabes)
/// + consonnes, et les chiffres lus en toutes lettres comptent davantage.
double _wordWeight(String word) {
  final lower = word.toLowerCase();
  var letters = 0;
  var vowelGroups = 0;
  var digits = 0;
  var inVowel = false;
  for (final r in lower.runes) {
    final c = String.fromCharCode(r);
    if (RegExp(r'[0-9]').hasMatch(c)) {
      digits++;
      inVowel = false;
    } else if (RegExp(r'[aeiouyàâäéèêëîïôöùûüœæãõáíóú]').hasMatch(c)) {
      letters++;
      if (!inVowel) vowelGroups++;
      inVowel = true;
    } else if (RegExp(r'\p{L}', unicode: true).hasMatch(c)) {
      letters++;
      inVowel = false;
    } else {
      inVowel = false;
    }
  }
  if (letters == 0 && digits == 0) return 0; // ponctuation seule
  return 0.8 + letters * 0.35 + vowelGroups * 1.0 + digits * 5.0;
}

/// Cherche, à ±[radius] trames de [center], la trame d'énergie minimale
/// (lissée sur 3 trames) — en général l'attaque du mot suivant.
int _snapToDip(Float64List rms, int center, int radius, int lo, int hi) {
  if (hi <= lo) return center.clamp(0, rms.length - 1);
  final from = math.max(lo, center - radius);
  final to = math.min(hi, center + radius);
  if (to < from) return center.clamp(lo, hi);
  var best = center.clamp(from, to);
  var bestVal = double.infinity;
  for (var i = from; i <= to; i++) {
    final a = rms[math.max(0, i - 1)];
    final b = rms[i];
    final c = rms[math.min(rms.length - 1, i + 1)];
    // Légère préférence pour la position estimée, pour ne pas sauter trop loin.
    final v = (a + b + c) / 3 * (1 + 0.04 * (i - center).abs());
    if (v < bestVal) {
      bestVal = v;
      best = i;
    }
  }
  return best;
}
