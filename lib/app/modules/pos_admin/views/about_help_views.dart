import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:solvexo_pos/app/data/local/pos_local_caches.dart' show SettingsCacheStore;
import 'package:solvexo_pos/app/data/services/thermal_printer_service.dart';
import 'package:solvexo_pos/app/modules/pos/views/pos_hub_widgets.dart';
import 'package:solvexo_pos/app/modules/pos_home/widgets/pos_scan_camera_view.dart';
import 'package:solvexo_pos/app/modules/pos_reports/views/report_widgets.dart';
import 'package:solvexo_pos/config/app_env.dart';
import 'package:solvexo_pos/config/app_version.dart';
import 'package:solvexo_pos/core/design/design.dart';
import 'package:solvexo_pos/shared_prefrences/app_prefrences.dart';

/// G5.1 — About Solvexo POS: version and build, this till's store, which API environment it talks to, and the open-source licences.
class AboutView extends StatefulWidget {
  const AboutView({super.key, this.storeIdOverride, this.receiptBaseOverride});
  final String? storeIdOverride;
  final String? receiptBaseOverride;

  @override
  State<AboutView> createState() => _AboutViewState();
}

class _AboutViewState extends State<AboutView> {
  String? _storeId;
  String? _receiptBase;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final sid = widget.storeIdOverride ?? await AppPreferences.getStoreId();
    String? base = widget.receiptBaseOverride;
    if (base == null && sid != null && sid.isNotEmpty) {
      try {
        base = (await SettingsCacheStore.instance.load(sid))?.settings.receiptLinkBase;
      } catch (_) {}
    }
    if (mounted) {
      setState(() {
        _storeId = sid;
        _receiptBase = base;
      });
    }
  }

  static String envLabel(String env) => switch (env) { 'prod' => 'Production', 'staging' => 'Staging', 'local' => 'Local', _ => 'Development' };

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final host = Uri.tryParse(AppEnv.apiBaseUrl)?.host ?? AppEnv.apiBaseUrl;
    return HubScaffold(
      title: 'About',
      listKey: const Key('aboutList'),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: Space.s4),
          child: Column(
            children: [
              Text('Solvexo POS', style: context.type.headline.copyWith(color: p.textPrimary)),
              const SizedBox(height: Space.s1),
              Text('Version ${AppVersion.label}', key: const Key('aboutVersion'), style: context.type.body.copyWith(color: p.textSecondary)),
            ],
          ),
        ),
        HubSection('This till', [
          ReportRow(key: const Key('aboutBuild'), title: 'Version', value: AppVersion.version, detail: 'Build ${AppVersion.build}'),
          ReportRow(key: const Key('aboutStore'), title: 'Store id', value: (_storeId ?? '').isEmpty ? 'Not set up' : _storeId!, onTap: (_storeId ?? '').isEmpty ? null : () => Clipboard.setData(ClipboardData(text: _storeId!))),
          ReportRow(key: const Key('aboutEnv'), title: 'Environment', value: envLabel(AppEnv.name), detail: host),
          ReportRow(key: const Key('aboutReceiptBase'), title: 'Receipt links', value: _receiptBase == null ? 'Not received yet' : 'Ready', detail: _receiptBase == null ? 'Receipts print without a QR until this till has loaded the store settings online' : Uri.tryParse(_receiptBase!)?.host),
        ]),
        HubSection('Legal', [
          HubRow(key: const Key('aboutLicences'), icon: Icons.description_outlined, title: 'Open-source licences', subtitle: 'The software this app is built with', onTap: () => showLicensePage(context: context, applicationName: 'Solvexo POS', applicationVersion: AppVersion.label)),
        ]),
        Padding(
          padding: const EdgeInsets.all(Space.s4),
          child: Text('Tap the store id to copy it for support.', textAlign: TextAlign.center, style: context.type.caption.copyWith(color: p.textMuted)),
        ),
      ],
    );
  }
}

/// G5.1 — Help: short answers shipped with the app (no web page, no external service), grouped by task.
class HelpView extends StatelessWidget {
  const HelpView({super.key});

