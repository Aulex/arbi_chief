import 'dart:io';

void main() async {
  final file = File('e:\\Projects\\arbi_chief\\swimming2.xls');
  if (!file.existsSync()) return;
  final bytes = file.readAsBytesSync();
  
  final rk25 = [0x66, 0x00, 0x00, 0x00];
  final rk46 = [0xBA, 0x00, 0x00, 0x00];
  
  print('Searching for RK 25 (ЕРП)...');
  _find(bytes, rk25);
  print('Searching for RK 46 (ЕЦ)...');
  _find(bytes, rk46);
}

void _find(List<int> bytes, List<int> pattern) {
  for (int i = 0; i < bytes.length - 4; i++) {
    if (bytes[i] == pattern[0] && bytes[i+1] == pattern[1] && bytes[i+2] == pattern[2] && bytes[i+3] == pattern[3]) {
        print('Found at $i');
        _printCtx(bytes, i);
    }
  }
}

void _printCtx(List<int> bytes, int offset) {
    final start = (offset - 64).clamp(0, bytes.length);
    final end = (offset + 128).clamp(0, bytes.length);
    print(bytes.sublist(start, end).map((b) => b.toRadixString(16).padLeft(2, '0')).join(' '));
}
