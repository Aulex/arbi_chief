import 'dart:io';

void main() async {
  final file = File('e:\\Projects\\arbi_chief\\swimming2.xls');
  if (!file.existsSync()) {
    print('File not found');
    return;
  }
  final bytes = file.readAsBytesSync();
  
  // Search for "ЕЦ" in various encodings
  _searchString(bytes, 'ЕЦ');
  _searchString(bytes, 'ЕРП');
}

void _searchString(List<int> bytes, String search) {
  print('\nSearching for "$search"...');
  // Simple check for UTF-8 or ASCII-ish
  final pattern = search.codeUnits;
  for (int i = 0; i < bytes.length - pattern.length; i++) {
    bool match = true;
    for (int j = 0; j < pattern.length; j++) {
      if (bytes[i + j] != pattern[j]) {
        match = false;
        break;
      }
    }
    if (match) {
      print('Found at offset $i');
      _printContext(bytes, i);
    }
  }
  
  // Also search for UTF-16LE (common in BIFF8)
  final pattern16 = <int>[];
  for (final c in search.runes) {
    pattern16.add(c & 0xFF);
    pattern16.add((c >> 8) & 0xFF);
  }
  
  for (int i = 0; i < bytes.length - pattern16.length; i++) {
    bool match = true;
    for (int j = 0; j < pattern16.length; j++) {
      if (bytes[i + j] != pattern16[j]) {
        match = false;
        break;
      }
    }
    if (match) {
      print('Found (UTF-16LE) at offset $i');
      _printContext(bytes, i);
    }
  }
}

void _printContext(List<int> bytes, int offset) {
    final start = (offset - 32).clamp(0, bytes.length);
    final end = (offset + 128).clamp(0, bytes.length);
    final context = bytes.sublist(start, end);
    print('Context around $offset:');
    print(context.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' '));
    // Try to decode as strings
    final printable = context.map((b) => (b >= 32 && b <= 126) ? String.fromCharCode(b) : '.').join();
    print('Printable: $printable');
}
