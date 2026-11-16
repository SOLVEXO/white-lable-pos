#!/usr/bin/env python3
"""DEV ONLY (G6.3). Writes docs/pos-blueprint/UI_CONSISTENCY_AUDIT.md: every route, tab, sheet and dialog of the app with its design-system status.

Status of a screen = the design-guard violations (test/design_guard_baseline.txt) summed over the screen's file and every module / component file it
imports (controllers excluded, except where a controller builds a dialog or sheet itself):
  New   = 0 violations
  Mixed = violations, but the files also use the design system (context.palette / context.type / design components)
  Old   = violations and no design-system use at all
Regenerate after each restyled group:  DESIGN_GUARD_WRITE=1 flutter test test/design_guard_test.dart && python3 tool/ui_audit.py
"""
import os
import re
from collections import Counter

ROOT = os.path.join(os.path.dirname(__file__), '..')
os.chdir(ROOT)

# app route name -> blueprint screen id (Solvexo_POS_UI_Developer_Package, app/index.html); None = no blueprint equivalent
BLUEPRINT = {
    'designGallery': None, 'splashScreen': 'splash', 'onboarding': 'welcome', 'posLogin': 'login', 'sellerOnboarding': None,
    'sellerStores': 'store-select', 'sellerHome': 'staff', 'posHome': 'pos', 'sellerPosManagement': 'staff', 'sellerPosLocations': None,
    'posDeviceSetup': 'device-setup', 'posOwnerGate': None, 'posDeleteAccount': None, 'posDevices': 'register-settings', 'posOrders': 'orders',
    'posPinLogin': 'pin', 'posOpenRegister': 'open-shift', 'posHeldSales': 'parked-sales', 'posDailyReport': 'sales-report', 'posProducts': 'products',
    'posSettings': 'settings', 'posSaleDetail': 'order-detail', 'posTaxInvoice': 'invoice', 'posCatalog': 'catalog-product', 'posTaxProfile': 'tax-settings',
    'posReturn': 'return-start', 'posSessionReport': 'shift-summary', 'posSessionHistory': 'shift-summary', 'posAuditLog': None, 'posRangeReport': 'sales-report',
    'posStockOverview': 'inventory-overview', 'posStockList': 'stock-list', 'posStockDetail': 'stock-detail', 'posStockMovements': 'inventory-history',
    'posStockCount': 'stock-count', 'posStockLimits': 'low-stock', 'posInventory': 'stock-list', 'posNeedsAttention': None, 'posKyb': 'payments-settings',
    'posPaymentsSetup': 'payments-settings', 'posIntegrations': 'integrations', 'posOfflineMode': 'offline', 'posPermissions': 'permissions',
    'posStockActivity': 'inventory-history', 'posCustomers': 'customers', 'posCustomerDirectory': 'customers', 'posCustomerProfile': 'customer-profile',
    'posSupply': 'suppliers', 'posSupplyOrders': 'purchase-orders', 'posSupplyOrder': 'purchase-order-detail', 'posSupplyOrderForm': 'new-purchase-order',
    'posSupplyReceive': 'receive-stock', 'posSupplySuppliers': 'suppliers', 'posSupplySupplier': 'supplier-profile', 'posSupplyPayables': 'supplier-payment',
    'posSupplyLedger': 'supplier-payment', 'posCash': 'expenses', 'posCashExpenses': 'expenses', 'posCashExpense': 'expense-detail', 'posCashDaybook': 'daybook',
    'posTeamClock': 'clock-in', 'posTeamAttendance': 'attendance', 'posTeamRecord': 'attendance', 'posTeamRoster': None, 'posTeamReport': 'attendance',
    'posPulse': 'reports-home', 'posReports': 'reports-home', 'posReport': 'sales-report', 'posStoreTimeZone': 'store-profile', 'posDayOrders': 'orders',
    'posRoles': 'roles', 'posSettingsHub': 'settings', 'posReceiptDesigner': 'receipt-settings', 'posAlertSettings': 'notifications',
    'posSecuritySettings': 'security', 'posBackupSync': 'backup-sync', 'posTransfers': 'transfer', 'posExpiry': 'batch-expiry', 'posCatalogAdmin': 'products',
    'posModifierGroups': 'modifiers', 'posPriceBooks': 'pricebook', 'posCatalogNewProduct': 'product-form', 'posCatalogCategories': 'categories',
    'posCatalogImport': 'bulk-import', 'posPlanInactive': None, 'posPlanStatus': None,
}
TABS = [('Home (dashboard)', 'PosHomeTabView', 'reports-home'), ('Sell', 'PosHomeView', 'pos'), ('Orders', 'PosOrdersView', 'orders'),
        ('Stock', 'PosStockHubView', 'inventory-overview'), ('More', 'PosMoreHubView', 'settings')]

