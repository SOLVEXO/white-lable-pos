import 'package:solvexo_pos/app/data/services/network_printer_transport.dart';
import 'package:solvexo_pos/app/data/services/thermal_printer_service.dart';
import 'package:solvexo_pos/core/design/design.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Bottom sheet to pick the receipt printer once and have it remembered: a paired/nearby Bluetooth printer, or a Wi-Fi/Ethernet
/// printer added by IP (port 9100) — see ThermalPrinterService's doc comment.
class PosPrinterPickerSheet extends StatefulWidget {
  final ThermalPrinterService service;
  final NetworkPrinterDiscovery? discovery;

  const PosPrinterPickerSheet({super.key, required this.service, this.discovery});

  @override
  State<PosPrinterPickerSheet> createState() => _PosPrinterPickerSheetState();
}

class _PosPrinterPickerSheetState extends State<PosPrinterPickerSheet> {
  bool _loading = true;
  bool _bluetoothOff = false;
  List<PosPrinterOption> _options = [];

  late String _kind = widget.service.isNetworkPrinter ? ThermalPrinterService.kindNetwork : ThermalPrinterService.kindBluetooth;
  late final NetworkPrinterDiscovery _discovery = widget.discovery ?? NetworkPrinterDiscovery();
  final _name = TextEditingController();
  final _host = TextEditingController();
  final _port = TextEditingController(text: '${NetworkPrinterAddress.defaultPort}');
  String? _netError;
  bool _scanning = false;
  double _scanProgress = 0;
  List<String>? _found; // null = not scanned yet
  bool _noNetwork = false;

  @override
  void initState() {
    super.initState();
    if (widget.service.isNetworkPrinter && widget.service.hasSavedPrinter) {
      final a = NetworkPrinterAddress.fromId(widget.service.savedPrinterAddress.value);
      if (a != null) {
        _host.text = a.host;
        _port.text = '${a.port}';
      }
      _name.text = widget.service.savedPrinterName.value;
    }
    _load();
  }

  @override
  void dispose() {
    _discovery.cancel();
    _name.dispose();
    _host.dispose();
    _port.dispose();
    super.dispose();
  }

  Future<void> _saveNetwork() async {
    final err = await widget.service.selectNetworkPrinter(name: _name.text, host: _host.text, port: _port.text);
    if (!mounted) return;
    if (err != null) {
      setState(() => _netError = err);
      return;
    }
    Get.back();
  }

  Future<void> _scan() async {
    setState(() {
      _scanning = true;
      _scanProgress = 0;
      _found = null;
      _noNetwork = false;
    });
    final hosts = await _discovery.scan(onProgress: (d, t) {
      if (mounted) setState(() => _scanProgress = d / t);
    });
    if (!mounted) return;
    setState(() {
      _scanning = false;
      _noNetwork = hosts == null;
      _found = hosts ?? const [];
    });
  }

  Widget _note(BuildContext context, String text, {Key? key}) =>
      Text(text, key: key, style: context.type.caption.copyWith(color: context.palette.textSecondary));

