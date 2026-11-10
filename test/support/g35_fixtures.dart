import 'package:solvexo_pos/app/data/models/pos/pos_cash_models.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_inventory_models.dart';

const usd = InvCur('USD', 2);
const jpy = InvCur('JPY', 0);
const kwd = InvCur('KWD', 3);

Map<String, dynamic> cashConfigJson({String currency = 'USD', int exponent = 2}) => {
  'currency': currency,
  'currencyExponent': exponent,
  'cashInCategories': ['float_topup', 'owner_injection', 'other_in'],
  'cashOutCategories': ['bank_deposit', 'safe_drop', 'petty', 'owner_draw', 'other_out'],
  'expenseCategories': ['rent', 'utilities', 'salaries', 'supplies', 'transport', 'repairs', 'marketing', 'meals', 'taxes_fees', 'other'],
  'expenseMethods': ['cash', 'bank', 'other'],
  'noteRequiredFor': ['other_in', 'other_out'],
  'cashOutApprovalAboveMinor': 5000,
  'expenseApprovalAboveMinor': 10000,
};

CashConfig cashConfig({String currency = 'USD', int exponent = 2}) => CashConfig.fromJson(cashConfigJson(currency: currency, exponent: exponent));

Map<String, dynamic> expenseJson({
  String id = 'x1',
  String number = 'EXP-000001',
  String category = 'rent',
  int amountMinor = 12000,
  String method = 'cash',
  String status = 'recorded',
  bool hasReceipt = false,
  String? decisionNote,
  String? payee = 'Landlord',
  String receiptMime = 'image/jpeg',
}) => {
  'id': id,
  'number': number,
  'category': category,
  'amountMinor': amountMinor,
  'currency': 'USD',
  'currencyExponent': 2,
  'payee': payee,
  'method': method,
  'note': 'November',
  'occurredAt': '2026-11-09T09:00:00.000Z',
  'sessionId': 'se1',
  'employeeId': 'e1',
  'employeeName': 'Sam',
  'status': status,
  'decisionNote': decisionNote,
  'hasReceipt': hasReceipt,
  'receiptMimeType': hasReceipt ? receiptMime : null,
};

Expense expense({
  String id = 'x1',
  String status = 'recorded',
  bool hasReceipt = false,
  int amountMinor = 12000,
  String category = 'rent',
  String? decisionNote,
  String number = 'EXP-000001',
  String? payee = 'Landlord',
  String receiptMime = 'image/jpeg',
}) => Expense.fromJson(
  expenseJson(id: id, status: status, hasReceipt: hasReceipt, amountMinor: amountMinor, category: category, decisionNote: decisionNote, number: number, payee: payee, receiptMime: receiptMime),
);

ExpenseList expenseList(List<Expense> items, {Map<String, int>? totals}) =>
    ExpenseList(expenses: items, totalsByCategoryMinor: totals ?? {for (final e in items.where((e) => e.status != 'rejected')) e.category: e.amountMinor}, cur: usd);

ExpenseSaved expenseSaved({bool duplicate = false}) => ExpenseSaved(expense: expense(), duplicate: duplicate);

CashMovementResult movementResult({bool duplicate = false}) => CashMovementResult(type: 'cash_in', category: 'float_topup', amountMinor: 1000, duplicate: duplicate, cur: usd);

