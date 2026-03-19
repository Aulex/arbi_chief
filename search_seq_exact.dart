import 'dart:io';

void main() async {
  final file = File('e:\\Projects\\arbi_chief\\swimming2.xls');
  if (!file.existsSync()) return;
  final bytes = file.readAsBytesSync();
  
  // RK values for [4, 5, 5, 7, 5, 13, 2]
  final seq = [0x12, 0x00, 0x00, 0x00, 0x16, 0x00, 0x00, 0x00, 0x16, 0x00, 0x00, 0x00, 0x1E, 0x00, 0x00, 0x00, 0x16, 0x00, 0x00, 0x00, 0x36, 0x00, 0x00, 0x00, 0x0A, 0x00, 0x00, 0x00];
  
  for (int i = 0; i < bytes.length - seq.length; i++) {
    bool match = true;
    for (int j = 0; j < seq.length; j++) {
      if (bytes[i + j] != seq[j]) {
        match = false;
        break;
      }
    }
    if (match) {
      print('Found sequence at $i');
    }
  }
}
