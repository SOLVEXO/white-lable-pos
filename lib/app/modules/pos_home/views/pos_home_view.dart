import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:solvexo_pos/app/modules/pos_home/controllers/pos_home_controller.dart';
import 'package:solvexo_pos/app/modules/pos_home/widgets/cart_panel.dart';
import 'package:solvexo_pos/app/modules/pos_home/widgets/phone_cart_sheet.dart';
import 'package:solvexo_pos/app/modules/pos_home/widgets/sale_catalog.dart';
import 'package:solvexo_pos/core/design/design.dart';

/// The sale screen. Where the content is 700 px or wider (tablets, portrait or landscape) it is two panes: the catalogue
/// (search + barcode + categories + product grid) and the receipt cart with sticky totals and a large Charge button.
/// On a phone it is the catalogue with a live total pill that expands into the cart.
class PosHomeView extends StatelessWidget {
  final c = Get.put(PosHomeController());

  /// Where the fly-to-cart dot lands (the cart icon of whichever layout is showing).
  final GlobalKey _cartKey = GlobalKey();

  PosHomeView({super.key});

  static const double twoPaneMinWidth = 700;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      backgroundColor: p.background,
      body: SafeArea(
        bottom: false,
        child: LayoutBuilder(
          builder: (context, box) {
            if (box.maxWidth >= twoPaneMinWidth) {
              final paneWidth = box.maxWidth >= 1000 ? 400.0 : 350.0;
              return Row(
                children: [
                  Expanded(child: SaleCatalog(c: c, cartKey: _cartKey)),
                  SizedBox(
                    width: paneWidth,
                    child: Padding(padding: const EdgeInsets.fromLTRB(0, Space.s2, Space.s3, Space.s3), child: CartPanel(c: c, cartIconKey: _cartKey)),
                  ),
                ],
              );
            }
            return Stack(
              children: [
                SaleCatalog(c: c, cartKey: _cartKey, bottomInset: PhoneCartSheet.pillHeight + Space.s4),
                Positioned.fill(child: PhoneCartSheet(c: c, cartKey: _cartKey)),
              ],
            );
          },
        ),
      ),
    );
  }
}
