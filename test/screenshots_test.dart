// Renders phone-sized screenshots of the main screens with real fonts.
// Run: flutter test test/screenshots_test.dart --update-goldens
// Output: test/goldens/*.png
@Tags(['screenshots'])
library;

import 'dart:io';

import 'package:clientpro/app.dart';
import 'package:clientpro/app_services.dart';
import 'package:clientpro/data/prefs.dart';
import 'package:clientpro/data/sample_data.dart';
import 'package:clientpro/data/store.dart';
import 'package:clientpro/ui/screens/customers_screen.dart';
import 'package:clientpro/ui/screens/invoices_screen.dart';
import 'package:clientpro/ui/screens/reminders_screen.dart';
import 'package:clientpro/ui/screens/sync_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _font(String family, List<String> paths) async {
  final loader = FontLoader(family);
  for (final p in paths) {
    loader.addFont(Future.value(ByteData.sublistView(File(p).readAsBytesSync())));
  }
  await loader.load();
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('ar');
    await _font('Tajawal', ['assets/fonts/Tajawal-Regular.ttf', 'assets/fonts/Tajawal-Bold.ttf']);
    final flutterRoot = Platform.environment['FLUTTER_ROOT'] ?? '/opt/flutter';
    await _font('MaterialIcons', ['$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf']);
  });

  final pages = <String, Widget Function(AppStore)?>{
    '1-dashboard': null,
    '2-customer': (s) => CustomerDetailScreen(id: s.customers.all.first.id),
    '3-invoice': (s) => InvoiceDetailScreen(id: s.invoices.all.firstWhere((i) => i.payments.isNotEmpty).id),
    '4-sync': (s) => const SyncScreen(),
    '5-reminders': (s) => const RemindersScreen(),
  };

  for (final entry in pages.entries) {
    testWidgets(entry.key, (tester) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues({'onboarded': true});
      final store = AppStore(persist: false);
      loadSampleData(store);
      store.updateBusiness((b) => b.name = 'مؤسسة النجاح');
      final services = AppServices(store: store, prefs: await DevicePrefs.load());
      await tester.pumpWidget(ClientProApp(services: services));
      await tester.pumpAndSettle();
      if (entry.value != null) {
        tester.state<NavigatorState>(find.byType(Navigator).first).push(MaterialPageRoute<void>(builder: (_) => entry.value!(store)));
        await tester.pumpAndSettle();
      }
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/${entry.key}.png'));
    });
  }
}
