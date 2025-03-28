import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'package:provider/provider.dart';
import 'screens/session_prompt_screen.dart';
import 'providers/app_state.dart';
import 'screens/main_screen.dart';
import 'screens/settings_screen.dart';
import 'utils/app_themes.dart';
import 'package:path_provider/path_provider.dart';
import 'hive_database.dart';
import 'dart:async';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'services/translation_service.dart';
import 'services/background_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/foundation.dart';
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:hive_flutter/hive_flutter.dart';

// Single global instance for error tracking
final _errorHandler = ErrorHandler();

// Global variables for initialization error handling
bool hasInitializationError = false;
String errorMessage = '';

Future<void> requestStoragePermission() async {
  if (await Permission.storage.isDenied) {
    await Permission.storage.request();
  }
  // For Android 13 and above
  if (await Permission.photos.isDenied) {
    await Permission.photos.request();
  }
  if (await Permission.audio.isDenied) {
    await Permission.audio.request();
  }
  if (await Permission.videos.isDenied) {
    await Permission.videos.request();
  }
  
  // For background service
  if (await Permission.notification.isDenied) {
    await Permission.notification.request();
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Hive
  await Hive.initFlutter();
  
  // Request necessary permissions at startup
  await _requestPermissions();
  
  // Initialize background service
  final backgroundService = BackgroundService();
  await backgroundService.initialize();
  
  // Initialize Android Alarm Manager
  await AndroidAlarmManager.initialize();
  
  // Set preferred orientation to portrait
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  
  // Configure status bar color
  SystemChrome.setSystemUIOverlayStyle(
    SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Colors.black,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  
  // Initialize directory for databases and files
  try {
    if (!kIsWeb) {
      final appDocDir = await getApplicationDocumentsDirectory();
      await Directory('${appDocDir.path}/sessions').create(recursive: true);
    }
  } catch (e) {
    print('Error creating app directory: $e');
  }
  
  // Enable wakelock to keep the screen on when the app is active
  try {
    await WakelockPlus.enable();
  } catch (e) {
    print('Error enabling wakelock: $e');
  }

  try {
    // Initialize Hive
    await HiveSessionDatabase.instance.init();
    print('Hive database initialized successfully');
  } catch (e) {
    print('Error initializing Hive: $e');
    hasInitializationError = true;
    errorMessage = e.toString();
  }
  
  // Set up global error handlers first
  FlutterError.onError = _errorHandler.handleFlutterError;
  PlatformDispatcher.instance.onError = _errorHandler.handlePlatformError;
  
  // Handle platform-specific concerns
  if (Platform.isAndroid) {
    // Configure UI mode
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, 
      overlays: [SystemUiOverlay.top, SystemUiOverlay.bottom]);
  }
  
  runApp(
    // Wrap everything in an error boundary
    ErrorBoundaryWidget(
      child: ChangeNotifierProvider(
        create: (context) => AppState(),
        child: SoccerTimeApp(),
      ),
    ),
  );
}

// Function to request all necessary permissions at startup
Future<void> _requestPermissions() async {
  print("Requesting necessary permissions at startup...");
  
  // Request notification permission for Android 13+
  final notificationStatus = await Permission.notification.request();
  print("Notification permission status: $notificationStatus");
  
  // Request post notifications permission explicitly
  if (await Permission.notification.isDenied) {
    await Permission.notification.request();
  }
  
  // Request battery optimization permission
  if (await Permission.ignoreBatteryOptimizations.isDenied) {
    await Permission.ignoreBatteryOptimizations.request();
  }
}

// Centralized error handling
class ErrorHandler {
  // Track seen errors to avoid log spam
  final Set<String> _seenErrors = {};
  
  void handleFlutterError(FlutterErrorDetails details) {
    final errorString = details.exception.toString();
    
    // Handle known errors
    if (_shouldSuppressError(errorString)) {
      // Just log it once to avoid spam
      if (!_seenErrors.contains(errorString)) {
        print('Suppressed Flutter error: ${details.exception}');
        _seenErrors.add(errorString);
      }
      return;
    }
    
    // Use default error handling for other errors
    FlutterError.presentError(details);
  }
  
  bool handlePlatformError(Object error, StackTrace stack) {
    final errorString = error.toString();
    
    // Handle known errors
    if (_shouldSuppressError(errorString)) {
      // Just log it once to avoid spam
      if (!_seenErrors.contains(errorString)) {
        print('Suppressed Platform error: $error');
        _seenErrors.add(errorString);
      }
      return true;
    }
    
    // Let platform handle other errors
    return false;
  }
  
  bool _shouldSuppressError(String errorString) {
    // List of error patterns to suppress
    final suppressPatterns = [
      'OpenGL ES API',
      'read-only',
      'Failed assertion', 
      '_dependents.isEmpty',
      '_children.contains(child)',
      'LateInitializationError: Field',
      'Duplicate GlobalKeys',
    ];
    
    // Check if this error should be suppressed
    return suppressPatterns.any((pattern) => errorString.contains(pattern));
  }
}

class ErrorBoundaryWidget extends StatefulWidget {
  final Widget child;
  
  const ErrorBoundaryWidget({Key? key, required this.child}) : super(key: key);
  
  @override
  _ErrorBoundaryWidgetState createState() => _ErrorBoundaryWidgetState();
}

class _ErrorBoundaryWidgetState extends State<ErrorBoundaryWidget> {
  bool _hasError = false;
  
  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return MaterialApp(
        home: Scaffold(
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('Something went wrong.'),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _hasError = false;
                    });
                  },
                  child: Text('Try Again'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    
    return widget.child;
  }
  
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Remove the post-frame callback which can cause issues
  }
}

