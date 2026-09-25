import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/prefs.dart';
import '../../data/sample_data.dart';
import '../../data/store.dart';
import '../../services/format.dart';
import '../../services/notifications.dart';
import 'customers_screen.dart';
import 'dashboard_screen.dart';
import 'invoices_screen.dart';
import 'more_screen.dart';
import 'tasks_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final prefs = context.watch<DevicePrefs>();
    if (!prefs.onboarded) return const OnboardingScreen();

    final tasks = context.watch<AppStore>().tasks.all;
    final dueTasks = tasks.where((t) => !t.isDone && (t.isOverdue || t.isDueToday)).length;

    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          DashboardScreen(onOpenTab: (i) => setState(() => _index = i)),
          const CustomersScreen(),
          const InvoicesScreen(),
          const TasksScreen(),
          const MoreScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'الرئيسية',
          ),
          const NavigationDestination(
            icon: Icon(Icons.people_outline),
            selectedIcon: Icon(Icons.people),
            label: 'العملاء',
          ),
          const NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long),
            label: 'الفواتير',
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: dueTasks > 0,
              label: Text(Fmt.number(dueTasks)),
              child: const Icon(Icons.task_alt_outlined),
            ),
            selectedIcon: const Icon(Icons.task_alt),
            label: 'المهام',
          ),
          const NavigationDestination(icon: Icon(Icons.menu), label: 'المزيد'),
        ],
      ),
    );
  }
}

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _name = TextEditingController();
  String _currency = 'EGP';

  static const _features = [
    (Icons.people, 'إدارة العملاء', 'ملف كامل لكل عميل مع سجل التواصل والحقول المخصصة'),
    (Icons.receipt_long, 'فواتير ومدفوعات', 'فواتير PDF بشعارك ومتابعة التحصيل والتذكير على واتساب'),
    (Icons.insights, 'داشبورد وتقارير', 'الإيرادات والمصروفات والأرباح وأفضل العملاء'),
    (Icons.notifications_active, 'تذكيرات وإشعارات', 'مهام متكررة، مواعيد الفواتير، أعياد ميلاد العملاء'),
    (Icons.cloud_sync, 'مزامنة ونسخ احتياطي', 'Google Drive بين الأندرويد والآيفون وتقرير Excel كل شهر'),
  ];

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _finish({required bool sample}) async {
    final store = context.read<AppStore>();
    final prefs = context.read<DevicePrefs>();
    store.updateBusiness((b) {
      b.name = _name.text.trim();
      b.currency = _currency;
    });
    if (sample) loadSampleData(store);
    await NotificationService.instance.requestPermission();
    prefs.onboarded = true;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const SizedBox(height: 12),
            Icon(Icons.groups_2, size: 72, color: theme.colorScheme.primary),
            const SizedBox(height: 12),
            Text(
              'أهلاً بك في ClientPro',
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              'كل ما تحتاجه لإدارة عملائك ومبيعاتك في مكان واحد',
              textAlign: TextAlign.center,
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            Card(
              child: Column(
                children: [
                  for (final f in _features)
                    ListTile(
                      leading: Icon(f.$1, color: theme.colorScheme.primary),
                      title: Text(f.$2, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text(f.$3),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'اسم نشاطك التجاري'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _currency,
              decoration: const InputDecoration(labelText: 'العملة'),
              items: [
                for (final c in currencies) DropdownMenuItem(value: c.code, child: Text('${c.name} (${c.code})')),
              ],
              onChanged: (v) => setState(() => _currency = v ?? 'EGP'),
            ),
            const SizedBox(height: 20),
            FilledButton(onPressed: () => _finish(sample: false), child: const Text('ابدأ الآن')),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () => _finish(sample: true),
              child: const Text('ابدأ ببيانات تجريبية للتعرف على التطبيق'),
            ),
          ],
        ),
      ),
    );
  }
}
