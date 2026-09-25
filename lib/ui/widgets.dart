import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../data/store.dart';
import '../services/format.dart';

class StatCard extends StatelessWidget {
  const StatCard({
    super.key,
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    this.subtitle,
  });

  final String title;
  final String value;
  final IconData icon;
  final Color color;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(height: 10),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: Text(value, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
            ),
            Text(title, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            if (subtitle != null)
              Text(
                subtitle!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(color: color),
              ),
          ],
        ),
      ),
    );
  }
}

/// Two-column grid of [StatCard]s where each row takes its tallest card's height.
class StatGrid extends StatelessWidget {
  const StatGrid({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i += 2) {
      rows.add(
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: children[i]),
              const SizedBox(width: 10),
              Expanded(child: i + 1 < children.length ? children[i + 1] : const SizedBox()),
            ],
          ),
        ),
      );
      if (i + 2 < children.length) rows.add(const SizedBox(height: 10));
    }
    return Column(children: rows);
  }
}

class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, required this.color, this.icon});
  final String text;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 12, color: color), const SizedBox(width: 3)],
          Text(
            text,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color),
          ),
        ],
      ),
    );
  }
}

class Avatar extends StatelessWidget {
  const Avatar({super.key, required this.name, this.color, this.size = 44, this.image});
  final String name;
  final Color? color;
  final double size;
  final ImageProvider? image;

  String get initials {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).take(2);
    return parts.map((p) => p.characters.first).join();
  }

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.primary;
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: c.withValues(alpha: 0.15),
      backgroundImage: image,
      child: image != null
          ? null
          : Text(
              initials.isEmpty ? '؟' : initials,
              style: TextStyle(color: c, fontWeight: FontWeight.bold, fontSize: size * 0.34),
            ),
    );
  }
}

class SectionCard extends StatelessWidget {
  const SectionCard({super.key, required this.title, this.icon, required this.child, this.trailing});
  final String title;
  final IconData? icon;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (icon != null) ...[Icon(icon, size: 20, color: theme.colorScheme.primary), const SizedBox(width: 6)],
                Expanded(
                  child: Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                ),
                ?trailing,
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.message, this.actionLabel, this.onAction});
  final IconData icon;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: theme.colorScheme.outline),
            const SizedBox(height: 12),
            Text(title, style: theme.textTheme.titleLarge, textAlign: TextAlign.center),
            if (message != null) ...[
              const SizedBox(height: 6),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
            if (actionLabel != null) ...[
              const SizedBox(height: 16),
              FilledButton.icon(onPressed: onAction, icon: const Icon(Icons.add), label: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

/// Horizontal row of filter chips.
class ChipsBar<T> extends StatelessWidget {
  const ChipsBar({
    super.key,
    required this.options,
    required this.selected,
    required this.label,
    required this.onSelected,
  });
  final List<T?> options;
  final T? selected;
  final String Function(T?) label;
  final ValueChanged<T?> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        children: [
          for (final o in options)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 6),
              child: ChoiceChip(label: Text(label(o)), selected: o == selected, onSelected: (_) => onSelected(o)),
            ),
        ],
      ),
    );
  }
}

/// Number input that accepts Arabic digits.
class AmountField extends StatefulWidget {
  const AmountField({super.key, required this.label, required this.value, required this.onChanged, this.suffix});
  final String label;
  final double value;
  final ValueChanged<double> onChanged;
  final String? suffix;

  @override
  State<AmountField> createState() => _AmountFieldState();
}

class _AmountFieldState extends State<AmountField> {
  late final _c = TextEditingController(text: Fmt.input(widget.value));

  @override
  void didUpdateWidget(AmountField old) {
    super.didUpdateWidget(old);
    if (Fmt.parse(_c.text) != widget.value) _c.text = Fmt.input(widget.value);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _c,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(labelText: widget.label, suffixText: widget.suffix),
      onChanged: (t) => widget.onChanged(Fmt.parse(t)),
    );
  }
}

/// Optional customer selector.
class CustomerDropdown extends StatelessWidget {
  const CustomerDropdown({super.key, required this.value, required this.onChanged, this.label = 'العميل'});
  final String? value;
  final ValueChanged<String?> onChanged;
  final String label;

  @override
  Widget build(BuildContext context) {
    final customers = context.watch<AppStore>().customers.all..sort((a, b) => a.name.compareTo(b.name));
    final valid = customers.any((c) => c.id == value) ? value : null;
    return DropdownButtonFormField<String?>(
      initialValue: valid,
      isExpanded: true,
      decoration: InputDecoration(labelText: label, prefixIcon: const Icon(Icons.person_outline)),
      items: [
        const DropdownMenuItem<String?>(value: null, child: Text('بدون عميل')),
        for (final c in customers)
          DropdownMenuItem<String?>(
            value: c.id,
            child: Text(c.name, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: onChanged,
    );
  }
}

Future<bool> confirm(
  BuildContext context,
  String title,
  String message, {
  String action = 'حذف',
  bool destructive = true,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
        FilledButton(
          style: destructive ? FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error) : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(action),
        ),
      ],
    ),
  );
  return result ?? false;
}

void toast(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

Future<DateTime?> pickDate(BuildContext context, DateTime initial, {DateTime? first}) => showDatePicker(
  context: context,
  initialDate: initial,
  firstDate: first ?? DateTime(2000),
  lastDate: DateTime(2100),
);

Future<DateTime?> pickDateTime(BuildContext context, DateTime initial) async {
  final date = await pickDate(context, initial);
  if (date == null || !context.mounted) return null;
  final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(initial));
  if (time == null) return null;
  return DateTime(date.year, date.month, date.day, time.hour, time.minute);
}

Future<void> shareFile(BuildContext context, File file, {String? text}) async {
  final box = context.findRenderObject() as RenderBox?;
  await SharePlus.instance.share(
    ShareParams(
      files: [XFile(file.path)],
      text: text,
      sharePositionOrigin: box == null ? null : box.localToGlobal(Offset.zero) & box.size,
    ),
  );
}

/// A labelled row with an icon, used on detail screens.
class InfoTile extends StatelessWidget {
  const InfoTile(this.label, this.value, {super.key, required this.icon, this.onTap});
  final String label;
  final String value;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    if (value.isEmpty) return const SizedBox.shrink();
    return ListTile(
      dense: true,
      leading: Icon(icon),
      title: Text(label),
      subtitle: SelectableText(value, style: Theme.of(context).textTheme.bodyLarge),
      onTap: onTap,
    );
  }
}
