import 'dart:io';

void main() {
  final file = File('lib/sports/streetball/streetball_report_builder.dart');
  var s = file.readAsStringSync();
  s = s.replaceAll('VolleyballReportBuilder', 'StreetballReportBuilder');
  s = s.replaceAll('VolleyballService', 'StreetballService');
  s = s.replaceAll('_volleyballService', '_streetballService');
  s = s.replaceAll('volleyball_scoring.dart', 'streetball_scoring.dart');
  s = s.replaceAll('volleyball_service.dart', 'streetball_service.dart');
  s = s.replaceAll('VolleyballStanding', 'StreetballStanding');
  s = s.replaceAll('Volleyball', 'Streetball');
  s = s.replaceAll('volleyball', 'streetball');
  file.writeAsStringSync(s);
  print('Done');
}
