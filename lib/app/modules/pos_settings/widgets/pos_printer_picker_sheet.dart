import 'package:solvexo_pos/app/components/custom_text.dart';
import 'package:solvexo_pos/app/data/services/network_printer_transport.dart';
import 'package:solvexo_pos/app/data/services/thermal_printer_service.dart';
import 'package:solvexo_pos/config/resources/app_colors.dart';
import 'package:solvexo_pos/utils/app_font_size.dart';
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

  Widget _networkPane() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const CustomText(text: 'Wi-Fi / Ethernet printer (ESC/POS, port 9100). The printer and this device must be on the same network.', fontSize: AppFontSize.tiny, color: AppColors.grey),
      const SizedBox(height: 10),
      TextField(key: const Key('netName'), controller: _name, decoration: const InputDecoration(labelText: 'Name (optional)', border: OutlineInputBorder(), isDense: true)),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(flex: 3, child: TextField(key: const Key('netHost'), controller: _host, keyboardType: TextInputType.number, onChanged: (_) => setState(() => _netError = null), decoration: InputDecoration(labelText: 'IP address', hintText: '192.168.1.50', border: const OutlineInputBorder(), isDense: true, errorText: _netError, errorMaxLines: 3))),
        const SizedBox(width: 8),
        Expanded(flex: 1, child: TextField(key: const Key('netPort'), controller: _port, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Port', border: OutlineInputBorder(), isDense: true))),
      ]),
      const SizedBox(height: 10),
      FilledButton(key: const Key('netSave'), onPressed: _saveNetwork, child: const Text('Save printer')),
      const SizedBox(height: 4),
      const CustomText(text: 'Then use "Print test page" in Printer settings to check it.', fontSize: AppFontSize.tiny, color: AppColors.grey),
      const Divider(height: 24),
      Row(children: [
        Expanded(child: OutlinedButton(key: const Key('netScan'), onPressed: _scanning ? () => _discovery.cancel() : _scan, child: Text(_scanning ? 'Stop searching' : 'Find printers on this network'))),
      ]),
      const SizedBox(height: 4),
      const CustomText(text: 'Best effort: checks this device\'s own network for printers listening on port 9100. It cannot see other subnets/VLANs or networks with device isolation — add those by IP above.', fontSize: AppFontSize.tiny, color: AppColors.grey),
      if (_scanning) Padding(padding: const EdgeInsets.only(top: 8), child: LinearProgressIndicator(value: _scanProgress)),
      if (_noNetwork) const Padding(padding: EdgeInsets.only(top: 8), child: CustomText(text: 'This device is not connected to a Wi-Fi/Ethernet network.')),
      if (_found != null && !_noNetwork && !_scanning)
        _found!.isEmpty
            ? const Padding(padding: EdgeInsets.only(top: 8), child: CustomText(text: 'No printers found. Check the printer is on and add it by IP address instead.', key: Key('netNoneFound')))
            : Column(children: [
                for (final h in _found!)
                  ListTile(
                    key: Key('found-$h'),
                    contentPadding: EdgeInsets.zero,
                    title: CustomText(text: h),
                    subtitle: const CustomText(text: 'Responds on port 9100', fontSize: AppFontSize.tiny, color: AppColors.grey),
                    onTap: () => setState(() {
                      _host.text = h;
                      _port.text = '${NetworkPrinterAddress.defaultPort}';
                      _netError = null;
                    }),
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
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 32 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.lightGrey2,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const CustomText(
            text: 'Select receipt printer',
            fontSize: AppFontSize.medium,
            fontWeight: FontWeight.w600,
          ),
          const SizedBox(height: 4),
          CustomText(
            text: ThermalPrinterService.platformNote,
            fontSize: AppFontSize.tiny,
            color: AppColors.grey,
          ),
          const SizedBox(height: 12),
          SegmentedButton<String>(
            key: const Key('printerKind'),
            segments: const [
              ButtonSegment(value: ThermalPrinterService.kindBluetooth, label: Text('Bluetooth'), icon: Icon(Icons.bluetooth)),
              ButtonSegment(value: ThermalPrinterService.kindNetwork, label: Text('Network (Wi-Fi/LAN)'), icon: Icon(Icons.wifi)),
            ],
            selected: {_kind},
            onSelectionChanged: (s) => setState(() => _kind = s.first),
          ),
          const SizedBox(height: 16),
          if (_kind == ThermalPrinterService.kindNetwork)
            _networkPane()
          else if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_bluetoothOff)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: CustomText(text: 'Bluetooth is off. Turn it on and try again.'),
            )
          else if (_options.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: CustomText(text: 'No paired Bluetooth devices found.'),
            )
          else
            ..._options.map(
              (o) => ListTile(
                contentPadding: EdgeInsets.zero,
                title: CustomText(text: o.name.isEmpty ? o.address : o.name),
                subtitle: CustomText(text: o.address, fontSize: AppFontSize.tiny, color: AppColors.grey),
                trailing: !widget.service.isNetworkPrinter && widget.service.savedPrinterAddress.value == o.address
                    ? const Icon(Icons.check_circle, color: AppColors.green)
                    : null,
                onTap: () async {
                  await widget.service.selectPrinter(o);
                  if (context.mounted) Get.back();
                },
              ),
            ),
          if (widget.service.hasSavedPrinter) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: () async {
                await widget.service.forgetPrinter();
                if (context.mounted) Get.back();
              },
              child: const CustomText(text: 'Forget saved printer', color: AppColors.red),
            ),
          ],
        ],
      ),
    );
  }
}
