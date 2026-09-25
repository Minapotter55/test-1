import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/store.dart';
import '../../services/drive_sync.dart';
import '../../services/format.dart';
import '../widgets.dart';
import 'deals_screen.dart';
import 'expenses_screen.dart';
import 'products_screen.dart';
import 'reminders_screen.dart';
import 'reports_screen.dart';
import 'settings_screen.dart';
import 'sync_screen.dart';

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final sync = context.watch<DriveSync>();
    final openDeals = store.deals.all.where((d) => d.stage.isOpen).length;
    final lowStock = store.products.all.where((p) => p.isLowStock).length;

    Widget link(String title, IconData icon, Color color, Widget Function() page, {String? badge, String? subtitle}) =>
        ListTile(
          leading: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, color: Colors.white, size: 20),
          ),
          title: Text(title),
          subtitle: subtitle == null ? null : Text(subtitle),
          trailing: badge == null ? const Icon(Icons.chevron_left) : Badge(label: Text(badge)),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => page())),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('المزيد')),
      body: ListView(
        children: [
          Card(
            margin: const EdgeInsets.all(12),
            child: ListTile(
              leading: Avatar(name: store.business.name.isEmpty ? 'نشاطي' : store.business.name, size: 48),
              title: Text(
                store.business.name.isEmpty ? 'اسم نشاطك التجاري' : store.business.name,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: const Text('بيانات النشاط والإعدادات'),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
            ),
          ),
          const _Header('المبيعات'),
          link(
            'الصفقات والفرص',
            Icons.handshake,
            Colors.purple,
            () => const DealsScreen(),
            badge: openDeals > 0 ? Fmt.number(openDeals) : null,
          ),
          link(
            'المنتجات والخدمات',
            Icons.inventory_2,
            Colors.blue,
            () => const ProductsScreen(),
            badge: lowStock > 0 ? Fmt.number(lowStock) : null,
          ),
          const _Header('المالية'),
          link('المصروفات', Icons.account_balance_wallet, Colors.red, () => const ExpensesScreen()),
          link('التقارير', Icons.pie_chart, Colors.green, () => const ReportsScreen()),
          const _Header('البيانات والتنبيهات'),
          link(
            'المزامنة والنسخ الاحتياطي',
            Icons.cloud_sync,
            Colors.teal,
            () => const SyncScreen(),
            subtitle: sync.connected ? 'متصل بـ Google Drive' : 'Google Drive، تصدير Excel شهري، نسخة احتياطية',
          ),
          link('التذكيرات والإشعارات', Icons.notifications_active, Colors.orange, () => const RemindersScreen()),
          link('الإعدادات', Icons.settings, Colors.grey, () => const SettingsScreen()),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
    child: Text(
      text,
      style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold),
    ),
  );
}
