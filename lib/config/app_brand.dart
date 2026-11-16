/// Solvexo POS is ONE product, not a white-label: its name and theme are fixed here, never fetched or per-tenant.
/// The brand COLOURS live in the design system (`AppPalette`, lib/core/design/tokens/palette.dart).
/// (A store's own identity — name, logo, receipt header/footer, tax id — comes from that store's POS settings, not from here.)
class AppBrand {
  const AppBrand._();

  static const String appName = 'Solvexo';
  static const String posName = 'Solvexo POS';
  static const String marketplaceName = 'Solvexo';
}
