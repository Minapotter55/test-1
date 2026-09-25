import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/store.dart';
import '../../models/models.dart';
import '../../services/format.dart';
import '../widgets.dart';

class TasksScreen extends StatefulWidget {
  const TasksScreen({super.key});

  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> {
  bool _showDone = false;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final all = store.tasks.all;
    final now = DateTime.now();
    int byDue(TaskItem a, TaskItem b) {
      final c = (a.dueDate ?? DateTime(9999)).compareTo(b.dueDate ?? DateTime(9999));
      return c != 0 ? c : b.priority.index.compareTo(a.priority.index);
    }

    final open = all.where((t) => !t.isDone).toList()..sort(byDue);
    final overdue = open.where((t) => t.isOverdue).toList();
    final today = open.where((t) => t.isDueToday && !t.isOverdue).toList();
    final upcoming = open.where((t) => t.dueDate != null && !t.isDueToday && t.dueDate!.isAfter(now)).toList();
    final noDate = open.where((t) => t.dueDate == null).toList();
    final done = all.where((t) => t.isDone).toList()
      ..sort((a, b) => (b.completedAt ?? now).compareTo(a.completedAt ?? now));

    Widget section(String title, List<TaskItem> list, Color color) {
      if (list.isEmpty) return const SizedBox.shrink();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Row(
              children: [
                CircleAvatar(radius: 4, backgroundColor: color),
                const SizedBox(width: 6),
                Text('$title (${Fmt.number(list.length)})', style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          for (final t in list) TaskTile(task: t),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('المهام والتذكيرات')),
      floatingActionButton: FloatingActionButton(
        heroTag: 'fab-tasks',
        onPressed: () =>
            Navigator.push(context, MaterialPageRoute(builder: (_) => const TaskFormScreen(), fullscreenDialog: true)),
        child: const Icon(Icons.add_task),
      ),
      body: all.isEmpty
          ? EmptyState(
              icon: Icons.task_alt,
              title: 'لا توجد مهام',
              message: 'أضف مهام المتابعة وسيذكّرك التطبيق بإشعار في موعدها',
              actionLabel: 'مهمة جديدة',
              onAction: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TaskFormScreen())),
            )
          : ListView(
              padding: const EdgeInsets.only(bottom: 90),
              children: [
                if (open.isEmpty)
                  const EmptyState(icon: Icons.celebration, title: 'أحسنت! 🎉', message: 'لا توجد مهام مفتوحة'),
                section('متأخرة', overdue, Colors.red),
                section('اليوم', today, Colors.orange),
                section('قادمة', upcoming, Colors.blue),
                section('بدون موعد', noDate, Colors.grey),
                if (done.isNotEmpty)
                  ExpansionTile(
                    title: Text('المكتملة (${Fmt.number(done.length)})'),
                    initiallyExpanded: _showDone,
                    onExpansionChanged: (v) => setState(() => _showDone = v),
                    children: [for (final t in done.take(50)) TaskTile(task: t)],
                  ),
              ],
            ),
    );
  }
}

class TaskTile extends StatelessWidget {
  const TaskTile({super.key, required this.task, this.showCustomer = true, this.dense = false});
  final TaskItem task;
  final bool showCustomer;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final store = context.read<AppStore>();
    final customer = showCustomer ? store.customer(task.customerId) : null;
    final due = task.dueDate;
    return Dismissible(
      key: ValueKey('task-${task.id}'),
      background: Container(
        color: Colors.orange,
        alignment: AlignmentDirectional.centerStart,
        padding: const EdgeInsets.all(16),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.snooze, color: Colors.white),
            Text(' تأجيل يوم', style: TextStyle(color: Colors.white)),
          ],
        ),
      ),
      secondaryBackground: Container(
        color: Colors.red,
        alignment: AlignmentDirectional.centerEnd,
        padding: const EdgeInsets.all(16),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      confirmDismiss: (dir) async {
        if (dir == DismissDirection.startToEnd) {
          if (!task.isDone && due != null) {
            final base = due.isAfter(DateTime.now()) ? due : DateTime.now();
            task.dueDate = base.add(const Duration(days: 1));
            store.upsert(store.tasks, task);
          }
          return false;
        }
        return confirm(context, 'حذف المهمة؟', task.title);
      },
      onDismissed: (_) => store.delete(store.tasks, task.id),
      child: ListTile(
        dense: dense,
        contentPadding: dense ? EdgeInsets.zero : null,
        leading: IconButton(
          icon: Icon(
            task.isDone ? Icons.check_circle : Icons.radio_button_unchecked,
            color: task.isDone ? Colors.green : task.priority.color,
          ),
          onPressed: () {
            if (task.isDone) {
              task
                ..isDone = false
                ..completedAt = null;
            } else {
              task.complete();
            }
            store.upsert(store.tasks, task);
            if (task.repeat != RepeatRule.none && !task.isDone) {
              toast(context, 'تم — الموعد القادم ${Fmt.dateTime(task.dueDate!)}');
            }
          },
        ),
        title: Text(
          task.title,
          style: TextStyle(decoration: task.isDone ? TextDecoration.lineThrough : null, fontWeight: FontWeight.w600),
        ),
        subtitle: Wrap(
          spacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (due != null)
              Text(Fmt.dateTime(due), style: TextStyle(color: task.isOverdue ? Colors.red : null, fontSize: 12)),
            if (task.repeat != RepeatRule.none) Pill(task.repeat.label, color: Colors.indigo, icon: Icons.repeat),
            if (customer != null) Text('👤 ${customer.name}', style: const TextStyle(fontSize: 12)),
            if (task.reminder && !task.isDone && due != null)
              const Icon(Icons.notifications_active, size: 14, color: Colors.orange),
          ],
        ),
        trailing: task.priority == TaskPriority.high && !task.isDone
            ? const Icon(Icons.flag, color: Colors.red, size: 18)
            : null,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => TaskFormScreen(task: task), fullscreenDialog: true),
        ),
      ),
    );
  }
}

