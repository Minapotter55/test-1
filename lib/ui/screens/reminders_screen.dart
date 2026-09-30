import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/prefs.dart';
import '../../data/store.dart';
import '../../services/format.dart';
import '../../services/notifications.dart';
import '../widgets.dart';
import 'tasks_screen.dart';

String _everyLabel(int days) => switch (days) {
  1 => 'كل يوم',
  2 => 'كل يومين',
  7 => 'كل أسبوع',
  _ => 'كل ${Fmt.number(days)} أيام',
};

class RemindersScreen extends StatelessWidget {
  const RemindersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final prefs = context.watch<DevicePrefs>();
    final store = context.watch<AppStore>();
    final upcoming = NotificationService.buildPlan(store, prefs, DateTime.now()).take(15).toList();
    final agenda = prefs.dailyAgendaTime;
    final agendaTime = TimeOfDay(hour: agenda ~/ 60, minute: agenda % 60);
    final follow = prefs.followUpTime;
    final followTime = TimeOfDay(hour: follow ~/ 60, minute: follow % 60);

    return Scaffold(
      appBar: AppBar(title: const Text('التذكيرات والإشعارات')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () async {
                      final ok = await NotificationService.instance.requestPermission();
                      if (context.mounted) {
                        toast(context, ok ? 'الإشعارات مفعّلة ✅' : 'فعّل الإشعارات من إعدادات الجهاز');
                      }
                    },
                    icon: const Icon(Icons.notifications_active),
                    label: const Text('تفعيل الإشعارات'),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: () => NotificationService.instance.showNow('إشعار تجريبي', 'الإشعارات تعمل بشكل صحيح 👍'),
                  child: const Text('تجربة'),
                ),
              ],
            ),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.today),
            title: const Text('ملخص يومي'),
            subtitle: Text('كل يوم الساعة ${Fmt.digits(agendaTime.format(context))}'),
            value: prefs.dailyAgenda,
            onChanged: (v) => prefs.dailyAgenda = v,
          ),
          if (prefs.dailyAgenda)
            ListTile(
              leading: const SizedBox(),
              title: const Text('تغيير وقت الملخص'),
              trailing: const Icon(Icons.schedule),
              onTap: () async {
                final t = await showTimePicker(context: context, initialTime: agendaTime);
                if (t != null) prefs.dailyAgendaTime = t.hour * 60 + t.minute;
              },
            ),
          SwitchListTile(
            secondary: const Icon(Icons.task_alt),
            title: const Text('تذكير بالمهام في موعدها'),
            subtitle: const Text('بما فيها المهام المتكررة يومياً / أسبوعياً / شهرياً'),
            value: prefs.notifyTasks,
            onChanged: (v) => prefs.notifyTasks = v,
          ),
          SwitchListTile(
            secondary: const Icon(Icons.receipt_long),
            title: const Text('مواعيد الفواتير ونهاية العقود'),
            subtitle: const Text(
              'الفواتير: قبلها بيوم ويوم الاستحقاق وبعد أسبوع تأخير. العقود: قبلها بأسبوعين و3 أيام ويوم الانتهاء',
            ),
            value: prefs.notifyInvoices,
            onChanged: (v) => prefs.notifyInvoices = v,
          ),
          SwitchListTile(
            secondary: const Icon(Icons.fact_check),
            title: const Text('متابعة دورية: مين اخد ومين عليه فلوس'),
            subtitle: Text(
              'إشعار ${_everyLabel(prefs.followUpEveryDays)} الساعة ${Fmt.digits(followTime.format(context))}: '
              'الالتزامات اللي ما اتدفعتش، الموظفين اللي ما اخدوش، واللي ليك واللي عليك',
            ),
            value: prefs.followUpDigest,
            onChanged: (v) => prefs.followUpDigest = v,
          ),
          if (prefs.followUpDigest)
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 56, end: 12),
              child: Wrap(
                spacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  for (final d in const [1, 2, 3, 7])
                    ChoiceChip(
                      label: Text(_everyLabel(d)),
                      selected: prefs.followUpEveryDays == d,
                      onSelected: (_) => prefs.followUpEveryDays = d,
                    ),
                  ActionChip(
                    avatar: const Icon(Icons.schedule, size: 16),
                    label: Text(Fmt.digits(followTime.format(context))),
                    onPressed: () async {
                      final t = await showTimePicker(context: context, initialTime: followTime);
                      if (t != null) prefs.followUpTime = t.hour * 60 + t.minute;
                    },
                  ),
                ],
              ),
            ),
          SwitchListTile(
            secondary: const Icon(Icons.handshake_outlined),
            title: const Text('مواعيد الديون (ليك وعليك)'),
            subtitle: const Text('يوم الميعاد، وبعدها كل أسبوع لحد ما تتقفل'),
            value: prefs.notifyDebts,
            onChanged: (v) => prefs.notifyDebts = v,
          ),
          SwitchListTile(
            secondary: const Icon(Icons.event_repeat),
            title: const Text('المصاريف الثابتة والمرتبات'),
            subtitle: const Text('الإيجار والكهرباء وغيرها قبلها بيوم ويوم الميعاد، ويوم قبض الموظفين'),
            value: prefs.notifyBills,
            onChanged: (v) => prefs.notifyBills = v,
          ),
          SwitchListTile(
            secondary: const Icon(Icons.cake),
            title: const Text('أعياد ميلاد العملاء'),
            value: prefs.notifyBirthdays,
            onChanged: (v) => prefs.notifyBirthdays = v,
          ),
          SwitchListTile(
            secondary: const Icon(Icons.table_view),
            title: const Text('تذكير بتصدير تقرير الشهر'),
            subtitle: const Text('أول كل شهر'),
            value: prefs.monthlyExportReminder,
            onChanged: (v) => prefs.monthlyExportReminder = v,
          ),
          ListTile(
            leading: const Icon(Icons.add_alarm),
            title: const Text('إضافة تذكير جديد'),
            trailing: const Icon(Icons.chevron_left),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const TaskFormScreen(), fullscreenDialog: true),
            ),
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(
              'الإشعارات القادمة',
              style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold),
            ),
          ),
          if (upcoming.isEmpty) const ListTile(title: Text('لا توجد إشعارات مجدولة')),
          for (final n in upcoming)
            ListTile(
              dense: true,
              leading: Icon(n.repeat == null ? Icons.notifications_none : Icons.repeat),
              title: Text(n.title),
              subtitle: Text(n.body, maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: Text(Fmt.dateTime(n.at), style: const TextStyle(fontSize: 11)),
            ),
        ],
      ),
    );
  }
}
