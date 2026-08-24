import 'package:just_audio/just_audio.dart';
import 'package:logger/logger.dart';

class AudioService {
  final AudioPlayer _audioPlayer = AudioPlayer();
  final _logger = Logger();

  // Getters for player state
  Stream<PlayerState> get playerStateStream => _audioPlayer.playerStateStream;
  Stream<Duration?> get positionStream => _audioPlayer.positionStream;
  Stream<Duration?> get durationStream => _audioPlayer.durationStream;
  Stream<double> get speedStream => _audioPlayer.speedStream;

  Duration? get currentPosition => _audioPlayer.position;
  Duration? get duration => _audioPlayer.duration;
  double get currentSpeed => _audioPlayer.speed;
  bool get isPlaying => _audioPlayer.playing;

  /// Initialize audio session (for background playback)
  Future<void> initAudioSession() async {
    // Rien à initialiser — le lecteur est prêt dès la création de l'objet
    _logger.i('Audio session prête');
  }

  /// Load audio from URL or file path
  Future<void> loadAudio(String audioSourceUrl) async {
    try {
      _logger.i('Loading audio: $audioSourceUrl');
      await _audioPlayer.setAudioSource(
        AudioSource.uri(Uri.parse(audioSourceUrl)),
      );
      _logger.i('Audio loaded successfully');
    } catch (e) {
      _logger.e('Error loading audio: $e');
      rethrow;
    }
  }

  /// Play audio
  Future<void> play() async {
    try {
      await _audioPlayer.play();
      _logger.i('Playing audio');
    } catch (e) {
      _logger.e('Error playing audio: $e');
      rethrow;
    }
  }

  /// Pause audio
  Future<void> pause() async {
    try {
      await _audioPlayer.pause();
      _logger.i('Audio paused');
    } catch (e) {
      _logger.e('Error pausing audio: $e');
      rethrow;
    }
  }

  /// Resume audio
  Future<void> resume() async {
    try {
      await _audioPlayer.play();
      _logger.i('Audio resumed');
    } catch (e) {
      _logger.e('Error resuming audio: $e');
      rethrow;
    }
  }

  /// Seek to position
  Future<void> seek(Duration position) async {
    try {
      await _audioPlayer.seek(position);
      _logger.i('Seeked to: $position');
    } catch (e) {
      _logger.e('Error seeking audio: $e');
      rethrow;
    }
  }

  /// Set playback speed
  Future<void> setSpeed(double speed) async {
    try {
      // Clamp speed between 0.5 and 2.0
      final clampedSpeed = speed.clamp(0.5, 2.0);
      await _audioPlayer.setSpeed(clampedSpeed);
      _logger.i('Speed set to: $clampedSpeed');
    } catch (e) {
      _logger.e('Error setting speed: $e');
      rethrow;
    }
  }

  /// Stop and dispose
  Future<void> stop() async {
    try {
      await _audioPlayer.stop();
      _logger.i('Audio stopped');
    } catch (e) {
      _logger.e('Error stopping audio: $e');
    }
  }

  /// Dispose audio player
  Future<void> dispose() async {
    try {
      await _audioPlayer.dispose();
      _logger.i('Audio player disposed');
    } catch (e) {
      _logger.e('Error disposing audio player: $e');
    }
  }

  /// Check if currently playing
  bool get playing => _audioPlayer.playing;
}
