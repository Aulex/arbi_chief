import 'dart:io';
import 'dart:typed_data';

void main() async {
  final file = File('e:\\Projects\\arbi_chief\\swimming2.xls');
  if (!file.existsSync()) return;
  final bytes = file.readAsBytesSync();
  
  _findTeamData(bytes, 'ЕРП');
  _findTeamData(bytes, 'ЕЦ');
}

void _findTeamData(Uint8List bytes, String teamName) {
  print('\n--- Search for team "$teamName" ---');
  final pattern = <int>[];
  for (final c in teamName.runes) {
    pattern.add(c & 0xFF);
    pattern.add((c >> 8) & 0xFF);
  }
  
  for (int i = 0; i < bytes.length - pattern.length; i++) {
    bool match = true;
    for (int j = 0; j < pattern.length; j++) {
      if (bytes[i + j] != pattern[j]) {
        match = false;
        break;
      }
    }
    if (match) {
      print('Found "$teamName" at offset $i');
      // Look for RK records nearby (within 200 bytes)
      _scanForRK(bytes, i - 100, i + 300);
    }
  }
}

void _scanForRK(Uint8List bytes, int start, int end) {
  start = start.clamp(0, bytes.length);
  end = end.clamp(0, bytes.length);
  print('Scanning RK records between $start and $end...');
  
  for (int i = start; i < end - 4; i++) {
    // RK record marker is 7E 02 (length=6, RK=4 bytes)
    // Or just look for 4-byte integers with the RK bit (bit 1 = 1)
    final val = bytes[i] | (bytes[i+1] << 8) | (bytes[i+2] << 16) | (bytes[i+3] << 24);
    if ((val & 0x02) == 0x02) {
      final actual = val >> 2;
      // Filter for reasonable score values (1-100)
      if (actual > 0 && actual < 200) {
        print('  Possible RK value at offset $i: $actual');
      }
    }
  }
}
