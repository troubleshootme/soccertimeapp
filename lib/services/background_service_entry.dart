import 'dart:async';
import 'dart:ui';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Background service entry point
@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  // Only available for flutter 3.0.0 and later
  DartPluginRegistrant.ensureInitialized();

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  // Initialize notifications
  await _initializeNotifications(flutterLocalNotificationsPlugin);

  // Service data
  int matchTime = 0;
  int period = 1;
  bool isPaused = false;
  bool isAlerting = false;
  Timer? updateTimer;
  Timer? alertTimer;

  // Listen for service data updates
  service.on('updateTimer').listen((event) {
    if (event != null) {
      matchTime = event['matchTime'] ?? matchTime;
      period = event['period'] ?? period;
      isPaused = event['isPaused'] ?? isPaused;
      _updateNotification(flutterLocalNotificationsPlugin, matchTime, period, isPaused);
    }
  });

  service.on('setAsForeground').listen((event) {
    if (service is AndroidServiceInstance) {
      service.setAsForegroundService();
    }
  });

  service.on('startAlert').listen((event) {
    if (!isAlerting) {
      isAlerting = true;
      _startVibrationAlert(flutterLocalNotificationsPlugin, period);
    }
  });

  service.on('stopAlert').listen((event) {
    isAlerting = false;
    alertTimer?.cancel();
    flutterLocalNotificationsPlugin.cancel(2);
  });

  service.on('stopService').listen((event) {
    service.stopSelf();
  });

  // Start the foreground service
  if (service is AndroidServiceInstance) {
    service.setForegroundNotificationInfo(
      title: "Soccer Timer - Period $period",
      content: "00:00 - Running",
    );
  }

  // Update notification every second
  updateTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
    if (service is AndroidServiceInstance) {
      if (await service.isForegroundService()) {
        _updateNotification(flutterLocalNotificationsPlugin, matchTime, period, isPaused);
      }
    }
  });
}

Future<void> _initializeNotifications(FlutterLocalNotificationsPlugin plugin) async {
  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');

  const InitializationSettings initializationSettings =
      InitializationSettings(android: initializationSettingsAndroid);

  await plugin.initialize(initializationSettings);

  // Create notification channels
  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'soccer_timer_channel',
    'Soccer Timer Service',
    description: 'Keeps the soccer timer running in the background',
    importance: Importance.low,
  );

  const AndroidNotificationChannel alertChannel = AndroidNotificationChannel(
    'soccer_timer_alert',
    'Timer Alerts',
    description: 'Period end and timer alerts',
    importance: Importance.high,
  );

  await plugin
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);

  await plugin
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(alertChannel);
}

void _updateNotification(
  FlutterLocalNotificationsPlugin plugin,
  int matchTime,
  int period,
  bool isPaused,
) {
  final minutes = matchTime ~/ 60;
  final seconds = matchTime % 60;
  final timeText = '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  final statusText = isPaused ? 'Paused' : 'Running';

  plugin.show(
    1,
    'Soccer Timer - Period $period',
    '$timeText - $statusText',
    const NotificationDetails(
      android: AndroidNotificationDetails(
        'soccer_timer_channel',
        'Soccer Timer Service',
        icon: '@mipmap/ic_launcher',
        ongoing: true,
        priority: Priority.low,
        importance: Importance.low,
        category: AndroidNotificationCategory.service,
        visibility: NotificationVisibility.public,
      ),
    ),
  );
}

void _startVibrationAlert(FlutterLocalNotificationsPlugin plugin, int period) {
  plugin.show(
    2,
    'Period Ending Soon!',
    'Period $period will end in 5 seconds',
    const NotificationDetails(
      android: AndroidNotificationDetails(
        'soccer_timer_alert',
        'Timer Alerts',
        icon: '@mipmap/ic_launcher',
        ongoing: true,
        priority: Priority.high,
        importance: Importance.high,
        category: AndroidNotificationCategory.alarm,
        visibility: NotificationVisibility.public,
      ),
    ),
  );
}
