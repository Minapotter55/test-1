import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_services.dart';
import '../../data/prefs.dart';
import '../../services/drive_sync.dart';
import '../../services/exporter.dart';
import '../../services/format.dart';
import '../widgets.dart';

/// Google Drive sync, monthly Excel exports and manual backup/restore.
class SyncScreen extends StatefulWidget {
  const SyncScreen({super.key});

  @override
  State<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends State<SyncScreen> {
  List<File> _exports = [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadExports();
  }

  Future<void> _loadExports() async {
    try {
      final files = await Exporter.listExports();
      if (mounted) setState(() => _exports = files);
    } catch (_) {}
  }

  Future<void> _run(Future<void> Function() job) async {
    setState(() => _busy = true);
    try {
      await job();
    } finally {
      if (mounted) setState(() => _busy = false);
      await _loadExports();
    }
  }

  Future<void> _exportMonth(DateTime month) => _run(() async {
    final exporter = context.read<Exporter>();
    final sync = context.read<DriveSync>();
    final prefs = context.read<DevicePrefs>();
    final file = await exporter.exportMonth(month);
    var uploaded = false;
    if (sync.connected && prefs.uploadExportsToDrive) uploaded = await sync.uploadExport(file);
    if (!mounted) return;
    toast(context, uploaded ? 'تم التصدير والرفع على Google Drive' : 'تم التصدير');
    await shareFile(context, file);
  });

  Future<void> _pickMonthAndExport() async {
    final now = DateTime.now();
    final months = [for (var i = 0; i < 12; i++) DateTime(now.year, now.month - i)];
    final month = await showModalBottomSheet<DateTime>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => ListView(
        shrinkWrap: true,
        children: [
          for (final m in months)
            ListTile(
              leading: const Icon(Icons.calendar_month),
              title: Text(Fmt.month(m)),
              onTap: () => Navigator.pop(ctx, m),
            ),
        ],
      ),
    );
    if (month != null) await _exportMonth(month);
  }

  Future<void> _backup() => _run(() async {
    final file = await context.read<Exporter>().writeBackup();
    if (!mounted) return;
    await shareFile(context, file, text: 'نسخة احتياطية ClientPro');
  });

