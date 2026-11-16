// The no-network guard itself (installed for every test file by flutter_test_config.dart): HTTP through Dio / HttpClient and sockets to real
// hosts are refused and recorded, loopback sockets still work. Each test clears the record itself, because the guard's tearDown would
// otherwise (correctly) fail it.
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/no_network.dart';

void main() {
  tearDown(blockedNetworkAttempts.clear);

  test('Dio to the production API is refused before anything is sent, and recorded', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://api.solvexo.store'));
    await expectLater(dio.get('/api/pos/capabilities'), throwsA(isA<DioException>()));
    expect(blockedNetworkAttempts.single, contains('https://api.solvexo.store/api/pos/capabilities'));
  });

  test('a plain HttpClient request is refused', () async {
    await expectLater(HttpClient().getUrl(Uri.parse('https://staging.example.com/health')), throwsStateError);
    expect(blockedNetworkAttempts.single, 'GET https://staging.example.com/health');
  });

  test('a raw socket to a non-loopback host (e.g. a LAN printer) is refused', () async {
    await expectLater(Socket.connect('192.168.1.50', 9100), throwsStateError);
    expect(blockedNetworkAttempts.single, 'socket 192.168.1.50:9100');
  });

  test('loopback sockets still work (local fake servers)', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final s = await Socket.connect(InternetAddress.loopbackIPv4, server.port);
    await s.close();
    await server.close();
    expect(blockedNetworkAttempts, isEmpty);
  });
}
