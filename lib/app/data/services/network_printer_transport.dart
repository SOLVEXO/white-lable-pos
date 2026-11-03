import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:solvexo_pos/app/data/services/thermal_printer_service.dart';

/// A validated network printer address.
class NetworkPrinterAddress {
  const NetworkPrinterAddress(this.host, this.port);
  final String host;
  final int port;

  static const defaultPort = 9100;

  /// Tests only: lets the fake printer listen on loopback.
  @visibleForTesting
  static bool allowLoopback = false;

  /// "192.168.1.50" or "192.168.1.50:9100" → address, or an error text in plain language. IPv4 only (what receipt printers use);
  /// loopback, 0.0.0.0, multicast and broadcast are refused — they can never be a printer on the shop network.
  static ({NetworkPrinterAddress? address, String? error}) parse(String hostInput, [String? portInput]) {
    var h = hostInput.trim();
    var p = (portInput ?? '').trim();
    final colon = h.split(':');
    if (colon.length == 2) {
      h = colon[0];
      if (p.isEmpty) p = colon[1];
    } else if (colon.length > 2) {
      return (address: null, error: 'Enter the printer\'s IPv4 address, like 192.168.1.50.');
    }
    final parts = h.split('.');
    final octets = parts.length == 4 ? parts.map((e) => RegExp(r'^\d{1,3}$').hasMatch(e) ? int.parse(e) : -1).toList() : <int>[];
    if (octets.length != 4 || octets.any((o) => o < 0 || o > 255)) {
      return (address: null, error: 'Enter the printer\'s IPv4 address, like 192.168.1.50.');
    }
    if (octets[0] == 0 || (octets[0] == 127 && !allowLoopback) || octets[0] >= 224) {
      return (address: null, error: 'That address cannot be a printer on your network.');
    }
    final port = p.isEmpty ? defaultPort : int.tryParse(p);
    if (port == null || port < 1 || port > 65535) return (address: null, error: 'The port must be a number from 1 to 65535 (receipt printers use 9100).');
    return (address: NetworkPrinterAddress(octets.join('.'), port), error: null);
  }

  /// The stored form.
  String get id => '$host:$port';

  static NetworkPrinterAddress? fromId(String id) => parse(id).address;
}

/// ESC/POS over a raw TCP socket (JetDirect / "port 9100") — the interface nearly every Ethernet/Wi-Fi receipt printer offers.
/// Works the same on Android and iOS (plain `dart:io` sockets, no native plugin). There is no acknowledgement in this protocol:
/// "written" means the printer's network stack accepted every byte; paper-out / cover-open cannot be detected.
class NetworkPrinterTransport implements PrinterTransport {
  NetworkPrinterTransport({
    this.connectTimeout = const Duration(seconds: 4),
    this.writeTimeout = const Duration(seconds: 10),
    this.settleDelay = const Duration(milliseconds: 250),
    Future<Socket> Function(String host, int port, Duration timeout)? connector,
  }) : _connector = connector ?? ((h, p, t) => Socket.connect(h, p, timeout: t));

  final Duration connectTimeout;
  final Duration writeTimeout;

  /// Printers drop the tail of a job if the socket is closed the instant the last byte is sent.
  final Duration settleDelay;
  final Future<Socket> Function(String host, int port, Duration timeout) _connector;
  Socket? _socket;

  /// No Bluetooth involved.
  @override
  Future<bool> get bluetoothEnabled async => true;
  @override
  Future<bool> get permissionGranted async => true;

  @override
  Future<bool> connect(String address) async {
    final a = NetworkPrinterAddress.fromId(address);
    if (a == null) return false;
    await disconnect();
    try {
      final s = await _connector(a.host, a.port, connectTimeout);
      s.setOption(SocketOption.tcpNoDelay, true);
      // Swallow the printer's own traffic (some send status bytes) so an unread socket buffer can't stall us.
      s.listen((_) {}, onError: (_) {}, cancelOnError: true);
      _socket = s;
      return true;
    } on SocketException {
      return false;
    } on TimeoutException {
      return false;
    }
  }