DS = re.compile(r'context\.palette|context\.type|\bSpace\.|\bRadii\.|AppButton\(|AppCard\(|AppBottomSheet|AppDialog|EmptyState|StatusBadge|AmountText|'
                r'SectionHeader|AppShell|AppPage|AppListRow|AppBanner')
SHOW = re.compile(r'showModalBottomSheet|showDialog|Get\.dialog|Get\.bottomSheet|Get\.defaultDialog|AppBottomSheet\.show|AppDialog\.')
IMP = re.compile(r"import 'package:solvexo_pos/([^']+)'|import '([^':]+\.dart)'")

base = {}
for line in open('test/design_guard_baseline.txt'):
    if line.startswith('#') or not line.strip():
        continue
    p, n = line.split()
    base[p] = int(n)

files = sorted(os.path.join(d, f) for d, _, fs in os.walk('lib') for f in fs if f.endswith('.dart'))
src = {f: open(f).read() for f in files}
cls = {}
for f, s in src.items():
    for m in re.finditer(r'^class (\w+)', s, re.M):
        cls[m.group(1)] = f


def deps(f, seen=None):
    seen = seen if seen is not None else set()
    if f in seen or f not in src:
        return seen
    seen.add(f)
    for m in IMP.finditer(src[f]):
        t = 'lib/' + m.group(1) if m.group(1) else os.path.normpath(os.path.join(os.path.dirname(f), m.group(2)))
        if t.startswith(('lib/app/modules/', 'lib/app/components/', 'lib/core/widgets/')) and t.split('/')[-2] not in ('controllers', 'bindings'):
            deps(t, seen)
    return seen


def status(f):
    ds = deps(f)
    v = sum(base.get(x, 0) for x in ds)
    if v == 0:
        return 'New', 0, []
    d = sum(len(DS.findall(src[x])) for x in ds)
    return ('Mixed' if d else 'Old'), v, sorted(x for x in ds if base.get(x))


pages = src['lib/app/routes/app_pages.dart']
routes = []
for b in re.split(r'GetPage\(', pages)[1:]:
    n = re.search(r'name:\s*Routes\.(\w+)', b)
    p = re.search(r'page:\s*\([^)]*\)\s*(?:=>|\{[^}]*?return)\s*(?:const\s+)?(\w+)', b)
    if n and p:
        routes.append((n.group(1), p.group(1)))

rows = []
for name, c in routes:
    f = cls.get(c)
    st, v, dirty = status(f) if f else ('?', 0, [])
    rows.append(('route', name, c, f, st, v, dirty, BLUEPRINT.get(name)))
for label, c, bp in TABS:
    f = cls[c]
    st, v, dirty = status(f)
    rows.append(('tab', label, c, f, st, v, dirty, bp))

