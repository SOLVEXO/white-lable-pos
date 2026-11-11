import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_catalog_admin_models.dart';
import 'package:solvexo_pos/app/modules/pos_catalog_admin/controllers/catalog_admin_common.dart';
import 'package:solvexo_pos/app/modules/pos_inventory/views/inv_widgets.dart';
import 'package:solvexo_pos/app/modules/pos_reports/controllers/reports_common.dart';
import 'package:solvexo_pos/app/modules/pos_reports/views/report_widgets.dart';
import 'package:solvexo_pos/core/design/design.dart';

/// A screen's controller: the one given (tests, an editor opened from its list), else one registered under a tag owned by the screen.
mixin CatOwnedController<W extends StatefulWidget, C extends CatalogAdminController> on State<W> {
  C? get given;
  C create();
  late final String _tag = '${C}_${identityHashCode(this)}';
  late final C c = given ?? Get.put<C>(create(), tag: _tag);

  @override
  void dispose() {
    if (given == null) Get.delete<C>(tag: _tag);
    super.dispose();
  }
}

/// The states every catalog-admin screen shares: offline with nothing read, loading, a read error (Try again), then the content under the
/// banners (refused role, offline writes, the outcome of the last write).
class CatStateBody extends StatelessWidget {
  const CatStateBody({super.key, required this.c, required this.subject, required this.builder});
  final CatalogAdminController c;
  final String subject;
  final List<Widget> Function(BuildContext) builder;

  @override
  Widget build(BuildContext context) => Obx(() {
    if (!reportsOnlineRx().value && !c.hasData) return ReportsNeedsInternet(subject: subject);
    if (!c.hasData && c.loading.value) return const Center(child: CircularProgressIndicator(key: Key('catLoading')));
    if (!c.hasData) return InvErrorState(message: c.error.value ?? 'Try again.', onRetry: c.load);
    return ListView(
      key: const Key('catList'),
      padding: const EdgeInsets.fromLTRB(Space.s4, Space.s2, Space.s4, Space.s8),
      children: [
        CatBanners(c: c),
        ...builder(context),
      ],
    );
  });
}

/// The refusal / offline / outcome banners (reads the controller's observables in its own Obx).
class CatBanners extends StatelessWidget {
  const CatBanners({super.key, required this.c});
  final CatalogAdminController c;

  @override
  Widget build(BuildContext context) => Obx(() {
    final p = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (c.forbidden.value)
          ReportInfo(key: const Key('catForbidden'), catalogErrorMessage('POS_ACTION_FORBIDDEN'), icon: Icons.lock_outline_rounded)
        else if (!reportsOnlineRx().value)
          const ReportInfo(key: Key('catOffline'), 'Offline. Changes need an internet connection.', warn: true),
        if (c.notice.value != null) ReportInfo(key: const Key('catNotice'), c.notice.value!, icon: Icons.check_circle_outline_rounded),
        if (c.saveError.value != null && !(c.forbidden.value && c.saveError.value == catalogErrorMessage('POS_ACTION_FORBIDDEN')))
          Container(
            key: const Key('catError'),
            margin: const EdgeInsets.only(bottom: Space.s2),
            padding: const EdgeInsets.all(Space.s3),
            decoration: BoxDecoration(color: p.dangerSoft, borderRadius: Radii.rMd),
            child: Text(c.saveError.value!, style: context.type.bodySmall.copyWith(color: p.dangerFg)),
          ),
      ],
    );
  });
}

/// A muted helper line.
class CatHint extends StatelessWidget {
  const CatHint(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: Space.s2),
    child: Text(text, style: context.type.bodySmall.copyWith(color: context.palette.textSecondary)),
  );
}

/// The empty state of a list.
class CatEmpty extends StatelessWidget {
  const CatEmpty({super.key, required this.icon, required this.title, this.message});
  final IconData icon;
  final String title;
  final String? message;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: Space.s6),
    child: EmptyState(key: const Key('catEmpty'), icon: icon, title: title, message: message),
  );
}

/// The decoration of the editors' text fields.
InputDecoration catField(String label, {String? hint, String? error, String? prefix}) => InputDecoration(labelText: label, hintText: hint, errorText: error, prefixText: prefix);

/// A search-and-pick sheet (products, variants, customers): debounced, the newest search wins, offline it says so.
class CatSearchSheet<T> extends StatefulWidget {
  const CatSearchSheet({super.key, required this.hint, required this.search, required this.tile, this.emptyQueryText, this.searchOnOpen = false});
  final String hint;

