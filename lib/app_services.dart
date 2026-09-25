import 'dart:async';

import 'package:flutter/foundation.dart';

import 'data/prefs.dart';
import 'data/store.dart';
import 'services/drive_sync.dart';
import 'services/exporter.dart';
import 'services/format.dart';
import 'services/notifications.dart';

/// Wires the background jobs together: formatting settings, notification
/// rescheduling, Google Drive sync and the automatic monthly export.
class AppServices {
  AppServices({required this.store, required this.prefs}) : sync = DriveSync(store, prefs), exporter = Exporter(store);

  final AppStore store;
  final DevicePrefs prefs;
  final DriveSync sync;
  final Exporter exporter;

  Timer? _notifyDebounce;

  void start() {
    _applyFormatting();
    store.addListener(_onDataChanged);
    prefs.addListener(_onPrefsChanged);
    unawaited(_startAsync());
  }

  Future<void> _startAsync() async {
    await NotificationService.instance.init();
    await NotificationService.instance.rescheduleAll(store, prefs);
    await sync.init();
    await runMonthlyExport();
  }

  void _applyFormatting() {
    Fmt.currency = store.business.currency;
    Fmt.arabicDigits = prefs.arabicDigits;
  }

  void _onDataChanged() {
    _applyFormatting();
    _scheduleNotifications();
  }

  void _onPrefsChanged() {
    _applyFormatting();
    _scheduleNotifications();
  }

  void _scheduleNotifications() {
    _notifyDebounce?.cancel();
    _notifyDebounce = Timer(const Duration(seconds: 2), () {
      NotificationService.instance.rescheduleAll(store, prefs);
    });
  }

  /// App came back to the foreground.
  void onResume() {
    sync.onResume();
    unawaited(runMonthlyExport());
    _scheduleNotifications();
  }

  /// Exports last month to Excel once, uploads it to Drive and notifies.
  Future<void> runMonthlyExport() async {
    try {
      final file = await exporter.autoExportIfDue(prefs);
      if (file == null) return;
      var uploaded = false;
      if (prefs.uploadExportsToDrive && sync.connected) {
        uploaded = await sync.uploadExport(file);
      }
      await NotificationService.instance.showNow(
        'تم تصدير تقرير الشهر',
        uploaded ? 'تم حفظ ملف Excel ورفعه على Google Drive' : 'ملف Excel جاهز في المزامنة والنسخ الاحتياطي',
      );
    } catch (e) {
      debugPrint('Monthly export failed: $e');
    }
  }
}
