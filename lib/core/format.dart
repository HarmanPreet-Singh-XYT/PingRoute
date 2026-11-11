/// Human-readable formatting helpers shared by App Mode widgets.

String formatBytes(num bytes) {
  if (bytes < 1000) return '${bytes.round()} B';
  const units = ['KB', 'MB', 'GB', 'TB'];
  var value = bytes / 1000;
  var unit = 0;
  while (value >= 1000 && unit < units.length - 1) {
    value /= 1000;
    unit++;
  }
  final digits = value >= 100 ? 0 : (value >= 10 ? 1 : 2);
  return '${value.toStringAsFixed(digits)} ${units[unit]}';
}

String formatRate(num bytesPerSecond) {
  if (bytesPerSecond < 1) return '0 B/s';
  return '${formatBytes(bytesPerSecond)}/s';
}

/// `5d 13h`, `2h 04m`, `3m 12s`, `8s` — two units at most.
String formatDuration(Duration d) {
  if (d.inSeconds < 60) return '${d.inSeconds}s';
  if (d.inMinutes < 60) {
    return '${d.inMinutes}m ${(d.inSeconds % 60).toString().padLeft(2, '0')}s';
  }
  if (d.inHours < 24) {
    return '${d.inHours}h ${(d.inMinutes % 60).toString().padLeft(2, '0')}m';
  }
  return '${d.inDays}d ${d.inHours % 24}h';
}

/// Resident memory from `ps` (KiB) as a readable size.
String formatKilobytes(int kb) => formatBytes(kb * 1024);

String formatPercent(double value) =>
    value >= 10 ? '${value.round()}%' : '${value.toStringAsFixed(1)}%';
