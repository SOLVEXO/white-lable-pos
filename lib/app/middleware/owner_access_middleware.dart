import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:solvexo_pos/app/data/services/owner_gate.dart';
import 'package:solvexo_pos/app/routes/app_pages.dart';

/// Route guard for the owner-only screens (management, locations, devices, stock activity, customers list). On a registered
/// device it sends the user to the owner re-auth gate first and comes back to the requested screen afterwards; the backend
/// enforces the same split independently (a device token is refused on those routes).
class OwnerAccessMiddleware extends GetMiddleware {
  @override
  int? get priority => 2;

  @override
  RouteSettings? redirect(String? route) {
    if (!OwnerGate.required) return null;
    return RouteSettings(name: Routes.posOwnerGate, arguments: {'next': route});
  }
}