  @override
  Future<bool> write(List<int> bytes) async {
    final s = _socket;
    if (s == null) return false;
    try {
      s.add(bytes);
      await s.flush().timeout(writeTimeout);
      await Future<void>.delayed(settleDelay);
      return true;
    } on SocketException {
      return false;
    } on TimeoutException {
      return false;
    }
  }

  @override
  Future<void> disconnect() async {
    final s = _socket;
    _socket = null;
    if (s == null) return;
    try {
      await s.close().timeout(const Duration(seconds: 2));
    } catch (_) {
      s.destroy();
    }
  }

  /// Network printers are added by IP (or found by [NetworkPrinterDiscovery]); there is no "paired list".
  @override
  Future<List<PosPrinterOption>> discover() async => const [];
}

/// Best-effort discovery: probes TCP port 9100 on every host of the device's own /24 subnet. It finds typical home/shop
/// networks; it will NOT find printers on another subnet/VLAN, behind client isolation, or on a /23 and larger — add those by IP.
/// Bounded (254 probes, 24 at a time, 450 ms each) and cancellable.
class NetworkPrinterDiscovery {
  NetworkPrinterDiscovery({
    Future<List<String>> Function()? localAddresses,
    Future<bool> Function(String host, int port, Duration timeout)? probe,
    this.concurrency = 24,
    this.probeTimeout = const Duration(milliseconds: 450),
  })  : _localAddresses = localAddresses ?? _defaultLocalAddresses,
        _probe = probe ?? _defaultProbe;

  final Future<List<String>> Function() _localAddresses;
  final Future<bool> Function(String host, int port, Duration timeout) _probe;
  final int concurrency;
  final Duration probeTimeout;
  bool _cancelled = false;

  void cancel() => _cancelled = true;

  static Future<List<String>> _defaultLocalAddresses() async {
    final ifaces = await NetworkInterface.list(type: InternetAddressType.IPv4, includeLoopback: false, includeLinkLocal: false);
    // Wi-Fi first (en0 on iOS, wlan0 on Android), then Ethernet/others.
    ifaces.sort((a, b) => _rank(a.name).compareTo(_rank(b.name)));
    return [for (final i in ifaces) for (final a in i.addresses) if (_isPrivate(a.address)) a.address];
  }

  static int _rank(String n) => (n == 'en0' || n.startsWith('wlan')) ? 0 : n.startsWith('en') || n.startsWith('eth') ? 1 : 2;

  static bool _isPrivate(String ip) {
    final o = ip.split('.').map(int.tryParse).toList();
    if (o.length != 4 || o.any((e) => e == null)) return false;
    return o[0] == 10 || (o[0] == 172 && o[1]! >= 16 && o[1]! <= 31) || (o[0] == 192 && o[1] == 168);
  }

  static Future<bool> _defaultProbe(String host, int port, Duration timeout) async {
    try {
      final s = await Socket.connect(host, port, timeout: timeout);
      s.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Returns the hosts that accept a connection on [port]; [onProgress] gets (done, total). Null result = no usable local network.
  Future<List<String>?> scan({int port = NetworkPrinterAddress.defaultPort, void Function(int done, int total)? onProgress}) async {
    _cancelled = false;
    final locals = await _localAddresses();
    if (locals.isEmpty) return null;
    final me = locals.first;
    final prefix = me.substring(0, me.lastIndexOf('.'));
    final hosts = [for (var i = 1; i <= 254; i++) '$prefix.$i'].where((h) => h != me).toList();
    final found = <String>[];
    var next = 0, done = 0;
    Future<void> worker() async {
      while (!_cancelled && next < hosts.length) {
        final h = hosts[next++];
        if (await _probe(h, port, probeTimeout)) found.add(h);
        onProgress?.call(++done, hosts.length);
      }
    }

    await Future.wait(List.generate(concurrency, (_) => worker()));
    found.sort((a, b) => int.parse(a.split('.').last).compareTo(int.parse(b.split('.').last)));
    return found;
  }
}