  static const topics = <(String, IconData, List<(String, String)>)>[
    ('Selling', Icons.point_of_sale_rounded, [
      ('Add an item', 'Tap it on the Sale screen, search by name, or scan its barcode. "Keep scanning" adds many items without closing the camera.'),
      ('Discounts and coupons', 'A manual discount above your limit asks for a manager. Coupons need a connection.'),
      ('Hold a sale', 'Hold keeps the cart for later; find it under Held sales.'),
    ]),
    ('Payments and receipts', Icons.receipt_long_rounded, [
      ('Split a payment', 'In the payment sheet choose Split and enter each part.'),
      ('Card payments', 'The till records the card amount and reference; the card machine confirms the payment.'),
      ('The receipt QR', 'The customer scans it to see the receipt. It works even for a sale made offline — it says "syncing" until the sale reaches the server.'),
      ('Share a receipt', 'Open the sale and tap Share link to send the receipt link through any app on this phone.'),
    ]),
    ('Offline', Icons.cloud_off_rounded, [
      ('No connection', 'Cash sales keep working and are saved on this device with an OFF- number. They sync by themselves when the connection is back. Do not ring them up again.'),
      ('Needs attention', 'If the server refuses an offline sale (for example the price changed), it appears under Needs attention for a manager.'),
    ]),
    ('Returns', Icons.assignment_return_outlined, [
      ('Return items', 'Open the sale → Return. Choose the items and quantities; the money goes back the way it was paid, or to store credit.'),
      ('Tax documents', 'Each return makes a credit note. The first print of an invoice or credit note says ORIGINAL; later prints say REPRINT.'),
    ]),
    ('Shifts and cash', Icons.payments_outlined, [
      ('Open and close a shift', 'Count the notes and coins when you open and close. A difference is recorded, never hidden.'),
      ('Cash in / out', 'Record every cash in or out with a reason. You can attach a photo of the slip.'),
    ]),
    ('Team', Icons.badge_outlined, [
      ('Clock in', 'Team → Clock. To clock someone else, they enter their PIN (or a manager does). This needs a connection.'),
      ('Forgot your PIN', 'Ask the owner to reset it from Registers & team.'),
    ]),
    ('Printer and scanner', Icons.print_outlined, [
      ('Set up a printer', 'Settings → Printer, drawer & sound. Then use Hardware check to print a test page.'),
      ('Scanner not reading', 'Hardware check → Test the scanner. A USB / Bluetooth scanner types into the box; the camera scans the same way.'),
    ]),
    ('Getting help', Icons.support_agent_rounded, [
      ('Who to contact', 'Your store owner first. For the app itself, the owner contacts Solvexo support from the web dashboard. Settings → About shows the version and store id support will ask for.'),
    ]),
  ];

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return HubScaffold(
      title: 'Help',
      listKey: const Key('helpList'),
      children: [
        for (final (title, icon, items) in topics)
          Card(
            key: Key('help_$title'),
            margin: const EdgeInsets.only(bottom: Space.s2),
            color: p.surface,
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: Radii.rLg, side: BorderSide(color: p.border)),
            child: ExpansionTile(
              leading: Icon(icon, color: p.accentFg),
              title: Text(title, style: context.type.subtitle.copyWith(color: p.textPrimary)),
              childrenPadding: const EdgeInsets.fromLTRB(Space.s4, 0, Space.s4, Space.s3),
              shape: const Border(),
              children: [
                for (final (q, a) in items)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Space.s3),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(q, style: context.type.body.copyWith(color: p.textPrimary, fontWeight: FontWeight.w600)),
                        const SizedBox(height: Space.s1),
                        Text(a, style: context.type.body.copyWith(color: p.textSecondary)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// G5.1 — Hardware check: print a test page, kick the cash drawer, and test the scanner (a USB / Bluetooth scanner types into the box; the camera too).
class HardwareCheckView extends StatefulWidget {
  const HardwareCheckView({super.key, this.printer, this.cameraScan});
  final ThermalPrinterService? printer;
  final Future<String?> Function()? cameraScan;

  @override
  State<HardwareCheckView> createState() => _HardwareCheckViewState();
}

class _HardwareCheckViewState extends State<HardwareCheckView> {
  final _scanBox = TextEditingController();
  String? _printResult, _drawerResult, _scanned;
  bool _printOk = false, _drawerOk = false, _busy = false;

  ThermalPrinterService? get _printer => widget.printer ?? (Get.isRegistered<ThermalPrinterService>() ? Get.find<ThermalPrinterService>() : null);

  @override
  void dispose() {
    _scanBox.dispose();
    super.dispose();
  }

  Future<void> _run(Future<String?> Function(ThermalPrinterService p) job, void Function(String msg, bool ok) done, String okText) async {
    final pr = _printer;
    if (pr == null || !pr.hasSavedPrinter) return setState(() => done('No printer is set up. Go to Settings → Printer, drawer & sound.', false));
    setState(() => _busy = true);
    final err = await job(pr);
    if (!mounted) return;
    setState(() {
      _busy = false;
      done(err ?? okText, err == null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.type;
    Widget result(String? text, bool ok, Key key) => text == null ? const SizedBox.shrink() : Padding(padding: const EdgeInsets.only(top: Space.s2), child: Text(text, key: key, style: t.body.copyWith(color: ok ? p.successFg : p.danger)));
    final pr = _printer;
    return HubScaffold(
      title: 'Hardware check',
      listKey: const Key('hardwareList'),
      children: [
        HubSection('Receipt printer', [
          Padding(
            padding: const EdgeInsets.all(Space.s3),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(pr?.hasSavedPrinter == true ? 'Printer: ${pr!.savedPrinterName.value} · ${pr.paperMm.value} mm' : 'No printer set up on this device.', key: const Key('hwPrinter'), style: t.body.copyWith(color: p.textSecondary)),
                const SizedBox(height: Space.s2),
                AppButton(key: const Key('hwTestPrint'), label: 'Print a test page', icon: Icons.print_outlined, variant: AppButtonVariant.secondary, loading: _busy, onPressed: _busy ? null : () => _run((x) => x.printTest(), (m, ok) { _printResult = m; _printOk = ok; }, 'Test page sent. Check that every column is visible and nothing is cut off.')),
                result(_printResult, _printOk, const Key('hwPrintResult')),
              ],
            ),
          ),
        ]),
        HubSection('Cash drawer', [
          Padding(
            padding: const EdgeInsets.all(Space.s3),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('The drawer is opened by the printer it is plugged into.', style: t.body.copyWith(color: p.textSecondary)),
                const SizedBox(height: Space.s2),
                AppButton(key: const Key('hwDrawer'), label: 'Open the cash drawer', icon: Icons.inbox_outlined, variant: AppButtonVariant.secondary, onPressed: _busy ? null : () => _run((x) => x.openDrawer(), (m, ok) { _drawerResult = m; _drawerOk = ok; }, 'Drawer signal sent.')),
                result(_drawerResult, _drawerOk, const Key('hwDrawerResult')),
              ],
            ),
          ),
        ]),
        HubSection('Barcode scanner', [
          Padding(
            padding: const EdgeInsets.all(Space.s3),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Tap the box and scan a barcode with a USB / Bluetooth scanner — it types the code and presses Enter. Or use the camera.', style: t.body.copyWith(color: p.textSecondary)),
                const SizedBox(height: Space.s2),
                AppTextField(key: const Key('hwScanBox'), label: 'Scan here', controller: _scanBox, onSubmitted: (v) => setState(() { _scanned = v.trim(); _scanBox.clear(); })),
                const SizedBox(height: Space.s2),
                AppButton(
                  key: const Key('hwCamera'),
                  label: 'Test the camera scanner',
                  icon: Icons.qr_code_scanner_rounded,
                  variant: AppButtonVariant.ghost,
                  onPressed: () async {
                    final code = await (widget.cameraScan ?? () async => await Get.to<String>(() => const PosScanCameraView()))();
                    if (code != null && mounted) setState(() => _scanned = code);
                  },
                ),
                if (_scanned != null)
                  Padding(
                    padding: const EdgeInsets.only(top: Space.s2),
                    child: Text(_scanned!.isEmpty ? 'Nothing was read.' : 'Read: $_scanned', key: const Key('hwScanResult'), style: t.body.copyWith(color: _scanned!.isEmpty ? p.danger : p.successFg)),
                  ),
              ],
            ),
          ),
        ]),
      ],
    );
  }
}