  Widget _networkPane(BuildContext context) {
    final p = context.palette;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _note(context, 'Wi-Fi / Ethernet printer (ESC/POS, port 9100). The printer and this device must be on the same network.'),
      const SizedBox(height: Space.s2),
      AppTextField(key: const Key('netName'), controller: _name, label: 'Name (optional)'),
      const SizedBox(height: Space.s2),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(flex: 3, child: AppTextField(key: const Key('netHost'), controller: _host, keyboardType: TextInputType.number, onChanged: (_) => setState(() => _netError = null), label: 'IP address', hint: '192.168.1.50')),
        const SizedBox(width: Space.s2),
        Expanded(flex: 1, child: AppTextField(key: const Key('netPort'), controller: _port, keyboardType: TextInputType.number, label: 'Port')),
      ]),
      if (_netError != null)
        Padding(
          padding: const EdgeInsets.only(top: Space.s1),
          child: Text(_netError!, style: context.type.caption.copyWith(color: p.dangerFg)),
        ),
      const SizedBox(height: Space.s2),
      AppButton(key: const Key('netSave'), label: 'Save printer', onPressed: _saveNetwork, expand: true),
      const SizedBox(height: Space.s1),
      _note(context, 'Then use "Print test page" in Printer settings to check it.'),
      Divider(height: Space.s5, color: p.border),
      AppButton(
        key: const Key('netScan'),
        label: _scanning ? 'Stop searching' : 'Find printers on this network',
        variant: AppButtonVariant.secondary,
        icon: _scanning ? Icons.stop_rounded : Icons.wifi_find_rounded,
        expand: true,
        onPressed: _scanning ? () => _discovery.cancel() : _scan,
      ),
      const SizedBox(height: Space.s1),
      _note(context, 'Best effort: checks this device\'s own network for printers listening on port 9100. It cannot see other subnets/VLANs or networks with device isolation — add those by IP above.'),
      if (_scanning)
        Padding(
          padding: const EdgeInsets.only(top: Space.s2),
          child: LinearProgressIndicator(value: _scanProgress, color: p.accent, backgroundColor: p.fill),
        ),
      if (_noNetwork)
        Padding(
          padding: const EdgeInsets.only(top: Space.s2),
          child: Text('This device is not connected to a Wi-Fi/Ethernet network.', style: context.type.body.copyWith(color: p.textPrimary)),
        ),
      if (_found != null && !_noNetwork && !_scanning)
        _found!.isEmpty
            ? Padding(
                padding: const EdgeInsets.only(top: Space.s2),
                child: Text('No printers found. Check the printer is on and add it by IP address instead.', key: const Key('netNoneFound'), style: context.type.body.copyWith(color: p.textPrimary)),
              )
            : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                for (final h in _found!)
                  Padding(
                    padding: const EdgeInsets.only(top: Space.s2),
                    child: AppListRow(
                      key: Key('found-$h'),
                      icon: Icons.print_rounded,
                      title: h,
                      subtitle: 'Responds on port 9100',
                      chevron: false,
                      onTap: () => setState(() {
                        _host.text = h;
                        _port.text = '${NetworkPrinterAddress.defaultPort}';
                        _netError = null;
                      }),
                    ),
                  ),
              ]),
    ]);
  }

  Future<void> _load() async {
    final enabled = await widget.service.isBluetoothEnabled;
    if (!enabled) {
      setState(() {
        _bluetoothOff = true;
        _loading = false;
      });
      return;
    }
    final options = await widget.service.listPairedPrinters();
    setState(() {
      _options = options;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    Widget message(String text) => Padding(
          padding: const EdgeInsets.symmetric(vertical: Space.s3),
          child: Text(text, style: context.type.body.copyWith(color: p.textPrimary)),
        );
    return AppSheetFrame(
      title: 'Select receipt printer',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _note(context, ThermalPrinterService.platformNote),
          const SizedBox(height: Space.s3),
          SegmentedButton<String>(
            key: const Key('printerKind'),
            segments: const [
              ButtonSegment(value: ThermalPrinterService.kindBluetooth, label: Text('Bluetooth'), icon: Icon(Icons.bluetooth)),
              ButtonSegment(value: ThermalPrinterService.kindNetwork, label: Text('Network (Wi-Fi/LAN)'), icon: Icon(Icons.wifi)),
            ],
            selected: {_kind},
            onSelectionChanged: (s) => setState(() => _kind = s.first),
          ),
          const SizedBox(height: Space.s4),
          if (_kind == ThermalPrinterService.kindNetwork)
            _networkPane(context)
          else if (_loading)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: Space.s6),
              child: Center(child: CircularProgressIndicator(color: p.accent)),
            )
          else if (_bluetoothOff)
            message('Bluetooth is off. Turn it on and try again.')
          else if (_options.isEmpty)
            message('No paired Bluetooth devices found.')
          else
            for (final o in _options)
              Padding(
                padding: const EdgeInsets.only(bottom: Space.s2),
                child: AppListRow(
                  icon: Icons.bluetooth_rounded,
                  title: o.name.isEmpty ? o.address : o.name,
                  subtitle: o.address,
                  chevron: false,
                  trailing: !widget.service.isNetworkPrinter && widget.service.savedPrinterAddress.value == o.address
                      ? Icon(Icons.check_circle, color: p.successFg)
                      : null,
                  onTap: () async {
                    await widget.service.selectPrinter(o);
                    if (context.mounted) Get.back();
                  },
                ),
              ),
          if (widget.service.hasSavedPrinter) ...[
            const SizedBox(height: Space.s2),
            AppButton(
              label: 'Forget saved printer',
              variant: AppButtonVariant.danger,
              icon: Icons.link_off_rounded,
              expand: true,
              onPressed: () async {
                await widget.service.forgetPrinter();
                if (context.mounted) Get.back();
              },
            ),
          ],
        ],
      ),
    );
  }
}
