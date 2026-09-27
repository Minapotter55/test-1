import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/store.dart';
import '../../models/models.dart';
import '../widgets.dart';
import 'products_screen.dart';

/// "تخصيص الخانات": the user's own lists that appear as choices across the app.
class CustomizeScreen extends StatelessWidget {
  const CustomizeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final b = store.business;
    final services = store.products.all.where((p) => p.isActive).map((p) => p.name).toList()..sort();

    return Scaffold(
      appBar: AppBar(title: const Text('تخصيص الخانات')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Card(
            color: Theme.of(context).colorScheme.primaryContainer,
            child: const Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                'هنا بتحدد القوائم والخانات اللي هتظهرلك وأنت بتسجل العملاء والمصروفات. '
                'اكتب بالظبط اللي بتستخدمه في شغلك، وأي حاجة تضيفها هنا هتلاقيها اختيار جاهز في كل مكان.',
              ),
            ),
          ),
          _ListEditor(
            title: 'أنواع العملاء (القطاع)',
            subtitle: 'تظهر في خانة "القطاع" في بيانات العميل',
            icon: Icons.local_hospital,
            items: b.sectors,
            hint: 'مثال: مستشفى، معمل تحاليل، عيادة أسنان',
            onChanged: (list) => store.updateBusiness((b) => b.sectors = list),
          ),
          _ListEditor(
            title: 'خانات إضافية لكل عميل',
            subtitle: 'خانات فاضية بتظهر في ملف كل عميل وتملاها بنفسك',
            icon: Icons.dynamic_form,
            items: b.clientFieldTemplates,
            hint: 'مثال: رقم التعاقد، اسم المدير المالي، عدد الفروع',
            onChanged: (list) => store.updateBusiness((b) => b.clientFieldTemplates = list),
          ),
          _ListEditor(
            title: 'أنواع المصروفات الخاصة بيك',
            subtitle: 'بتظهر جنب الأنواع الأساسية لما تسجل مصروف',
            icon: Icons.label,
            items: b.expenseCategories,
            hint: 'مثال: طباعة، مواصلات للعميل، تصوير',
            onChanged: (list) => store.updateBusiness((b) => b.expenseCategories = list),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.medical_services),
              title: const Text('الخدمات والباقات اللي بتقدمها'),
              subtitle: Text(
                services.isEmpty ? 'لسه ما ضفتش خدمات، اضغط هنا وضيف خدماتك وأسعارها' : services.join('، '),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: const Icon(Icons.chevron_left),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProductsScreen())),
            ),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () async {
              if (await confirm(
                context,
                'استرجاع القوائم الأساسية؟',
                'هترجع قائمة القطاعات والخانات الإضافية زي ما كانت.',
                action: 'استرجاع',
                destructive: false,
              )) {
                store.updateBusiness((b) {
                  b.sectors = [...BusinessSettings.defaultSectors];
                  b.clientFieldTemplates = [...BusinessSettings.defaultClientFields];
                });
              }
            },
            icon: const Icon(Icons.restore),
            label: const Text('استرجاع القوائم الأساسية'),
          ),
        ],
      ),
    );
  }
}

class _ListEditor extends StatelessWidget {
  const _ListEditor({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.items,
    required this.hint,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final List<String> items;
  final String hint;
  final ValueChanged<List<String>> onChanged;

  Future<void> _add(BuildContext context) async {
    final v = await promptText(context, title, hint: hint);
    if (v == null || v.isEmpty || items.contains(v)) return;
    onChanged([...items, v]);
  }

  Future<void> _edit(BuildContext context, String old) async {
    final v = await promptText(context, 'تعديل', initial: old);
    if (v == null || v.isEmpty || v == old) return;
    onChanged([for (final i in items) i == old ? v : i]);
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            Text(subtitle, style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final item in items)
                  InputChip(
                    label: Text(item),
                    onPressed: () => _edit(context, item),
                    onDeleted: () => onChanged([...items]..remove(item)),
                  ),
                ActionChip(
                  avatar: const Icon(Icons.add, size: 16),
                  label: const Text('إضافة'),
                  onPressed: () => _add(context),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
