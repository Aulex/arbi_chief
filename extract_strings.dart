import 'dart:io';

void main() async {
  final file = File('e:\\Projects\\arbi_chief\\swimming2.xls');
  if (!file.existsSync()) {
    print('File not found');
    return;
  }
  final bytes = await file.readAsBytes();
  final ascii = <int>[];
  for (final b in bytes) {
    if (b >= 32 && b <= 126) {
      ascii.add(b);
    } else {
      if (ascii.length >= 4) {
        print(ascii.map((c) => String.fromCharCode(c)).join());
      }
      ascii.clear();
    }
  }
}
