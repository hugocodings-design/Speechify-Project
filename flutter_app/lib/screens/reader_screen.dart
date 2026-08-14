import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:just_audio/just_audio.dart';

import '../models/ebook.dart';
import '../services/tts_service.dart';
import '../services/audio_service.dart';

class ReaderScreen extends StatefulWidget {
  final Ebook ebook;

  const ReaderScreen({Key? key, required this.ebook}) : super(key: key);

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  late TtsService _ttsService;
  late AudioService _audioService;
  late Box<Ebook> _ebookBox;

  int _currentChapterIndex = 0;
  List<Voice> _availableVoices = [];
  String _selectedVoice = 'en-US-Neural2-C';
  bool _isSynthesizing = false;
  double _playbackSpeed = 1.0;
  bool _audioLoaded = false;

  static const List<double> _speedOptions = [0.75, 1.0, 1.25, 1.5];

  @override
  void initState() {
    super.initState();
    _ttsService = TtsService();
    _audioService = AudioService();
    _initializeScreen();
    _listenForChapterCompletion();
  }

  Future<void> _initializeScreen() async {
    _ebookBox = Hive.box<Ebook>('ebooks');

    // Restaurer la position de lecture sauvegardée
    final savedPosition = widget.ebook.lastReadPosition;
    if (savedPosition > 0 && savedPosition < widget.ebook.chapters.length) {
      setState(() => _currentChapterIndex = savedPosition);
    }

    // Restaurer la voix sauvegardée
    if (widget.ebook.selectedVoiceName.isNotEmpty) {
      setState(() => _selectedVoice = widget.ebook.selectedVoiceName);
    }

    await _loadAvailableVoices();
  }

  Future<void> _loadAvailableVoices() async {
    try {
      final voices = await _ttsService.getAvailableVoices();
      if (mounted) {
        setState(() => _availableVoices = voices);
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar('Impossible de charger les voix: $e', isError: true);
      }
    }
  }

