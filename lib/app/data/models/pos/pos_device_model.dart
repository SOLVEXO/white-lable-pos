/// A registered POS terminal, as listed on the owner's Devices screen.
class PosDeviceModel {
  final String id;
  final String name;
  final String registerId;
  final String? platform;
  final bool revoked;
  final DateTime? lastSeenAt;
  final DateTime? revokedAt;

  const PosDeviceModel({
    required this.id,
    required this.name,
    required this.registerId,
    required this.revoked,
    this.platform,
    this.lastSeenAt,
    this.revokedAt,
  });

  factory PosDeviceModel.fromJson(Map<String, dynamic> j) => PosDeviceModel(
        id: (j['_id'] ?? j['id']).toString(),
        name: j['name'] as String? ?? 'Device',
        registerId: j['registerId']?.toString() ?? '',
        platform: j['platform'] as String?,
        revoked: j['status'] == 'revoked',
        lastSeenAt: j['lastSeenAt'] != null ? DateTime.tryParse(j['lastSeenAt'].toString()) : null,
        revokedAt: j['revokedAt'] != null ? DateTime.tryParse(j['revokedAt'].toString()) : null,
      );
}

/// What registering this terminal returns: its id and the long-lived token that replaces the owner's session.
class PosDeviceRegistration {
  final String deviceId;
  final String deviceToken;
  const PosDeviceRegistration({required this.deviceId, required this.deviceToken});
}
