// Environment configs (config/env/*.json, passed with --dart-define-from-file): only prod.json may point at the production API, and staging —
// which has no API of its own yet — refuses to start instead of quietly using production.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:solvexo_pos/config/app_env.dart';

Map<String, dynamic> _read(File f) => (jsonDecode(f.readAsStringSync()) as Map).cast<String, dynamic>();

void main() {
  final configs = Directory('config/env').listSync().whereType<File>().where((f) => f.path.endsWith('.json')).toList();

  test('there are config files to check, and prod.json targets the production API over https', () {
    expect(configs.map((f) => f.uri.pathSegments.last), containsAll(['prod.json', 'staging.json', 'dev.json', 'local.json']));
    final prod = Uri.parse(_read(File('config/env/prod.json'))['API_BASE_URL'] as String);
    expect([prod.scheme, prod.host], ['https', AppEnv.productionApiHost]);
  });

  test('no config other than prod.json contains the production API address (anywhere in the file)', () {
    final offenders = [
      for (final f in configs)
        if (!f.path.endsWith('/prod.json') && f.readAsStringSync().toLowerCase().contains(AppEnv.productionApiHost)) f.path,
    ];
    expect(offenders, isEmpty, reason: 'only prod.json may point at ${AppEnv.productionApiHost}');
  });

  test('staging.json has no API yet, and a staging build or run with it refuses to start (debug and release) with a clear message', () {
    final staging = _read(File('config/env/staging.json'));
    expect(staging['APP_ENV'], 'staging');
    final url = staging['API_BASE_URL'] as String;
    for (final release in [false, true]) {
      final problem = AppEnv.validate(release: release, env: 'staging', baseUrl: url);
      expect(problem, startsWith('No staging API configured'), reason: 'release=$release');
    }
    // and even if someone puts the production address back into it, staging still refuses
    expect(AppEnv.validate(release: true, env: 'staging', baseUrl: 'https://${AppEnv.productionApiHost}'), startsWith('No staging API configured'));
    // a real staging URL, once ops provide one, is accepted
    expect(AppEnv.validate(release: true, env: 'staging', baseUrl: 'https://staging-api.example.com'), isNull);
  });

  test('the other configs still validate (prod in release; dev / local in debug)', () {
    String? v(String name, {required bool release}) {
      final c = _read(File('config/env/$name'));
      return AppEnv.validate(release: release, env: c['APP_ENV'] as String, baseUrl: c['API_BASE_URL'] as String);
    }

    expect(v('prod.json', release: true), isNull);
    expect(v('dev.json', release: false), isNull);
    expect(v('local.json', release: false), isNull);
  });
}
