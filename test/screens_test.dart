import 'package:clientpro/app.dart';
import 'package:clientpro/app_services.dart';
import 'package:clientpro/data/prefs.dart';
import 'package:clientpro/data/sample_data.dart';
import 'package:clientpro/data/store.dart';
import 'package:clientpro/ui/screens/customers_screen.dart';
import 'package:clientpro/ui/screens/deals_screen.dart';
import 'package:clientpro/ui/screens/expenses_screen.dart';
import 'package:clientpro/ui/screens/invoices_screen.dart';
import 'package:clientpro/ui/screens/products_screen.dart';
import 'package:clientpro/ui/screens/reminders_screen.dart';
import 'package:clientpro/ui/screens/reports_screen.dart';
import 'package:clientpro/ui/screens/settings_screen.dart';
import 'package:clientpro/ui/screens/sync_screen.dart';
import 'package:clientpro/ui/screens/tasks_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<AppServices> _services({bool onboarded = true, bool sample = true}) async {
  SharedPreferences.setMockInitialValues({'onboarded': onboarded});
  final prefs = await DevicePrefs.load();
  final store = AppStore(persist: false);
  if (sample) loadSampleData(store);
  return AppServices(store: store, prefs: prefs);
}

Future<void> _loadFonts() async {
  final tajawal = FontLoader('Tajawal')
    ..addFont(rootBundle.load('assets/fonts/Tajawal-Regular.ttf'))
    ..addFont(rootBundle.load('assets/fonts/Tajawal-Bold.ttf'));
  await tajawal.load();
}

/// iPhone 13/14/15 (390 wide) by default; small Android phones are 360 wide.
void _phoneSize(WidgetTester tester, {double width = 390, double height = 844}) {
  tester.view.physicalSize = Size(width * 3, height * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('ar');
    await _loadFonts();
  });

  testWidgets('onboarding shows for a new user', (tester) async {
    final s = await _services(onboarded: false, sample: false);
    await tester.pumpWidget(ClientProApp(services: s));
    await tester.pumpAndSettle();
    expect(find.text('أهلاً بك في ClientPro'), findsOneWidget);
  });

  testWidgets('all tabs render with sample data', (tester) async {
    _phoneSize(tester);

    final s = await _services();
    await tester.pumpWidget(ClientProApp(services: s));
    await tester.pumpAndSettle();
    expect(find.text('لوحة التحكم'), findsOneWidget);

    for (final tab in ['العملاء', 'الفواتير', 'المهام', 'المزيد', 'الرئيسية']) {
      await tester.tap(find.text(tab).last);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: tab);
    }
  });

  final screens = <String, Widget Function(AppStore)>{
    'customer detail': (st) => CustomerDetailScreen(id: st.customers.all.first.id),
    'customer form': (st) => CustomerFormScreen(customer: st.customers.all.first),
    'invoice detail': (st) => InvoiceDetailScreen(id: st.invoices.all.first.id),
    'invoice form': (st) => InvoiceFormScreen(invoice: st.invoices.all.first),
    'new invoice': (st) => const InvoiceFormScreen(),
    'task form': (st) => TaskFormScreen(task: st.tasks.all.first),
    'deals': (st) => const DealsScreen(),
    'deal form': (st) => DealFormScreen(deal: st.deals.all.first),
    'products': (st) => const ProductsScreen(),
    'product form': (st) => ProductFormScreen(product: st.products.all.first),
    'expenses': (st) => const ExpensesScreen(),
    'expense form': (st) => ExpenseFormScreen(expense: st.expenses.all.first),
    'reports': (st) => const ReportsScreen(),
    'settings': (st) => const SettingsScreen(),
    'sync': (st) => const SyncScreen(),
    'reminders': (st) => const RemindersScreen(),
    'tasks': (st) => const TasksScreen(),
  };

  for (final entry in screens.entries) {
    for (final width in [390.0, 360.0]) {
      testWidgets('screen renders at ${width.toInt()}pt: ${entry.key}', (tester) async {
        _phoneSize(tester, width: width, height: width == 360 ? 740 : 844);
        final s = await _services();
        await tester.pumpWidget(ClientProApp(services: s));
        await tester.pumpAndSettle();
        tester
            .state<NavigatorState>(find.byType(Navigator).first)
            .push(MaterialPageRoute<void>(builder: (_) => entry.value(s.store)));
        await tester.pumpAndSettle();
      });
    }
  }

  testWidgets('adding a customer through the form saves it', (tester) async {
    final s = await _services(sample: false);
    await tester.pumpWidget(ClientProApp(services: s));
    await tester.pumpAndSettle();
    final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
    nav.push(MaterialPageRoute<void>(builder: (_) => const CustomerFormScreen()));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'اسم العميل *'), 'عميل جديد');
    await tester.enterText(find.widgetWithText(TextField, 'رقم الهاتف'), '01000000000');
    await tester.tap(find.text('حفظ').first);
    await tester.pumpAndSettle();

    expect(s.store.customers.all.single.name, 'عميل جديد');
    expect(s.store.customers.all.single.phone, '01000000000');
  });
}