  /// null = the search failed
  final Future<List<T>?> Function(String q) search;
  final Widget Function(BuildContext, T, VoidCallback pick) tile;
  final String? emptyQueryText;
  final bool searchOnOpen;

  static Future<T?> open<T>({
    required String title,
    required String hint,
    required Future<List<T>?> Function(String q) search,
    required Widget Function(BuildContext, T, VoidCallback pick) tile,
    String? emptyQueryText,
    bool searchOnOpen = false,
  }) => AppBottomSheet.showGet<T>(
    CatSearchSheet<T>(hint: hint, search: search, tile: tile, emptyQueryText: emptyQueryText, searchOnOpen: searchOnOpen),
    title: title,
    scrollable: false,
  );

  @override
  State<CatSearchSheet<T>> createState() => _CatSearchSheetState<T>();
}

class _CatSearchSheetState<T> extends State<CatSearchSheet<T>> {
  final TextEditingController _q = TextEditingController();
  Timer? _timer;
  int _ticket = 0;
  bool _searching = false;
  bool _failed = false;
  bool _searched = false;
  List<T> _items = const [];

  @override
  void initState() {
    super.initState();
    if (widget.searchOnOpen) _run('');
  }

  @override
  void dispose() {
    _timer?.cancel();
    _q.dispose();
    super.dispose();
  }

  void _changed(String v) {
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 350), () => _run(v));
  }

  Future<void> _run(String q) async {
    final ticket = ++_ticket;
    if (q.trim().isEmpty && !widget.searchOnOpen) {
      setState(() {
        _items = const [];
        _searched = false;
        _failed = false;
      });
      return;
    }
    setState(() => _searching = true);
    final r = await widget.search(q);
    if (!mounted || ticket != _ticket) return;
    setState(() {
      _searching = false;
      _searched = true;
      _failed = r == null;
      _items = r ?? const [];
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.type;
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.6,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const Key('catSearchField'),
            controller: _q,
            autofocus: false,
            decoration: InputDecoration(hintText: widget.hint, prefixIcon: const Icon(Icons.search_rounded)),
            onChanged: _changed,
            onSubmitted: _run,
          ),
          const SizedBox(height: Space.s2),
          Expanded(
            child: Obx(() {
              final online = reportsOnlineRx().value;
              if (online && _searching) return const Center(child: CircularProgressIndicator());
              final status = !online
                  ? ('Searching needs an internet connection.', p.warningFg)
                  : _failed
                  ? ('The search did not work. Try again.', p.dangerFg)
                  : !_searched
                  ? (widget.emptyQueryText ?? 'Type to search.', p.textSecondary)
                  : _items.isEmpty
                  ? ('Nothing found.', p.textSecondary)
                  : null;
              if (status != null) {
                return Center(
                  child: Text(
                    status.$1,
                    key: const Key('catSearchStatus'),
                    textAlign: TextAlign.center,
                    style: t.bodySmall.copyWith(color: status.$2),
                  ),
                );
              }
              return ListView(
                key: const Key('catSearchResults'),
                children: [for (final x in _items) widget.tile(context, x, () => Get.back<T>(result: x))],
              );
            }),
          ),
        ],
      ),
    );
  }
}

/// A one-field sheet ("New category", "Rename"): resolves with the trimmed text, or null.
class CatTextSheet extends StatefulWidget {
  const CatTextSheet({super.key, required this.label, this.initial, required this.confirmLabel});
  final String label, confirmLabel;
  final String? initial;

  static Future<String?> open({required String title, required String label, String? initial, String confirmLabel = 'Save'}) => AppBottomSheet.showGet<String>(
    CatTextSheet(label: label, initial: initial, confirmLabel: confirmLabel),
    title: title,
  );

  @override
  State<CatTextSheet> createState() => _CatTextSheetState();
}

class _CatTextSheetState extends State<CatTextSheet> {
  late final TextEditingController _t = TextEditingController(text: widget.initial ?? '');

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      TextField(
        key: const Key('catTextField'),
        controller: _t,
        autofocus: true,
        decoration: catField(widget.label),
        onSubmitted: (v) => Get.back<String>(result: v.trim()),
      ),
      const SizedBox(height: Space.s3),
      AppButton(
        key: const Key('catTextConfirm'),
        label: widget.confirmLabel,
        onPressed: () => Get.back<String>(result: _t.text.trim()),
      ),
    ],
  );
}
