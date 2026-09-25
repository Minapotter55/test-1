import 'package:intl/intl.dart';

class CurrencyOption {
  const CurrencyOption(this.code, this.name, this.symbol);
  final String code;
  final String name;
  final String symbol;
}

const currencies = <CurrencyOption>[
  CurrencyOption('EGP', 'جنيه مصري', 'ج.م'),
  CurrencyOption('SAR', 'ريال سعودي', 'ر.س'),
  CurrencyOption('AED', 'درهم إماراتي', 'د.إ'),
  CurrencyOption('KWD', 'دينار كويتي', 'د.ك'),
  CurrencyOption('QAR', 'ريال قطري', 'ر.ق'),
  CurrencyOption('BHD', 'دينار بحريني', 'د.ب'),
  CurrencyOption('OMR', 'ريال عماني', 'ر.ع'),
  CurrencyOption('JOD', 'دينار أردني', 'د.أ'),
  CurrencyOption('LYD', 'دينار ليبي', 'د.ل'),
  CurrencyOption('MAD', 'درهم مغربي', 'د.م'),
  CurrencyOption('IQD', 'دينار عراقي', 'د.ع'),
  CurrencyOption('USD', 'دولار أمريكي', r'$'),
  CurrencyOption('EUR', 'يورو', '€'),
  CurrencyOption('GBP', 'جنيه إسترليني', '£'),
];

/// Central formatting. [currency] and [arabicDigits] are updated from settings.
class Fmt {
  static String currency = 'EGP';
  static bool arabicDigits = false;

  static const _latin = '0123456789';
  static const _arabic = '٠١٢٣٤٥٦٧٨٩';

  static String digits(String s) {
    final from = arabicDigits ? _latin : _arabic;
    final to = arabicDigits ? _arabic : _latin;
    final b = StringBuffer();
    for (final ch in s.split('')) {
      final i = from.indexOf(ch);
      b.write(i >= 0 ? to[i] : ch);
    }
    return b.toString();
  }

  static String get symbol => currencies
      .firstWhere((c) => c.code == currency, orElse: () => CurrencyOption(currency, currency, currency))
      .symbol;

  static String number(num v, {int decimals = 2}) {
    final f = NumberFormat.decimalPatternDigits(locale: 'en', decimalDigits: decimals);
    var s = f.format(v);
    if (s.contains('.')) {
      s = s.replaceFirst(RegExp(r'\.?0+$'), '');
    }
    return digits(s);
  }

  static String money(num v) => '${number(v)} $symbol';

  static String compactMoney(num v) {
    final s = NumberFormat.compact(locale: 'en').format(v);
    return '${digits(s)} $symbol';
  }

  static String percent(num v) => '${number(v, decimals: 1)}٪';

  static String date(DateTime d) => digits(DateFormat('d MMM y', 'ar').format(d));
  static String dateTime(DateTime d) => digits(DateFormat('d MMM، h:mm a', 'ar').format(d));
  static String time(DateTime d) => digits(DateFormat('h:mm a', 'ar').format(d));
  static String month(DateTime d) => digits(DateFormat('MMMM y', 'ar').format(d));
  static String shortMonth(DateTime d) => digits(DateFormat('MMM', 'ar').format(d));
  static String weekday(DateTime d) => digits(DateFormat('EEEE d MMMM', 'ar').format(d));

  static String relative(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);
    final diff = day.difference(today).inDays;
    if (diff == 0) return 'اليوم';
    if (diff == -1) return 'أمس';
    if (diff == 1) return 'غداً';
    if (diff < 0) return 'منذ ${number(-diff)} يوم';
    return 'بعد ${number(diff)} يوم';
  }

  /// Parses user input with Arabic or Latin digits.
  static double parse(String s) {
    final b = StringBuffer();
    for (final ch in s.split('')) {
      final ai = _arabic.indexOf(ch);
      if (ai >= 0) {
        b.write(ai);
      } else if (_latin.contains(ch)) {
        b.write(ch);
      } else if (ch == '.' || ch == '٫' || ch == ',') {
        b.write('.');
      } else if (ch == '-' && b.isEmpty) {
        b.write('-');
      }
    }
    return double.tryParse(b.toString()) ?? 0;
  }

  static String input(double v) {
    if (v == 0) return '';
    if (v == v.roundToDouble()) return v.toInt().toString();
    return v.toString();
  }

  static String monthKey(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}';
}

DateTime startOfMonth(DateTime d) => DateTime(d.year, d.month);
DateTime startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);
