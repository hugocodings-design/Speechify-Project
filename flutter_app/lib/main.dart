import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'models/ebook.dart';
import 'models/chapter.dart';
import 'models/audio_chunk.dart';
import 'models/folder.dart';
import 'models/annotation.dart';
import 'screens/main_screen.dart';
import 'services/speechify_audio_handler.dart';

// Préférences globales accessibles partout dans l'app
final ValueNotifier<ThemeMode> themeModeNotifier = ValueNotifier(ThemeMode.system);
final ValueNotifier<String?> fontFamilyNotifier = ValueNotifier(null);
final ValueNotifier<double> fontSizeNotifier = ValueNotifier(16.0);

// Handler audio global pour la notification de lecture en arrière-plan
SpeechifyAudioHandler? audioHandler;

// Réinitialise AudioService si audioHandler est null (artefact de hot restart en dev)
Future<void> ensureAudioHandler() async {
  if (audioHandler != null) return;
  // Récupérer l'instance existante si AudioService est déjà initialisé
  if (SpeechifyAudioHandler.instance != null) {
    audioHandler = SpeechifyAudioHandler.instance;
    debugPrint('✅ AudioService handler récupéré via _instance');
    return;
  }
  try {
    audioHandler = await AudioService.init(
      builder: () => SpeechifyAudioHandler(),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.example.speechify.audio',
        androidNotificationChannelName: 'Speechify',
        androidNotificationIcon: 'drawable/ic_notification',
        androidStopForegroundOnPause: false,
      ),
    );
    debugPrint('✅ AudioService (re)init OK');
  } catch (e) {
    // Peu importe la cause (AssertionError si le service Android tourne
    // encore, PlatformException si l'Activity n'est pas prête...) : le
    // builder de AudioService.init() peut avoir déjà tourné et construit un
    // SpeechifyAudioHandler avant l'échec, auquel cas SpeechifyAudioHandler
    // .instance pointe déjà dessus. Il FAUT récupérer cette même instance
    // plutôt que d'en construire une nouvelle — sinon les widgets qui
    // écoutent l'instance capturée avant l'échec (ex: le mini-lecteur, dont
    // le ValueNotifier est lié à une instance précise) ne voient plus jamais
    // les mises à jour faites sur la "vraie" instance utilisée ensuite pour
    // la lecture.
    debugPrint('⚠️ AudioService.init a échoué ($e) — récupération du handler existant');
    audioHandler = SpeechifyAudioHandler.instance ?? SpeechifyAudioHandler();
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Filet de sécurité global : un pépin de rendu transitoire n'importe où
  // dans l'app (ex: un débordement de layout pendant un défilement rapide
  // ou un changement de taille de police) ne doit jamais remplacer l'écran
  // par le grand rectangle rouge/jaune-noir de Flutter — surtout pendant la
  // lecture d'un livre, où ça cache tout le texte. On affiche à la place un
  // espace vide et discret pour le seul widget concerné ; le reste de
  // l'écran continue de fonctionner normalement.
  ErrorWidget.builder = (FlutterErrorDetails details) {
    FlutterError.reportError(details);
    return const SizedBox.shrink();
  };

  await ensureAudioHandler();

  // Initialiser Hive
  await Hive.initFlutter();

  // Enregistrer les adaptateurs Hive
  Hive.registerAdapter(EbookAdapter());
  Hive.registerAdapter(ChapterAdapter());
  Hive.registerAdapter(AudioChunkAdapter());
  Hive.registerAdapter(FolderAdapter());
  Hive.registerAdapter(AnnotationAdapter());

  // Ouvrir les boxes persistantes
  await Hive.openBox<Folder>('folders');
  await Hive.openBox<Ebook>('ebooks');
  await Hive.openBox<Annotation>('annotations');
  await Hive.openBox('reading_stats');
  final settings = await Hive.openBox('settings');

  // Restaurer les préférences sauvegardées
  final savedTheme = settings.get('themeMode', defaultValue: 'system') as String;
  themeModeNotifier.value = _parseThemeMode(savedTheme);
  fontFamilyNotifier.value = settings.get('fontFamily') as String?;
  fontSizeNotifier.value = (settings.get('fontSize', defaultValue: 16.0) as num).toDouble();

  runApp(const SpeechifyApp());
}

ThemeMode _parseThemeMode(String value) {
  switch (value) {
    case 'light': return ThemeMode.light;
    case 'dark':  return ThemeMode.dark;
    default:      return ThemeMode.system;
  }
}

class SpeechifyApp extends StatefulWidget {
  const SpeechifyApp({Key? key}) : super(key: key);

  @override
  State<SpeechifyApp> createState() => _SpeechifyAppState();
}

class _SpeechifyAppState extends State<SpeechifyApp> {
  @override
  void initState() {
    super.initState();
    // Demander la permission notification dès le premier frame affiché
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _requestNotificationPermission();
    });
  }

  Future<void> _requestNotificationPermission() async {
    final status = await Permission.notification.status;
    if (status.isDenied) {
      await Permission.notification.request();
    }
    // Exemption batterie Samsung One UI — évite que le foreground service soit tué
    if (await Permission.ignoreBatteryOptimizations.isDenied) {
      await Permission.ignoreBatteryOptimizations.request();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeModeNotifier,
      builder: (context, themeMode, _) {
        return MaterialApp(
          title: 'Speechify',
          debugShowCheckedModeBanner: false,
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
          themeMode: themeMode,
          home: const MainScreen(),
        );
      },
    );
  }
}