DaybookShift shift({String id = 'se1', bool reconciled = true, int unreconciled = 0, bool closed = true, String? employee = 'Sam', List<DaybookLine>? lines}) => DaybookShift(
  sessionId: id,
  status: closed ? 'closed' : 'open',
  registerName: 'Main till',
  employeeName: employee,
  openedAt: DateTime(2026, 11, 9, 9),
  closedAt: closed ? DateTime(2026, 11, 9, 18) : null,
  openingMinor: 10000,
  cashSalesMinor: 2500,
  cashRefundsMinor: 500,
  cashInMinor: 1000,
  cashOutMinor: 2000,
  expensesMinor: 300,
  expectedCashMinor: 10700,
  countedMinor: closed ? 10650 : null,
  varianceMinor: closed ? -50 : null,
  reconciled: reconciled,
  unreconciledMinor: unreconciled,
  lines:
      lines ??
      [
        DaybookLine(type: 'opening', label: 'Opening float', amountMinor: 10000, runningMinor: 10000, at: DateTime(2026, 11, 9, 9), refType: 'session', refId: id),
        DaybookLine(type: 'cash_sale', label: 'Sale S-0001', amountMinor: 2500, runningMinor: 12500, at: DateTime(2026, 11, 9, 9, 30), refType: 'sale', refId: 'sale1', employeeName: 'Sam'),
        DaybookLine(
          type: 'cash_refund',
          label: 'Refund R-1',
          amountMinor: -500,
          runningMinor: 12000,
          at: DateTime(2026, 11, 9, 10),
          refType: 'refund',
          refId: 'rf1',
          saleId: 'sale1',
          employeeName: 'Sam',
        ),
        DaybookLine(type: 'cash_in', label: 'Cash in — float topup', amountMinor: 1000, runningMinor: 13000, at: DateTime(2026, 11, 9, 11), refType: 'cash_movement', refId: 'req1'),
        DaybookLine(type: 'cash_out', label: 'Cash out — bank deposit', amountMinor: -2000, runningMinor: 11000, at: DateTime(2026, 11, 9, 12), refType: 'cash_movement', refId: 'req2'),
        DaybookLine(
          type: 'expense',
          label: 'Expense EXP-000001 — rent (Landlord)',
          amountMinor: -300,
          runningMinor: 10700,
          at: DateTime(2026, 11, 9, 13),
          refType: 'expense',
          refId: 'x1',
          employeeName: 'Ali',
        ),
      ],
);

Daybook daybook({List<DaybookShift>? shifts, bool own = false, InvCur? cur = usd}) {
  final list = shifts ?? [shift()];
  return Daybook(
    shifts: list,
    totals: DaybookTotals(
      cashSalesMinor: list.length * 2500,
      cashRefundsMinor: list.length * 500,
      cashInMinor: list.length * 1000,
      cashOutMinor: list.length * 2000,
      expensesMinor: list.length * 300,
      varianceMinor: list.fold(0, (a, s) => a + (s.varianceMinor ?? 0)),
    ),
    cur: cur,
    from: DateTime(2026, 11, 9),
    to: DateTime(2026, 11, 10),
    ownShiftsOnly: own,
  );
}

Map<String, dynamic> daybookJson() => {
  'currency': 'USD',
  'currencyExponent': 2,
  'from': '2026-11-08T19:00:00.000Z',
  'to': '2026-11-09T19:00:00.000Z',
  'ownShiftsOnly': true,
  'shifts': [
    {
      'sessionId': 'se1',
      'registerName': 'Main till',
      'employeeName': 'Sam',
      'status': 'closed',
      'openedAt': '2026-11-09T04:00:00.000Z',
      'closedAt': '2026-11-09T13:00:00.000Z',
      'openingMinor': 10000,
      'cashSalesMinor': 2500,
      'cashRefundsMinor': 500,
      'cashInMinor': 0,
      'cashOutMinor': 0,
      'expensesMinor': 0,
      'supplierPaymentsMinor': 0,
      'expectedCashMinor': 12000,
      'countedMinor': 12000,
      'varianceMinor': 0,
      'reconciled': false,
      'unreconciledMinor': -300,
      'lines': [
        {'type': 'opening', 'label': 'Opening float', 'refType': 'session', 'refId': 'se1', 'amountMinor': 10000, 'runningMinor': 10000, 'at': '2026-11-09T04:00:00.000Z', 'employeeName': 'Sam'},
        {'type': 'cash_refund', 'label': 'Refund R-1', 'refType': 'refund', 'refId': 'rf1', 'saleId': 'sale9', 'amountMinor': -500, 'runningMinor': 9500, 'at': '2026-11-09T05:00:00.000Z'},
      ],
    },
  ],
  'totals': {'cashSalesMinor': 2500, 'cashRefundsMinor': 500, 'cashInMinor': 0, 'cashOutMinor': 0, 'expensesMinor': 0, 'supplierPaymentsMinor': 0, 'varianceMinor': 0},
};
