import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/car_listing.dart';
import 'storage_service.dart';

/// REFACTORED: Individual Listing Notification Architecture.
class NotificationService {
  NotificationService._();
  static final instance = NotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  final _storage = StorageService();

  Future<void> initialize({bool requestPermission = false}) async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: android);
    
    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) async {
        final String? payload = response.payload;
        if (payload != null && payload.isNotEmpty) {
          final uri = Uri.tryParse(payload);
          if (uri != null) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          }
        }
      },
    );

    final platform = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (platform != null) {
      if (requestPermission) {
        await platform.requestNotificationsPermission();
      }
      await platform.getNotificationChannels();
    }
  }

  /// Fires an individual push notification for a single car record.
  /// Returns true if successfully displayed.
  Future<bool> notifyNewAd(CarListing ad) async {
    debugPrint('[NOTIFICATION_TRACE] ENTRY notifyNewAd adId=${ad.id}');
    try {
      final platform = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      if (platform != null) {
        debugPrint('[NOTIFICATION_TRACE] BEFORE areNotificationsEnabled adId=${ad.id}');
        final notificationsEnabled = await platform.areNotificationsEnabled() ?? false;
        debugPrint('[NOTIFICATION_TRACE] AFTER areNotificationsEnabled adId=${ad.id} enabled=$notificationsEnabled');
        if (!notificationsEnabled) {
          debugPrint('[NOTIFICATION_TRACE] EXIT notifyNewAd adId=${ad.id} result=false (disabled)');
          return false;
        }
      }

      final String title = ad.title; 
      final String mileage = (ad.mileage.isEmpty || ad.mileage == '0 km') ? '/' : ad.mileage;
      final String body = '${ad.price} • ${ad.year} • ${ad.fuel} • $mileage';

      final bigStyle = BigTextStyleInformation(
        body,
        contentTitle: title,
        summaryText: 'Novo vozilo na Avto.net',
      );

      final androidDetails = AndroidNotificationDetails(
        'avtonet_finder_channel',
        'AvtoNet Skener Alerts',
        channelDescription: 'Individual vehicle tracking update notifications',
        importance: Importance.max,
        priority: Priority.high,
        showWhen: true,
        styleInformation: bigStyle,
        ticker: 'ticker',
      );

      debugPrint('[NOTIFICATION_TRACE] BEFORE _plugin.show adId=${ad.id}');
      await _plugin.show(
        ad.id.hashCode,
        title,
        body,
        NotificationDetails(android: androidDetails),
        payload: ad.link,
      );
      debugPrint('[NOTIFICATION_TRACE] AFTER _plugin.show adId=${ad.id}');

      debugPrint('[NOTIFICATION_TRACE] BEFORE recordNotificationSent adId=${ad.id}');
      await _storage.recordNotificationSent(DateTime.now());
      debugPrint('[NOTIFICATION_TRACE] AFTER recordNotificationSent adId=${ad.id}');

      debugPrint('[NOTIFICATION_TRACE] EXIT notifyNewAd adId=${ad.id} result=true');
      return true;
    } catch (e, stack) {
      debugPrint('[NOTIFICATION_TRACE] ERROR notifyNewAd adId=${ad.id}: $e');
      debugPrint('[NOTIFICATION] [ERROR] Send failed id=${ad.id}: $e');
      if (stack != null) debugPrint(stack.toString());
      return false;
    }
  }

  /// Silent internal error notification for debugging.
  Future<void> notifyError(String error) async {
    const androidDetails = AndroidNotificationDetails(
      'avtonet_errors',
      'Sistemske Napake',
      importance: Importance.low,
      priority: Priority.low,
    );
    await _plugin.show(
      9999, 
      'Napaka pri skeniranju', 
      error, 
      const NotificationDetails(android: androidDetails),
    );
  }

  @Deprecated('Use notifyNewAd instead')
  Future<void> showNewMatchesNotification({
    int newCount = 0, 
    bool offlineCatchUp = false, 
    String? error,
  }) async {
    if (error != null) await notifyError(error);
  }
}