class TaskFormScreen extends StatefulWidget {
  const TaskFormScreen({super.key, this.task, this.customerId});
  final TaskItem? task;
  final String? customerId;

  @override
  State<TaskFormScreen> createState() => _TaskFormScreenState();
}

class _TaskFormScreenState extends State<TaskFormScreen> {
  late final TaskItem? _t = widget.task;
  late final _title = TextEditingController(text: _t?.title);
  late final _notes = TextEditingController(text: _t?.notes);
  late String? _customerId = _t?.customerId ?? widget.customerId;
  late bool _hasDue = _t == null || _t.dueDate != null;
  late DateTime _due = _t?.dueDate ?? _tomorrowAt10();
  late TaskPriority _priority = _t?.priority ?? TaskPriority.medium;
  late bool _reminder = _t?.reminder ?? true;
  late RepeatRule _repeat = _t?.repeat ?? RepeatRule.none;

  static DateTime _tomorrowAt10() {
    final n = DateTime.now().add(const Duration(days: 1));
    return DateTime(n.year, n.month, n.day, 10);
  }

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _save() {
    if (_title.text.trim().isEmpty) {
      toast(context, 'اكتب عنوان المهمة');
      return;
    }
    final store = context.read<AppStore>();
    final t = _t ?? TaskItem();
    t
      ..title = _title.text.trim()
      ..notes = _notes.text.trim()
      ..customerId = _customerId
      ..dueDate = _hasDue ? _due : null
      ..priority = _priority
      ..reminder = _hasDue && _reminder
      ..repeat = _hasDue ? _repeat : RepeatRule.none;
    store.upsert(store.tasks, t);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    const gap = SizedBox(height: 12);
    return Scaffold(
      appBar: AppBar(
        title: Text(_t == null ? 'مهمة / تذكير جديد' : 'تعديل المهمة'),
        actions: [TextButton(onPressed: _save, child: const Text('حفظ'))],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _title,
            decoration: const InputDecoration(labelText: 'العنوان *'),
          ),
          gap,
          TextField(
            controller: _notes,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'تفاصيل (اختياري)'),
          ),
          gap,
          CustomerDropdown(value: _customerId, onChanged: (v) => setState(() => _customerId = v)),
          gap,
          SegmentedButton<TaskPriority>(
            segments: [for (final p in TaskPriority.values) ButtonSegment(value: p, label: Text(p.label))],
            selected: {_priority},
            onSelectionChanged: (s) => setState(() => _priority = s.first),
          ),
          const Divider(height: 32),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('موعد محدد'),
            value: _hasDue,
            onChanged: (v) => setState(() => _hasDue = v),
          ),
          if (_hasDue) ...[
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event),
              title: Text(Fmt.dateTime(_due)),
              subtitle: Text(Fmt.relative(_due)),
              onTap: () async {
                final d = await pickDateTime(context, _due);
                if (d != null) setState(() => _due = d);
              },
            ),
            Wrap(
              spacing: 6,
              children: [
                ActionChip(
                  label: const Text('بعد ساعة'),
                  onPressed: () => setState(() => _due = DateTime.now().add(const Duration(hours: 1))),
                ),
                ActionChip(label: const Text('غداً ١٠ص'), onPressed: () => setState(() => _due = _tomorrowAt10())),
                ActionChip(
                  label: const Text('بعد أسبوع'),
                  onPressed: () => setState(() => _due = _tomorrowAt10().add(const Duration(days: 6))),
                ),
              ],
            ),
            gap,
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.notifications_active_outlined),
              title: const Text('تذكير بإشعار'),
              value: _reminder,
              onChanged: (v) => setState(() => _reminder = v),
            ),
            DropdownButtonFormField<RepeatRule>(
              initialValue: _repeat,
              decoration: const InputDecoration(labelText: 'التكرار', prefixIcon: Icon(Icons.repeat)),
              items: [for (final r in RepeatRule.values) DropdownMenuItem(value: r, child: Text(r.label))],
              onChanged: (v) => setState(() => _repeat = v ?? RepeatRule.none),
            ),
          ],
          const SizedBox(height: 24),
          FilledButton(onPressed: _save, child: const Text('حفظ')),
          if (_t != null)
            TextButton(
              onPressed: () async {
                if (await confirm(context, 'حذف المهمة؟', _t.title)) {
                  if (!context.mounted) return;
                  final store = context.read<AppStore>();
                  store.delete(store.tasks, _t.id);
                  Navigator.pop(context);
                }
              },
              child: const Text('حذف المهمة', style: TextStyle(color: Colors.red)),
            ),
        ],
      ),
    );
  }
}