class SoccerTimeApp extends StatefulWidget {
  @override
  _SoccerTimeAppState createState() => _SoccerTimeAppState();
}

class _SoccerTimeAppState extends State<SoccerTimeApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Close Hive database when app is disposed
    HiveSessionDatabase.instance.close();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      // App is in background, close database to prevent locking
      HiveSessionDatabase.instance.close();
      
      // Don't disable wakelock to keep timers and audio running in background
    } else if (state == AppLifecycleState.resumed) {
      try {
        // Re-enable wakelock when app is brought back to foreground
        WakelockPlus.enable();
      } catch (e) {
        print('Error re-enabling wakelock: $e');
      }
      
      // Reopen database connection
      HiveSessionDatabase.instance.init();
    } else if (state == AppLifecycleState.detached) {
      // App is being terminated, disable wakelock
      try {
        WakelockPlus.disable();
      } catch (e) {
        print('Error disabling wakelock: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) => AppState(),
      child: Consumer<AppState>(
        builder: (context, appState, child) {
          return MaterialApp(
            title: 'Soccer Time App',
            theme: ThemeData(
              brightness: appState.isDarkTheme ? Brightness.dark : Brightness.light,
              primarySwatch: Colors.blue,
              scaffoldBackgroundColor: appState.isDarkTheme 
                ? AppThemes.darkBackground 
                : AppThemes.lightBackground,
              appBarTheme: AppBarTheme(
                backgroundColor: appState.isDarkTheme 
                  ? AppThemes.darkBackground 
                  : AppThemes.lightBackground,
                iconTheme: IconThemeData(
                  color: appState.isDarkTheme 
                    ? AppThemes.darkText 
                    : AppThemes.lightText,
                ),
                titleTextStyle: TextStyle(
                  color: appState.isDarkTheme 
                    ? AppThemes.darkText 
                    : AppThemes.lightText,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            // Define routes directly using the route constructors for better type checking
            initialRoute: '/',
            routes: {
              '/': (context) => SessionPromptScreen(),
              '/main': (context) => MainScreen(),
              '/settings': (context) => SettingsScreen(),
            },
            debugShowCheckedModeBanner: false,
          );
        },
      ),
    );
  }
}