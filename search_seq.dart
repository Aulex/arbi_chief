import 'dart:io';
import 'dart:typed_data';

void main() async {
  final file = File('e:\\Projects\\arbi_chief\\swimming2.xls');
  if (!file.existsSync()) return;
  final bytes = file.readAsBytesSync();
  
  // Sequence for ЕЦ: 4, 5, 5, 7, 5, 13, 2
  _searchRKSequence(bytes, [4, 5, 5, 7, 5, 13, 2]);
  
  // Sequence for ЕРП: 1, 2, 1, 4, 11, 5, 1
  _searchRKSequence(bytes, [1, 2, 1, 4, 11, 5, 1]);
}

void _searchRKSequence(Uint8List bytes, List<int> sequence) {
    print('\nSearching for sequence $sequence (RK)...');
    final patterns = sequence.map((val) => (val << 2) | 2).toList();
    
    // In BIFF8, RK values are 4 bytes each. They might be in a row.
    // However, they might be separated by BIFF8 record headers (6 bytes).
    // Let's look for the first value and then look for the others nearby.
    
    for (int i = 0; i < bytes.length - 4; i++) {
        final val = bytes[i] | (bytes[i+1] << 8) | (bytes[i+2] << 16) | (bytes[i+3] << 24);
        if (val == patterns[0]) {
            print('Found first value ${sequence[0]} at $i');
            // Scan subsequent ~128 bytes for the rest of the sequence
            int count = 1;
            int lastFound = i;
            for (int k = 1; k < sequence.length; k++) {
                bool found = false;
                for (int j = lastFound + 4; j < lastFound + 40; j++) {
                    if (j + 4 > bytes.length) break;
                    final nextVal = bytes[j] | (bytes[j+1] << 8) | (bytes[j+2] << 16) | (bytes[j+3] << 24);
                    if (nextVal == patterns[k]) {
                        count++;
                        lastFound = j;
                        found = true;
                        break;
                    }
                }
                if (!found) break;
            }
            if (count >= 3) {
                print('  Matched $count values in sequence starting at $i');
                _printContext(bytes, i);
            }
        }
    }
}

void _printContext(Uint8List bytes, int offset) {
    final start = (offset - 32).clamp(0, bytes.length);
    final end = (offset + 256).clamp(0, bytes.length);
    final context = bytes.sublist(start, end);
    print('  Context: ${context.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');
}
