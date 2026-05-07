void main() {
  final input = """18	0,9856	0,9895
19	0,9914	0,9948
20	1	1
21	1	1
22	1	1
23	1	1
24	1	1
25	1	1
26	1	1""";

  final lines = input.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
  for (final line in lines) {
    var parts = line.split(RegExp(r'[\t;]+')).map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    if (parts.length == 1) {
      parts = line.split(RegExp(r'\s+')).map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    }
    if (parts.length >= 3) {
      final age = int.tryParse(parts[0]);
      final men = double.tryParse(parts[1].replaceAll(',', '.'));
      final women = double.tryParse(parts[2].replaceAll(',', '.'));
      final valid = age != null && men != null && women != null && age > 0;
      print('Parsed: age=$age, men=$men, women=$women, valid=$valid');
    } else {
      print('Failed to split properly: $parts');
    }
  }
}
