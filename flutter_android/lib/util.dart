/// Human-readable time helpers (port of TimeFormat.swift) and small formatters.
class Fmt {
  static String relative(DateTime date, {DateTime? now}) {
    final n = now ?? DateTime.now();
    final secs = n.difference(date).inSeconds;
    if (secs < 3600) {
      final m = secs < 1 ? 1 : secs ~/ 60;
      return '$m minute${m == 1 ? '' : 's'} ago';
    }
    if (secs < 7200) {
      final h = secs ~/ 3600;
      return '$h hour${h == 1 ? '' : 's'} ago';
    }
    if (date.year == n.year && date.month == n.month && date.day == n.day) {
      final hh = date.hour.toString().padLeft(2, '0');
      final mm = date.minute.toString().padLeft(2, '0');
      return 'today at $hh:$mm';
    }
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul',
      'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final hh = date.hour.toString().padLeft(2, '0');
    final mm = date.minute.toString().padLeft(2, '0');
    final gmtH = date.timeZoneOffset.inHours;
    final gmtM = date.timeZoneOffset.inMinutes.abs() % 60;
    final sign = gmtH >= 0 ? 'GMT+' : 'GMT-';
    final mm2 = gmtM.toString().padLeft(2, '0');
    return '${months[date.month - 1]} ${date.day} at $hh:$mm '
        '$sign${gmtH.abs()}:$mm2';
  }

  static String duration(Duration? d) {
    if (d == null) return '—';
    final s = d.inSeconds;
    if (s < 60) return '${s}s';
    final h = s ~/ 3600;
    final m = (s % 3600) ~/ 60;
    final sec = s % 60;
    if (h > 0) return '${h}h ${m}min ${sec}s';
    if (m > 0) return '${m}min ${sec}s';
    return '${s}s';
  }
}