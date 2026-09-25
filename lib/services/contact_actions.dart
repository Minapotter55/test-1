import 'package:url_launcher/url_launcher.dart';

/// Call / WhatsApp / SMS / email / maps links.
class ContactActions {
  static String _digits(String raw) {
    const arabic = '٠١٢٣٤٥٦٧٨٩';
    final b = StringBuffer();
    for (final ch in raw.split('')) {
      final i = arabic.indexOf(ch);
      if (i >= 0) {
        b.write(i);
      } else if ('0123456789'.contains(ch)) {
        b.write(ch);
      }
    }
    return b.toString();
  }

  /// International format without "+" as WhatsApp expects (e.g. 2010xxxxxxx).
  static String international(String raw, String countryCode) {
    final trimmed = raw.trim();
    final d = _digits(trimmed);
    if (trimmed.startsWith('+')) return d;
    if (d.startsWith('00')) return d.substring(2);
    if (d.startsWith('0')) return countryCode + d.substring(1);
    return d;
  }

  static Uri? call(String phone) {
    final d = _digits(phone);
    if (d.isEmpty) return null;
    return Uri(scheme: 'tel', path: phone.trim().startsWith('+') ? '+$d' : d);
  }

  static Uri? sms(String phone) {
    final d = _digits(phone);
    return d.isEmpty ? null : Uri(scheme: 'sms', path: d);
  }

  static Uri? whatsapp(String phone, String countryCode, {String text = ''}) {
    final d = international(phone, countryCode);
    if (d.isEmpty) return null;
    return Uri.https('wa.me', '/$d', text.isEmpty ? null : {'text': text});
  }

  static Uri? email(String address) {
    final a = address.trim();
    return a.isEmpty ? null : Uri(scheme: 'mailto', path: a);
  }

  static Uri? maps(String address) {
    final a = address.trim();
    return a.isEmpty ? null : Uri.https('www.google.com', '/maps/search/', {'api': '1', 'query': a});
  }

  static Future<bool> open(Uri? uri) async {
    if (uri == null) return false;
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }
}
