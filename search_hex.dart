import 'dart:io';

void main() async {
  final file = File('e:\\Projects\\arbi_chief\\swimming2.xls');
  if (!file.existsSync()) return;
  final bytes = file.readAsBytesSync();
  
  // Category patterns (UTF-16LE)
  final catM35 = [0x27, 0x04, 0x33, 0x00, 0x35, 0x00]; // Ч35
  final catM49 = [0x27, 0x04, 0x34, 0x00, 0x39, 0x00]; // Ч49
  final catM50 = [0x27, 0x04, 0x35, 0x00, 0x30, 0x00]; // Ч50
  
  _searchPattern(bytes, catM35, 'Ч35');
  _searchPattern(bytes, catM49, 'Ч49');
  _searchPattern(bytes, catM50, 'Ч50');
}

void _searchPattern(List<int> bytes, List<int> pattern, String name) {
  print('\nSearching for $name...');
  for (int i = 0; i < bytes.length - pattern.length; i++) {
    bool match = true;
    for (int j = 0; j < pattern.length; j++) {
      if (bytes[i + j] != pattern[j]) {
        match = false;
        break;
      }
    }
    if (match) {
      print('Found at $i');
      _printContext(bytes, i);
    }
  }
}

void _printContext(List<int> bytes, int offset) {
    final start = (offset - 64).clamp(0, bytes.length);
    final end = (offset + 128).clamp(0, bytes.length);
    final context = bytes.sublist(start, end);
    print(context.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' '));
}
