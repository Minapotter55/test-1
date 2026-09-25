import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// Settings that belong to this phone only (not synced).
class DevicePrefs extends ChangeNotifier {
  DevicePrefs._(this._p);

  final SharedPreferences _p;

  static Future<DevicePrefs> load() async => DevicePrefs._(await SharedPreferences.getInstance());

  static const accents = <Color>[
    Color(0xFF2563EB),
    Color(0xFF4F46E5),
    Color(0xFF7C3AED),
    Color(0xFFDB2777),
    Color(0xFFDC2626),
    Color(0xFFEA580C),
    Color(0xFF16A34A),
    Color(0xFF0D9488),
    Color(0xFF8D6E63),
  ];

  bool _b(String k, bool d) => _p.getBool(k) ?? d;
  int _i(String k, int d) => _p.getInt(k) ?? d;

  void _set(String k, Object v) {
    if (v is bool) _p.setBool(k, v);
    if (v is int) _p.setInt(k, v);
    if (v is String) _p.setString(k, v);
    notifyListeners();
  }

  String get deviceId {
    var id = _p.getString('deviceId');
    if (id == null) {
      id = const Uuid().v4();
      _p.setString('deviceId', id);
    }
    return id;
  }

  bool get onboarded => _b('onboarded', false);
  set onboarded(bool v) => _set('onboarded', v);

  ThemeMode get themeMode => ThemeMode.values[_i('themeMode', 0).clamp(0, 2)];
  set themeMode(ThemeMode v) => _set('themeMode', v.index);

  int get accentIndex => _i('accent', 0).clamp(0, accents.length - 1);
  set accentIndex(int v) => _set('accent', v);
  Color get accent => accents[accentIndex];

  bool get arabicDigits => _b('arabicDigits', false);
  set arabicDigits(bool v) => _set('arabicDigits', v);

  bool get appLock => _b('appLock', false);
  set appLock(bool v) => _set('appLock', v);

  // Notifications
  bool get notifyTasks => _b('notifyTasks', true);
  set notifyTasks(bool v) => _set('notifyTasks', v);

  bool get notifyInvoices => _b('notifyInvoices', true);
  set notifyInvoices(bool v) => _set('notifyInvoices', v);

  bool get notifyBirthdays => _b('notifyBirthdays', true);
  set notifyBirthdays(bool v) => _set('notifyBirthdays', v);

  bool get dailyAgenda => _b('dailyAgenda', true);
  set dailyAgenda(bool v) => _set('dailyAgenda', v);

  /// Minutes after midnight.
  int get dailyAgendaTime => _i('dailyAgendaTime', 9 * 60);
  set dailyAgendaTime(int v) => _set('dailyAgendaTime', v);

  bool get monthlyExportReminder => _b('monthlyExportReminder', true);
  set monthlyExportReminder(bool v) => _set('monthlyExportReminder', v);

  // Monthly export
  bool get autoMonthlyExport => _b('autoMonthlyExport', true);
  set autoMonthlyExport(bool v) => _set('autoMonthlyExport', v);

  bool get uploadExportsToDrive => _b('uploadExportsToDrive', true);
  set uploadExportsToDrive(bool v) => _set('uploadExportsToDrive', v);

  /// "2026-08" of the last month exported automatically.
  String get lastExportedMonth => _p.getString('lastExportedMonth') ?? '';
  set lastExportedMonth(String v) => _set('lastExportedMonth', v);

  // Google Drive sync
  bool get driveSyncEnabled => _b('driveSync', false);
  set driveSyncEnabled(bool v) => _set('driveSync', v);

  int get lastSyncAt => _i('lastSyncAt', 0);
  set lastSyncAt(int v) => _set('lastSyncAt', v);

  String get driveEmail => _p.getString('driveEmail') ?? '';
  set driveEmail(String v) => _set('driveEmail', v);
}