  Future<void> _restore() async {
    final picked = await FilePicker.pickFile(type: FileType.any);
    if (picked == null || !mounted) return;
    final path = picked.path;
    if (path == null) {
      toast(context, 'تعذّر قراءة الملف');
      return;
    }
    final text = await File(path).readAsString();
    if (!mounted) return;
    final mode = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('استرجاع نسخة احتياطية'),
        content: const Text(
          'دمج: يضيف ما في النسخة لبياناتك الحالية ويحدّث الأقدم.\nاستبدال: يحذف بياناتك الحالية ويضع النسخة مكانها.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'replace'),
            child: const Text('استبدال', style: TextStyle(color: Colors.red)),
          ),
          FilledButton(onPressed: () => Navigator.pop(ctx, 'merge'), child: const Text('دمج')),
        ],
      ),
    );
    if (mode == null || !mounted) return;
    final error = context.read<Exporter>().restoreFromJson(text, merge: mode == 'merge');
    toast(context, error ?? 'تم استرجاع البيانات بنجاح');
  }

  @override
  Widget build(BuildContext context) {
    final sync = context.watch<DriveSync>();
    final prefs = context.watch<DevicePrefs>();
    final lastSync = prefs.lastSyncAt == 0 ? null : DateTime.fromMillisecondsSinceEpoch(prefs.lastSyncAt);
    final theme = Theme.of(context);

    Widget header(String t) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
      child: Text(
        t,
        style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.bold),
      ),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('المزامنة والنسخ الاحتياطي')),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              header('المزامنة مع Google Drive'),
              Card(
                margin: const EdgeInsets.symmetric(horizontal: 12),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Icon(
                            sync.connected ? Icons.cloud_done : Icons.cloud_off,
                            color: sync.connected ? Colors.green : Colors.grey,
                            size: 36,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  sync.connected ? 'متصل' : 'غير متصل',
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                                if (sync.email.isNotEmpty) Text(sync.email, style: const TextStyle(fontSize: 12)),
                                if (lastSync != null)
                                  Text('آخر مزامنة: ${Fmt.dateTime(lastSync)}', style: const TextStyle(fontSize: 12)),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'بياناتك تُحفظ في مجلد ClientPro على Google Drive الخاص بك، وتتزامن تلقائياً بين كل أجهزتك '
                        '(أندرويد وآيفون) عند تسجيل الدخول بنفس الحساب. التعديلات من أكثر من جهاز تُدمج ولا تضيع.',
                        style: TextStyle(fontSize: 12),
                      ),
                      if (sync.error != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(sync.error!, style: const TextStyle(color: Colors.red)),
                        ),
                      const SizedBox(height: 12),
                      if (!sync.isConfigured)
                        const Text(
                          '⚠️ لم يتم إعداد Google Drive في هذه النسخة بعد (راجع README).',
                          style: TextStyle(color: Colors.orange),
                        )
                      else if (!sync.connected)
                        FilledButton.icon(
                          onPressed: sync.connect,
                          icon: const Icon(Icons.login),
                          label: const Text('تسجيل الدخول بحساب Google'),
                        )
                      else
                        Row(
                          children: [
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: sync.syncing ? null : () => sync.syncNow(interactive: true),
                                icon: sync.syncing
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      )
                                    : const Icon(Icons.sync),
                                label: const Text('مزامنة الآن'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            OutlinedButton(
                              onPressed: () async {
                                if (await confirm(
                                  context,
                                  'قطع الاتصال؟',
                                  'ستبقى بياناتك على هذا الجهاز وعلى Drive، لكن لن تتزامن.',
                                  action: 'قطع الاتصال',
                                )) {
                                  await sync.disconnect();
                                }
                              },
                              child: const Text('قطع الاتصال'),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
              header('تصدير Excel الشهري'),
              SwitchListTile(
                secondary: const Icon(Icons.event_repeat),
                title: const Text('تصدير تلقائي أول كل شهر'),
                subtitle: const Text('ملف Excel فيه الملخص والفواتير والمدفوعات والمصروفات والعملاء والمهام'),
                value: prefs.autoMonthlyExport,
                onChanged: (v) => prefs.autoMonthlyExport = v,
              ),
              SwitchListTile(
                secondary: const Icon(Icons.drive_folder_upload),
                title: const Text('رفع التقرير على Google Drive'),
                subtitle: const Text('في مجلد ClientPro / تقارير شهرية'),
                value: prefs.uploadExportsToDrive,
                onChanged: sync.connected ? (v) => prefs.uploadExportsToDrive = v : null,
              ),
              ListTile(
                leading: const Icon(Icons.table_view),
                title: const Text('تصدير شهر الآن'),
                trailing: const Icon(Icons.chevron_left),
                onTap: _pickMonthAndExport,
              ),
              header('نسخة احتياطية يدوية'),
              ListTile(
                leading: const Icon(Icons.save_alt),
                title: const Text('إنشاء نسخة احتياطية'),
                subtitle: const Text('احفظها في iCloud Drive أو Google Drive أو أرسلها لنفسك'),
                onTap: _backup,
              ),
              ListTile(
                leading: const Icon(Icons.restore),
                title: const Text('استرجاع من نسخة احتياطية'),
                subtitle: const Text('من ملفات الجهاز أو iCloud Drive أو Google Drive'),
                onTap: _restore,
              ),
              if (_exports.isNotEmpty) ...[
                header('الملفات المصدّرة'),
                for (final f in _exports.take(24))
                  ListTile(
                    leading: Icon(
                      f.path.endsWith('.xlsx') ? Icons.table_chart : Icons.data_object,
                      color: Colors.green,
                    ),
                    title: Text(f.uri.pathSegments.last, textDirection: TextDirection.ltr),
                    subtitle: Text(Fmt.dateTime(f.statSync().modified)),
                    trailing: IconButton(icon: const Icon(Icons.share), onPressed: () => shareFile(context, f)),
                  ),
              ],
              Padding(
                padding: const EdgeInsets.all(16),
                child: TextButton.icon(
                  onPressed: () => context.read<AppServices>().runMonthlyExport(),
                  icon: const Icon(Icons.play_circle_outline),
                  label: const Text('تشغيل التصدير التلقائي الآن (إن كان مستحقاً)'),
                ),
              ),
            ],
          ),
          if (_busy)
            const Positioned.fill(
              child: ColoredBox(
                color: Colors.black26,
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
        ],
      ),
    );
  }
}