  /// Écoute la fin du chapitre pour passer automatiquement au suivant
  void _listenForChapterCompletion() {
    _audioService.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed && mounted) {
        _onChapterCompleted();
      }
    });
  }

  void _onChapterCompleted() {
    final isLast = _currentChapterIndex >= widget.ebook.chapters.length - 1;
    if (isLast) {
      _showSnackBar('Fin du livre !');
    } else {
      setState(() {
        _currentChapterIndex++;
        _audioLoaded = false;
      });
      _synthesizeAndPlay();
    }
  }

  /// Synthétise le chapitre courant et lance la lecture
  Future<void> _synthesizeAndPlay() async {
    if (_isSynthesizing) return;

    final chapter = widget.ebook.chapters[_currentChapterIndex];
    final text = chapter.textContent;

    // Tronquer à 4500 chars pour rester sous la limite de l'API
    final truncated = text.length > 4500 ? text.substring(0, 4500) : text;

    // Extraire le code langue depuis le nom de la voix (ex: "en-US-Neural2-C" → "en-US")
    final langCode = _selectedVoice.length >= 5
        ? _selectedVoice.substring(0, 5)
        : 'en-US';

    setState(() => _isSynthesizing = true);

    try {
      final result = await _ttsService.synthesizeText(
        text: truncated,
        voiceName: _selectedVoice,
        languageCode: langCode,
      );

      final audioContent = result['audio_content'] as String;
      await _audioService.loadFromBase64(audioContent);
      await _audioService.setSpeed(_playbackSpeed);
      await _audioService.play();

      setState(() {
        _isSynthesizing = false;
        _audioLoaded = true;
      });

      // Sauvegarder la position de lecture
      widget.ebook.lastReadPosition = _currentChapterIndex;
      _ebookBox.put(widget.ebook.id, widget.ebook);
    } catch (e) {
      if (mounted) {
        setState(() => _isSynthesizing = false);
        _showSnackBar('Erreur de synthèse: $e', isError: true);
      }
    }
  }

  Future<void> _togglePlayPause() async {
    if (_isSynthesizing) return;

    if (!_audioLoaded) {
      await _synthesizeAndPlay();
      return;
    }

    if (_audioService.isPlaying) {
      await _audioService.pause();
    } else {
      await _audioService.resume();
    }
  }

  void _changeChapter(int newIndex) async {
    if (newIndex < 0 || newIndex >= widget.ebook.chapters.length) return;
    await _audioService.stop();
    setState(() {
      _currentChapterIndex = newIndex;
      _audioLoaded = false;
    });
  }

  void _changeVoice(String? newVoice) {
    if (newVoice == null) return;
    setState(() {
      _selectedVoice = newVoice;
      _audioLoaded = false;
    });
    widget.ebook.selectedVoiceName = newVoice;
    _ebookBox.put(widget.ebook.id, widget.ebook);
  }

  Future<void> _changeSpeed(double speed) async {
    setState(() => _playbackSpeed = speed);
    await _audioService.setSpeed(speed);
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: isError ? Colors.red : null,
    ));
  }

  // ─── UI ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final chapter = widget.ebook.chapters[_currentChapterIndex];

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.ebook.title),
        elevation: 0,
      ),
      // bottomNavigationBar est toujours positionné au-dessus de la barre système Android
      bottomNavigationBar: _buildPlayerPanel(),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              chapter.title,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            Text(
              '${chapter.wordCount} mots',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Colors.grey),
            ),
            const SizedBox(height: 16),
            Text(
              chapter.textContent,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlayerPanel() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          top: BorderSide(color: Colors.grey.shade300),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildVoiceSelector(),
          const SizedBox(height: 8),
          _buildSeekBar(),
          _buildPlaybackControls(),
          const SizedBox(height: 4),
          _buildSpeedSelector(),
          // Espace fixe pour que les boutons ne soient jamais cachés par la barre Samsung
          const SizedBox(height: 60),
        ],
      ),
    );
  }

  Widget _buildVoiceSelector() {
    if (_availableVoices.isEmpty) {
      return const SizedBox(
        height: 36,
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    // S'assurer que la voix sélectionnée est dans la liste
    final voiceNames = _availableVoices.map((v) => v.name).toList();
    final currentVoice =
        voiceNames.contains(_selectedVoice) ? _selectedVoice : voiceNames.first;

    return DropdownButton<String>(
      value: currentVoice,
      isExpanded: true,
      isDense: true,
      onChanged: _changeVoice,
      items: _availableVoices.map((voice) {
        return DropdownMenuItem<String>(
          value: voice.name,
          child: Text(voice.displayName, overflow: TextOverflow.ellipsis),
        );
      }).toList(),
    );
  }

  Widget _buildSeekBar() {
    return StreamBuilder<Duration?>(
      stream: _audioService.positionStream,
      builder: (context, posSnap) {
        return StreamBuilder<Duration?>(
          stream: _audioService.durationStream,
          builder: (context, durSnap) {
            final position = posSnap.data ?? Duration.zero;
            final duration = durSnap.data ?? Duration.zero;
            final maxMs = duration.inMilliseconds.toDouble();
            final posMs =
                position.inMilliseconds.toDouble().clamp(0.0, maxMs > 0 ? maxMs : 0.0);

            return Column(
              children: [
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    thumbShape:
                        const RoundSliderThumbShape(enabledThumbRadius: 6),
                    overlayShape:
                        const RoundSliderOverlayShape(overlayRadius: 14),
                  ),
                  child: Slider(
                    value: posMs,
                    max: maxMs > 0 ? maxMs : 1.0,
                    onChanged: maxMs > 0
                        ? (value) => _audioService
                            .seek(Duration(milliseconds: value.toInt()))
                        : null,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(_formatDuration(position),
                          style: Theme.of(context).textTheme.bodySmall),
                      Text(_formatDuration(duration),
                          style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildPlaybackControls() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Chapitre précédent
        IconButton(
          onPressed: _currentChapterIndex > 0
              ? () => _changeChapter(_currentChapterIndex - 1)
              : null,
          icon: const Icon(Icons.skip_previous, size: 32),
          tooltip: 'Chapitre précédent',
        ),

        const SizedBox(width: 24),

        // Bouton Play / Pause
        StreamBuilder<PlayerState>(
          stream: _audioService.playerStateStream,
          builder: (context, snapshot) {
            final isPlaying = snapshot.data?.playing ?? false;

            return SizedBox(
              width: 64,
              height: 64,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  shape: const CircleBorder(),
                  padding: EdgeInsets.zero,
                ),
                onPressed: _isSynthesizing ? null : _togglePlayPause,
                child: _isSynthesizing
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      )
                    : Icon(
                        isPlaying ? Icons.pause : Icons.play_arrow,
                        size: 32,
                      ),
              ),
            );
          },
        ),

        const SizedBox(width: 24),

        // Chapitre suivant
        IconButton(
          onPressed:
              _currentChapterIndex < widget.ebook.chapters.length - 1
                  ? () => _changeChapter(_currentChapterIndex + 1)
                  : null,
          icon: const Icon(Icons.skip_next, size: 32),
          tooltip: 'Chapitre suivant',
        ),
      ],
    );
  }

  Widget _buildSpeedSelector() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: _speedOptions.map((speed) {
        final isSelected = _playbackSpeed == speed;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: ChoiceChip(
            label: Text('${speed}x'),
            selected: isSelected,
            onSelected: (_) => _changeSpeed(speed),
            labelStyle: TextStyle(
              fontSize: 12,
              fontWeight:
                  isSelected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        );
      }).toList(),
    );
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  void dispose() {
    _audioService.dispose();
    super.dispose();
  }
}
