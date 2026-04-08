import 'dart:io';
import 'dart:typed_data';

void main() async {
  final file = File('e:\\Projects\\arbi_chief\\swimming2.xls');
  if (!file.existsSync()) return;
  final bytes = file.readAsBytesSync();
  
  // Search for the number 46.0 (Double in BIFF8) and 46 (RK/Integer)
  _searchDouble(bytes, 46.0);
  _searchInt(bytes, 46);
  
  _searchDouble(bytes, 25.0);
  _searchInt(bytes, 25);
}

void _searchDouble(Uint8List bytes, double val) {
  final data = ByteData(8);
  data.setFloat64(0, val, Endian.little);
  final pattern = data.buffer.asUint8List();
  
  print('\nSearching for double $val...');
  for (int i = 0; i < bytes.length - 8; i++) {
    bool match = true;
    for (int j = 0; j < 8; j++) {
      if (bytes[i + j] != pattern[j]) {
        match = false;
        break;
      }
    }
    if (match) print('Found at $i');
  }
}

void _searchInt(Uint8List bytes, int val) {
    print('\nSearching for int $val (RK)...');
    // RK value for integer N is (N << 2) | 2
    final rk = (val << 2) | 2;
    final pattern = [rk & 0xFF, (rk >> 8) & 0xFF, (rk >> 16) & 0xFF, (rk >> 24) & 0xFF];
    
    for (int i = 0; i < bytes.length - 4; i++) {
      bool match = true;
      for (int j = 0; j < 4; j++) {
        if (bytes[i + j] != pattern[j]) {
          match = false;
          break;
        }
      }
      if (match) print('Found RK at $i');
    }
}
