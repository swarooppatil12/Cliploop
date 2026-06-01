import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../core/navigation/app_navigator.dart';
import '../core/navigation/app_routes.dart';

class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  factory NotificationService() => instance;

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  bool _permissionsRequested = false;

  static const String method1CompletePayload = 'method1_complete';
  static const String method2CompletePayload = 'method2_complete';

  static const String _processingChannelId = 'cliploops_processing';
  static const String _processingChannelName = 'Swaroop App Processing';
  static const String _processingChannelDescription =
      'Processing status updates for Swaroop App';

  static const String _sharingChannelId = 'cliploops_sharing';
  static const String _sharingChannelName = 'Swaroop App Sharing';
  static const String _sharingChannelDescription =
      'Alerts when a new audio file is shared to Swaroop App';

  static const int _progressNotificationId = 3;
  static const int _sharedFileNotificationId = 4;

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationResponse,
    );

    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _processingChannelId,
        _processingChannelName,
        description: _processingChannelDescription,
        importance: Importance.high,
      ),
    );

    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _sharingChannelId,
        _sharingChannelName,
        description: _sharingChannelDescription,
        importance: Importance.high,
      ),
    );

    _initialized = true;
  }

  Future<void> _requestPermissionsIfNeeded() async {
    if (_permissionsRequested) {
      return;
    }
    _permissionsRequested = true;

    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.requestNotificationsPermission();

    final iosPlugin = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    await iosPlugin?.requestPermissions(
      alert: true,
      badge: true,
      sound: true,
    );
  }

  void _onNotificationResponse(NotificationResponse response) {
    switch (response.payload) {
      case 'shared_file':
        AppNavigator.openHome();
      case method1CompletePayload:
        AppNavigator.openRoute(AppRoutes.spleeter);
      case method2CompletePayload:
        AppNavigator.openRoute(AppRoutes.whisper);
    }
  }

  Future<void> startForegroundProcessing(String fileName, String step) async {
    await initialize();
    await _requestPermissionsIfNeeded();
    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

    final androidDetails = AndroidNotificationDetails(
      _processingChannelId,
      _processingChannelName,
      channelDescription: _processingChannelDescription,
      importance: Importance.high,
      priority: Priority.high,
      ongoing: true,
      showProgress: true,
      maxProgress: 100,
      progress: 0,
      onlyAlertOnce: true,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: false,
    );

    if (androidPlugin == null) {
      await _plugin.show(
        _progressNotificationId,
        'Processing $fileName',
        step,
        const NotificationDetails(iOS: iosDetails),
      );
      return;
    }

    await androidPlugin.startForegroundService(
      _progressNotificationId,
      'Processing $fileName',
      step,
      notificationDetails: androidDetails,
      foregroundServiceTypes: {
        AndroidServiceForegroundType.foregroundServiceTypeDataSync,
      },
    );
  }

  Future<void> stopForegroundProcessing() async {
    await initialize();
    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.stopForegroundService();
  }

  void showProcessingComplete(
    String fileName,
    String method, {
    String? routeName,
  }) {
    stopForegroundProcessing();
    _show(
      id: 1,
      title: 'Processing complete',
      body: '$fileName finished with $method.',
      payload: routeName,
    );
  }

  void showProcessingFailed(String fileName, String reason) {
    stopForegroundProcessing();
    _show(
      id: 2,
      title: 'Processing failed',
      body: '$fileName could not be processed. $reason',
    );
  }

  void showProgress(String fileName, int percent) {
    final clamped = percent.clamp(0, 100);
    _show(
      id: _progressNotificationId,
      title: 'Processing $fileName',
      body: 'Progress: $clamped%',
      ongoing: clamped < 100,
      progress: clamped,
    );
  }

  void showSharedFileReceived(String fileName) {
    _show(
      id: _sharedFileNotificationId,
      title: 'New music file received',
      body: '$fileName. Tap to analyse.',
      channelId: _sharingChannelId,
      channelName: _sharingChannelName,
      channelDescription: _sharingChannelDescription,
      payload: 'shared_file',
    );
  }

  void _show({
    required int id,
    required String title,
    required String body,
    bool ongoing = false,
    int? progress,
    String channelId = _processingChannelId,
    String channelName = _processingChannelName,
    String channelDescription = _processingChannelDescription,
    String? payload,
  }) {
    initialize().then((_) async {
      await _requestPermissionsIfNeeded();

      final androidDetails = AndroidNotificationDetails(
        channelId,
        channelName,
        channelDescription: channelDescription,
        importance: Importance.high,
        priority: Priority.high,
        ongoing: ongoing,
        showProgress: progress != null,
        maxProgress: 100,
        progress: progress ?? 0,
        onlyAlertOnce: true,
      );

      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      final details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      await _plugin.show(id, title, body, details, payload: payload);
    });
  }
}