sheets = []
for f in files:
    if f.startswith('lib/core/design/'):
        continue
    s = src[f]
    names = [m.group(1) for m in re.finditer(r'^class (\w+(?:Sheet|Dialog|Picker|Popup|Overlay|Banner))\b', s, re.M)]
    opens = bool(SHOW.search(s))
    if not names and not (opens and base.get(f)):
        continue
    if not names and '/views/' in f:
        continue  # a view that opens a sheet is counted with the view; only its own sheet classes are listed
    v = base.get(f, 0)
    d = len(DS.findall(s))
    st = 'New' if v == 0 else ('Mixed' if d else 'Old')
    sheets.append((f, names or ['(dialogs / sheets built inline)'], st, v))

route_counts = Counter(r[4] for r in rows)
sheet_counts = Counter(s[2] for s in sheets)
total = sum(base.values())


def rel(f):
    return f.replace('lib/app/modules/', '').replace('lib/app/', '').replace('lib/', '')


out = []
w = out.append
w('# UI consistency audit (G6.3)\n')
w('Generated by `tool/ui_audit.py` from the design guard (`test/design_guard_test.dart`). Re-run it after each restyled group.\n')
w('**Statuses** (a screen counts the violations of its own file and every module / component file it imports):')
w('- **New**: no raw colour, `Colors.*`, hard-coded font size or family, ad-hoc `TextStyle`, `AppColors`, `CustomText` or `.sp`.')
w('- **Mixed**: uses the design system, but still has some of the above.')
w('- **Old**: none of the design system; the legacy kit only.\n')
w(f'**Design guard baseline:** {len(base)} files, {total} violations (must reach 0 by the G6.3 close-out).\n')
w('## Summary\n')
w('| | New | Mixed | Old | Total |')
w('|---|---|---|---|---|')
w(f"| Routes + tabs | {route_counts['New']} | {route_counts['Mixed']} | {route_counts['Old']} | {len(rows)} |")
w(f"| Sheets, dialogs, overlays, banners | {sheet_counts['New']} | {sheet_counts['Mixed']} | {sheet_counts['Old']} | {len(sheets)} |\n")
w('## Old and Mixed screens (what Step 3 restyles)\n')
w('| Screen | Route / tab | Status | Violations | Blueprint | Files still to fix |')
w('|---|---|---|---|---|---|')
for kind, name, c, f, st, v, dirty, bp in sorted(rows, key=lambda r: (r[4] != 'Old', -r[5])):
    if st == 'New':
        continue
    w(f"| {c} | {'tab ' if kind == 'tab' else ''}`{name}` | {st} | {v} | {bp or 'no blueprint equivalent'} | {', '.join('`' + rel(x) + '`' for x in dirty)} |")
w('\n## Every route and tab\n')
w('| Route / tab | Screen | File | Status | Blueprint |')
w('|---|---|---|---|---|')
for kind, name, c, f, st, v, dirty, bp in rows:
    w(f"| {'tab ' if kind == 'tab' else ''}`{name}` | {c} | `{rel(f) if f else '?'}` | {st} | {bp or 'no blueprint equivalent'} |")
w('\n## Sheets, dialogs, overlays and banners\n')
w('Classes named *Sheet / *Dialog / *Picker / *Popup / *Overlay / *Banner, and non-view files that build dialogs or sheets inline. Sheets that '
  'live inside a view file are listed with that view above as well.\n')
w('| File | Classes | Status | Violations |')
w('|---|---|---|---|')
for f, names, st, v in sorted(sheets, key=lambda s: (s[2] == 'New', s[0])):
    w(f"| `{rel(f)}` | {', '.join(names[:5])} | {st} | {v} |")
w('\n## Other files still on the legacy kit\n')
w('Shared components, utilities and controllers with violations that no single screen owns (they disappear as the screens above are restyled, '
  'or are deleted once unused):\n')
owned = set(x for r in rows for x in r[6]) | set(s[0] for s in sheets)
for f in sorted(base):
    if f not in owned:
        w(f'- `{rel(f)}` — {base[f]}')
open('docs/pos-blueprint/UI_CONSISTENCY_AUDIT.md', 'w').write('\n'.join(out) + '\n')
print(dict(route_counts), dict(sheet_counts), len(base), total)
