String trafficStamp(DateTime time) {
  final t = time.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(t.day)}/${two(t.month)}/${t.year} à ${two(t.hour)}:${two(t.minute)}';
}
