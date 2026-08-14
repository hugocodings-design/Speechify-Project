import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'models/ebook.dart';
import 'models/chapter.dart';
import 'models/audio_chunk.dart';
import 'screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.example.speechify.channel.audio',
    androidNotificationChannelName: 'Speechify',
    androidNotificationOngoing: true,
  );

  // Désactive le mode edge-to-edge pour éviter que le contenu passe derrière la barre système
  SystemChrome.setEnabledSystemUIMode(
    SystemUiMode.manual,
    overlays: SystemUiOverlay.values,
  );

  // Initialize Hive
  await Hive.initFlutter();
  
  // Register Hive models
  Hive.registerAdapter(EbookAdapter());
  Hive.registerAdapter(ChapterAdapter());
  Hive.registerAdapter(AudioChunkAdapter());

  // Ouvrir les boîtes Hive au démarrage
  await Hive.openBox('settings');

  runApp(const SpeechifyApp());
}

class SpeechifyApp extends StatelessWidget {
  const SpeechifyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Speechify',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.light,
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.dark,
        ),
      ),
      themeMode: ThemeMode.system,
      home: const HomeScreen(),
    );
  }
}
