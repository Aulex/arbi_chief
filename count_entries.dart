import 'dart:io';

void main() async {
  final file = File('e:\\Projects\\arbi_chief\\swimming2.xls');
  if (!file.existsSync()) return;
  final bytes = file.readAsBytesSync();
  
  // Sheet markers (BIFF8 BOUNDSHEET)
  final sheets = ['M<35', 'M>35', '>50', '<35', '>35', 'Staffet'];
  for (final s in sheets) {
    _countEntries(bytes, s);
  }
}

void _countEntries(List<int> bytes, String sheetName) {
  // We can't easily parse BIFF8 records, but we can search for the sheet name 
  // and then look for strings that look like names in the vicinity?
  // Actually, let's just use the string extraction but group by sheet if possible.
  // Sheets in BIFF8 are usually separate blocks.
}
