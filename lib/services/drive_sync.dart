import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis_auth/googleapis_auth.dart' show AuthClient;

import '../config.dart';
import '../data/prefs.dart';
import '../data/store.dart';

/// Keeps the data in sync across phones (Android and iPhone) through the
/// user's own Google Drive, and uploads monthly exports there.
///
/// Sync = download the shared file, merge record-by-record (newest edit wins,
/// deletions are remembered), save locally, upload the merged result.
class DriveSync extends ChangeNotifier {
  DriveSync(this.store, this.prefs);

  final AppStore store;
  final DevicePrefs prefs;

  static const _scopes = [drive.DriveApi.driveFileScope];

  GoogleSignInAccount? _account;
  bool syncing = false;
  String? error;
  int _syncedRevision = -1;
  Timer? _debounce;
  bool _initialized = false;

  bool get isConfigured => Platform.isIOS ? googleIosClientId.isNotEmpty : googleWebClientId.isNotEmpty;
  bool get connected => _account != null;
  String get email => _account?.email ?? prefs.driveEmail;

  Future<void> init() async {
    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS) || !isConfigured) return;
    try {
      await GoogleSignIn.instance.initialize(
        clientId: Platform.isIOS ? googleIosClientId : null,
        serverClientId: googleWebClientId.isEmpty ? null : googleWebClientId,
      );
      _initialized = true;
      GoogleSignIn.instance.authenticationEvents.listen((event) {
        _account = switch (event) {
          GoogleSignInAuthenticationEventSignIn() => event.user,
          GoogleSignInAuthenticationEventSignOut() => null,
        };
        notifyListeners();
      }, onError: (Object e) => debugPrint('Google sign-in event error: $e'));

      if (prefs.driveSyncEnabled) {
        _account = await GoogleSignIn.instance.attemptLightweightAuthentication();
        notifyListeners();
        if (_account != null) unawaited(syncNow());
      }
    } catch (e) {
      debugPrint('Google sign-in init failed: $e');
    }
    store.addListener(_onStoreChanged);
  }

  void _onStoreChanged() {
    if (!connected || !prefs.driveSyncEnabled || store.revision == _syncedRevision) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 20), () => syncNow());
  }

  /// Called when the app returns to the foreground: pull what other devices changed.
  void onResume() {
    if (connected && prefs.driveSyncEnabled) unawaited(syncNow());
  }

  Future<bool> connect() async {
    if (!_initialized) {
      error = 'لم يتم إعداد Google Drive في هذه النسخة من التطبيق';
      notifyListeners();
      return false;
    }
    try {
      error = null;
      _account = await GoogleSignIn.instance.authenticate(scopeHint: _scopes);
      await _account!.authorizationClient.authorizeScopes(_scopes);
      prefs.driveSyncEnabled = true;
      prefs.driveEmail = _account!.email;
      notifyListeners();
      return await syncNow();
    } on GoogleSignInException catch (e) {
      error = e.code == GoogleSignInExceptionCode.canceled
          ? null
          : 'تعذّر تسجيل الدخول: ${e.description ?? e.code.name}';
      notifyListeners();
      return false;
    } catch (e) {
      error = 'تعذّر تسجيل الدخول: $e';
      notifyListeners();
      return false;
    }
  }

  Future<void> disconnect() async {
    _debounce?.cancel();
    try {
      await GoogleSignIn.instance.signOut();
    } catch (_) {}
    _account = null;
    prefs.driveSyncEnabled = false;
    prefs.driveEmail = '';
    notifyListeners();
  }

  Future<AuthClient?> _client({bool interactive = false}) async {
    final account = _account;
    if (account == null) return null;
    var authz = await account.authorizationClient.authorizationForScopes(_scopes);
    if (authz == null && interactive) {
      authz = await account.authorizationClient.authorizeScopes(_scopes);
    }
    return authz?.authClient(scopes: _scopes);
  }

  Future<String> _folder(drive.DriveApi api, String name, {String? parent}) async {
    final escaped = name.replaceAll("'", r"\'");
    final q =
        "name = '$escaped' and mimeType = 'application/vnd.google-apps.folder' and trashed = false"
        "${parent == null ? '' : " and '$parent' in parents"}";
    final found = await api.files.list(q: q, spaces: 'drive', $fields: 'files(id)');
    final existing = found.files;
    if (existing != null && existing.isNotEmpty && existing.first.id != null) return existing.first.id!;
    final created = await api.files.create(
      drive.File()
        ..name = name
        ..mimeType = 'application/vnd.google-apps.folder'
        ..parents = parent == null ? null : [parent],
      $fields: 'id',
    );
    return created.id!;
  }

  Future<drive.File?> _findFile(drive.DriveApi api, String folderId, String name) async {
    final res = await api.files.list(
      q: "name = '$name' and '$folderId' in parents and trashed = false",
      spaces: 'drive',
      $fields: 'files(id, modifiedTime)',
    );
    final files = res.files;
    return (files == null || files.isEmpty) ? null : files.first;
  }

  Future<bool> syncNow({bool interactive = false}) async {
    if (syncing) return false;
    syncing = true;
    error = null;
    notifyListeners();
    try {
      final client = await _client(interactive: interactive);
      if (client == null) {
        error = 'يلزم تسجيل الدخول إلى Google مرة أخرى';
        return false;
      }
      try {
        final api = drive.DriveApi(client);
        final folderId = await _folder(api, driveFolderName);
        final existing = await _findFile(api, folderId, driveSyncFileName);

        if (existing?.id != null) {
          final media =
              await api.files.get(existing!.id!, downloadOptions: drive.DownloadOptions.fullMedia) as drive.Media;
          final bytes = <int>[];
          await for (final chunk in media.stream) {
            bytes.addAll(chunk);
          }
          final remote = jsonDecode(utf8.decode(bytes));
          if (AppStore.isValidSnapshot(remote)) store.mergeFrom(Map<String, dynamic>.from(remote as Map));
        }

        final revisionAtUpload = store.revision;
        final payload = utf8.encode(jsonEncode(store.snapshot()));
        final media = drive.Media(Stream.value(payload), payload.length, contentType: 'application/json');
        if (existing?.id != null) {
          await api.files.update(drive.File(), existing!.id!, uploadMedia: media);
        } else {
          await api.files.create(
            drive.File()
              ..name = driveSyncFileName
              ..parents = [folderId],
            uploadMedia: media,
          );
        }
        _syncedRevision = revisionAtUpload;
        prefs.lastSyncAt = DateTime.now().millisecondsSinceEpoch;
        return true;
      } finally {
        client.close();
      }
    } catch (e) {
      debugPrint('Drive sync failed: $e');
      error = 'فشلت المزامنة، تأكد من الاتصال بالإنترنت';
      return false;
    } finally {
      syncing = false;
      notifyListeners();
    }
  }

  /// Uploads a file (e.g. the monthly Excel export) to ClientPro/تقارير شهرية.
  Future<bool> uploadExport(File file) async {
    try {
      final client = await _client();
      if (client == null) return false;
      try {
        final api = drive.DriveApi(client);
        final root = await _folder(api, driveFolderName);
        final folder = await _folder(api, driveExportsFolderName, parent: root);
        final name = file.uri.pathSegments.last;
        final length = await file.length();
        final media = drive.Media(file.openRead(), length);
        final existing = await _findFile(api, folder, name);
        if (existing?.id != null) {
          await api.files.update(drive.File(), existing!.id!, uploadMedia: media);
        } else {
          await api.files.create(
            drive.File()
              ..name = name
              ..parents = [folder],
            uploadMedia: media,
          );
        }
        return true;
      } finally {
        client.close();
      }
    } catch (e) {
      debugPrint('Drive upload failed: $e');
      return false;
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    store.removeListener(_onStoreChanged);
    super.dispose();
  }
}
