import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:local_auth/local_auth.dart';
import 'package:provider/provider.dart';

import '../../data/prefs.dart';
import '../../data/sample_data.dart';
import '../../data/store.dart';
import '../../services/format.dart';
import '../widgets.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final AppStore _store = context.read<AppStore>();
  late final _b = _store.business;
  late final _name = TextEditingController(text: _b.name);
  late final _phone = TextEditingController(text: _b.phone);
  late final _email = TextEditingController(text: _b.email);
  late final _address = TextEditingController(text: _b.address);
  late final _taxId = TextEditingController(text: _b.taxId);
  late final _country = TextEditingController(text: _b.countryCode);
  late final _prefix = TextEditingController(text: _b.invoicePrefix);
  late final _footer = TextEditingController(text: _b.invoiceFooter);

  @override
  void dispose() {
    for (final c in [_name, _phone, _email, _address, _taxId, _country, _prefix, _footer]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Text fields are saved when leaving the screen.
  void _saveBusiness() {
    final b = _store.business;
    if (b.name == _name.text.trim() &&
        b.phone == _phone.text.trim() &&
        b.email == _email.text.trim() &&
        b.address == _address.text.trim() &&
        b.taxId == _taxId.text.trim() &&
        b.countryCode == _country.text.trim() &&
        b.invoicePrefix == _prefix.text &&
        b.invoiceFooter == _footer.text.trim()) {
      return;
    }
    _store.updateBusiness((b) {
      b
        ..name = _name.text.trim()
        ..phone = _phone.text.trim()
        ..email = _email.text.trim()
        ..address = _address.text.trim()
        ..taxId = _taxId.text.trim()
        ..countryCode = _country.text.trim().isEmpty ? '20' : _country.text.trim()
        ..invoicePrefix = _prefix.text
        ..invoiceFooter = _footer.text.trim();
    });
  }

  Future<void> _pickLogo() async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 400,
      maxHeight: 400,
      imageQuality: 85,
    );
    if (file == null) return;
    final bytes = await file.readAsBytes();
    _store.updateBusiness((b) => b.logoBase64 = base64Encode(bytes));
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final prefs = context.watch<DevicePrefs>();
    final b = store.business;
    const gap = SizedBox(height: 12);

    Widget header(String t) => Padding(
      padding: const EdgeInsets.fromLTRB(0, 24, 0, 8),
      child: Text(
        t,
        style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold),
      ),
    );

    return PopScope(
      onPopInvokedWithResult: (didPop, _) => _saveBusiness(),
      child: Scaffold(
        appBar: AppBar(title: const Text('الإعدادات')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            header('بيانات النشاط (تظهر في الفواتير)'),
            Row(
              children: [
                GestureDetector(
                  onTap: _pickLogo,
                  child: Avatar(
                    name: b.name.isEmpty ? 'شعار' : b.name,
                    size: 72,
                    image: b.logoBase64.isEmpty ? null : MemoryImage(base64Decode(b.logoBase64)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextButton.icon(
                        onPressed: _pickLogo,
                        icon: const Icon(Icons.image),
                        label: const Text('اختيار الشعار'),
                      ),
                      if (b.logoBase64.isNotEmpty)
                        TextButton(
                          onPressed: () => _store.updateBusiness((b) => b.logoBase64 = ''),
                          child: const Text('إزالة الشعار', style: TextStyle(color: Colors.red)),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            gap,
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'اسم النشاط التجاري'),
            ),
            gap,
            TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'رقم الهاتف'),
            ),
            gap,
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'البريد الإلكتروني'),
            ),
            gap,
            TextField(
              controller: _address,
              decoration: const InputDecoration(labelText: 'العنوان'),
            ),
            gap,
            TextField(
              controller: _taxId,
              decoration: const InputDecoration(labelText: 'الرقم الضريبي / السجل التجاري'),
            ),
            header('الفواتير والعملة'),
            DropdownButtonFormField<String>(
              initialValue: currencies.any((c) => c.code == b.currency) ? b.currency : 'EGP',
              decoration: const InputDecoration(labelText: 'العملة'),
              items: [
                for (final c in currencies) DropdownMenuItem(value: c.code, child: Text('${c.name} (${c.symbol})')),
              ],
              onChanged: (v) => _store.updateBusiness((b) => b.currency = v ?? 'EGP'),
            ),
            gap,
            TextField(
              controller: _country,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'كود الدولة لواتساب',
                helperText: 'مصر 20، السعودية 966، الإمارات 971، الكويت 965',
              ),
            ),
            gap,
            TextField(
              controller: _prefix,
              decoration: const InputDecoration(labelText: 'بادئة رقم الفاتورة'),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('رقم الفاتورة التالية'),
              subtitle: Text(store.peekInvoiceNumber()),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline),
                    onPressed: b.nextInvoiceNumber > 1
                        ? () => _store.updateBusiness((b) => b.nextInvoiceNumber -= 1)
                        : null,
                  ),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline),
                    onPressed: () => _store.updateBusiness((b) => b.nextInvoiceNumber += 1),
                  ),
                ],
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: AmountField(
                    label: 'الضريبة الافتراضية',
                    suffix: '٪',
                    value: b.defaultTaxRate,
                    onChanged: (v) => _store.updateBusiness((b) => b.defaultTaxRate = v),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: AmountField(
                    label: 'مدة الاستحقاق',
                    suffix: 'يوم',
                    value: b.defaultDueDays.toDouble(),
                    onChanged: (v) => _store.updateBusiness((b) => b.defaultDueDays = v.round()),
                  ),
                ),
              ],
            ),
            gap,
            TextField(
              controller: _footer,
              decoration: const InputDecoration(labelText: 'تذييل الفاتورة'),
            ),
            gap,
            AmountField(
              label: 'هدف الإيرادات الشهري (يظهر في الرئيسية)',
              suffix: Fmt.symbol,
              value: b.monthlyTarget,
              onChanged: (v) => _store.updateBusiness((b) => b.monthlyTarget = v),
            ),
            header('المظهر'),
            SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(value: ThemeMode.system, label: Text('تلقائي')),
                ButtonSegment(value: ThemeMode.light, label: Text('فاتح')),
                ButtonSegment(value: ThemeMode.dark, label: Text('داكن')),
              ],
              selected: {prefs.themeMode},
              onSelectionChanged: (s) => prefs.themeMode = s.first,
            ),
            gap,
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (var i = 0; i < DevicePrefs.accents.length; i++)
                  GestureDetector(
                    onTap: () => prefs.accentIndex = i,
                    child: CircleAvatar(
                      radius: 18,
                      backgroundColor: DevicePrefs.accents[i],
                      child: prefs.accentIndex == i ? const Icon(Icons.check, color: Colors.white) : null,
                    ),
                  ),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('أرقام عربية (١٢٣)'),
              value: prefs.arabicDigits,
              onChanged: (v) => prefs.arabicDigits = v,
            ),
            header('الحماية'),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.fingerprint),
              title: const Text('قفل التطبيق بالبصمة / Face ID'),
              value: prefs.appLock,
              onChanged: (v) async {
                if (!v) {
                  prefs.appLock = false;
                  return;
                }
                try {
                  final auth = LocalAuthentication();
                  if (!await auth.isDeviceSupported()) {
                    if (context.mounted) toast(context, 'فعّل قفل الشاشة على جهازك أولاً');
                    return;
                  }
                  if (await auth.authenticate(localizedReason: 'تأكيد تفعيل قفل التطبيق')) prefs.appLock = true;
                } catch (_) {
                  if (context.mounted) toast(context, 'تعذّر تفعيل القفل على هذا الجهاز');
                }
              },
            ),
            header('البيانات'),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.auto_awesome),
              title: const Text('تحميل بيانات تجريبية'),
              onTap: () async {
                if (await confirm(
                  context,
                  'تحميل بيانات تجريبية؟',
                  'ستُضاف بيانات تجريبية بجانب بياناتك الحالية.',
                  action: 'تحميل',
                  destructive: false,
                )) {
                  loadSampleData(_store);
                }
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.delete_forever, color: Colors.red),
              title: const Text('حذف كل البيانات', style: TextStyle(color: Colors.red)),
              subtitle: const Text('يُحذف أيضاً من الأجهزة المتزامنة'),
              onTap: () async {
                if (await confirm(
                  context,
                  'حذف كل البيانات؟',
                  'سيتم حذف كل العملاء والفواتير والمهام والمصروفات نهائياً. خذ نسخة احتياطية أولاً.',
                )) {
                  _store.wipe();
                }
              },
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}
