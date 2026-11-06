import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:solvexo_pos/app/modules/pos_home/controllers/pos_home_controller.dart';
import 'package:solvexo_pos/app/modules/pos_home/utils/cart_removal_undo.dart';
import 'package:solvexo_pos/app/modules/pos_home/widgets/category_sheet.dart';
import 'package:solvexo_pos/app/modules/pos_home/widgets/pos_barcode_sheet.dart';
import 'package:solvexo_pos/app/modules/pos_home/widgets/product_grid.dart';
import 'package:solvexo_pos/core/design/design.dart';

/// The left pane of the sale screen (the whole screen on a phone): header, search + barcode, offline bar,
/// category chips and the product grid.
class SaleCatalog extends StatelessWidget {
  const SaleCatalog({super.key, required this.c, required this.cartKey, this.bottomInset = Space.s4});
  final PosHomeController c;
  final GlobalKey cartKey;
  final double bottomInset;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(c: c),
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.s4, 0, Space.s4, Space.s3),
          child: _SearchArea(c: c),
        ),
        _StaleDataBar(c: c),
        Obx(() {
          final cats = c.categories;
          if (cats.length < 2) return const SizedBox.shrink();
          final selected = cats.indexOf(c.selectedCategoryId.value);
          return Padding(
            padding: const EdgeInsets.only(bottom: Space.s1),
            child: Row(
              children: [
                Expanded(
                  child: CategoryChips(
                    labels: [for (final id in cats) c.categoryLabel(id)],
                    selectedIndex: selected < 0 ? 0 : selected,
                    onSelected: (i) => c.selectCategory(cats[i]),
                  ),
                ),
                IconButton(key: const Key('allCategoriesButton'), tooltip: 'All categories', constraints: const BoxConstraints(minWidth: Space.minTouch, minHeight: Space.minTouch), icon: const Icon(Icons.grid_view_rounded), onPressed: () => CategorySheet.open(c)),
              ],
            ),
          );
        }),
        Expanded(child: ProductGrid(c: c, cartKey: cartKey, bottomInset: bottomInset)),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.c});
  final PosHomeController c;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.s4, Space.s3, Space.s2, Space.s2),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text('Quick Sale', style: context.type.headline.copyWith(color: p.textPrimary)),
            ),
          ),
          IconButton(
            key: const Key('heldSalesButton'),
            tooltip: 'Held sales',
            constraints: const BoxConstraints(minWidth: Space.minTouch, minHeight: Space.minTouch),
            icon: Icon(Icons.pause_circle_outline_rounded, color: p.textSecondary),
            onPressed: () {
              // a resume (from that screen) rebuilds the cart: a pending "Undo remove" must not survive it
              CartRemovalUndo.of(c).invalidate();
              c.openHeldSales();
            },
          ),
        ],
      ),
    );
  }
}

/// Shown while the catalogue / tax settings on screen came from the on-device cache (the server couldn't be reached):
/// says how old they are so nobody trusts a stale price without knowing. Cleared once fresh data loads.
class _StaleDataBar extends StatelessWidget {
  const _StaleDataBar({required this.c});
  final PosHomeController c;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Obx(() {
      if (!c.isDataStale) return const SizedBox.shrink();
      final at = c.catalogFromCache.value ? c.catalogUpdatedAt.value : c.settingsUpdatedAt.value;
      final when = at == null ? 'earlier' : DateFormat('d MMM, HH:mm').format(at.toLocal());
      return Container(
        key: const Key('staleDataBar'),
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(Space.s4, 0, Space.s4, Space.s3),
        padding: const EdgeInsets.fromLTRB(Space.s3, Space.s2, Space.s1, Space.s2),
        decoration: BoxDecoration(color: p.warningSoft, borderRadius: Radii.rMd),
        child: Row(
          children: [
            Icon(Icons.history_rounded, size: 18, color: p.warningFg),
            const SizedBox(width: Space.s2),
            Expanded(
              child: Text(
                'Offline — prices and tax from $when. They may be out of date; sales are checked against the server when they sync.',
                style: context.type.caption.copyWith(color: p.warningFg),
              ),
            ),
            TextButton(
              onPressed: c.refreshCatalogAndSettings,
              style: TextButton.styleFrom(minimumSize: const Size(Space.minTouch, Space.minTouch), foregroundColor: p.warningFg),
              child: Text('Refresh', style: context.type.label.copyWith(color: p.warningFg)),
            ),
          ],
        ),
      );
    });
  }
}


/// The search field and, while it is focused and empty, the cashier's recent searches (one tap runs one again).
class _SearchArea extends StatefulWidget {
  const _SearchArea({required this.c});
  final PosHomeController c;

  @override
  State<_SearchArea> createState() => _SearchAreaState();
}

class _SearchAreaState extends State<_SearchArea> {
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppSearchBar(
          controller: c.searchController,
          focusNode: _focus,
          hint: 'Search products or SKU',
          onChanged: c.onSearchChanged,
          onSubmitted: c.rememberSearch,
          onScan: () => Get.bottomSheet(PosBarcodeSheet(c: c), isScrollControlled: true, backgroundColor: Colors.transparent),
        ),
        Obx(() {
          // read both observables first (a short-circuit that skips them all leaves the Obx with nothing to listen to)
          final empty = c.searchText.value.isEmpty;
          final has = c.recentSearches.isNotEmpty;
          final show = _focus.hasFocus && empty && has;
          if (!show) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.only(top: Space.s2),
            child: Wrap(
              key: const Key('recentSearches'),
              spacing: Space.s2,
              runSpacing: Space.s1,
              children: [
                for (final term in c.recentSearches)
                  ActionChip(
                    key: Key('recent_$term'),
                    avatar: const Icon(Icons.history_rounded, size: 16),
                    label: Text(term),
                    onPressed: () => c.useRecentSearch(term),
                  ),
                TextButton(key: const Key('clearRecent'), onPressed: c.clearRecentSearches, child: const Text('Clear')),
              ],
            ),
          );
        }),
      ],
    );
  }
}
