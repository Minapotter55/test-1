import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app.dart';
import 'app_services.dart';
import 'data/prefs.dart';
import 'data/store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ar');
  final prefs = await DevicePrefs.load();
  final store = AppStore();
  await store.load();
  final services = AppServices(store: store, prefs: prefs);
  runApp(ClientProApp(services: services));
  services.start();
}
