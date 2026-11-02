import 'package:flutter/material.dart';

/// Solvexo POS is ONE product, not a white-label: its name and theme are fixed here, never fetched or per-tenant.
/// (A store's own identity — name, logo, receipt header/footer, tax id — comes from that store's POS settings, not from here.)
class AppBrand {
  const AppBrand._();

  static const String appName = 'Solvexo';
  static const String posName = 'Solvexo POS';
  static const String marketplaceName = 'Solvexo';

  static const Color primary = Color(0xFFd97757);
  static const Color secondary = Color(0xFF6FBF4A);
  static const Color accent = Color(0xFFd97757);
}
