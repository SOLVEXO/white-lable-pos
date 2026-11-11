import 'package:solvexo_pos/app/data/models/pos/pos_inventory_models.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_supply_models.dart';

/// G3.5 cash & daybook: cash in / out by category, expenses with a private receipt photo, and the daybook. Money is integer MINOR units
/// (`...Minor`) next to the response's own currency and exponent ([InvCur]); no response without both shows any money.
int? _int(dynamic v) => v is num ? v.toInt() : null;
String? _str(dynamic v) {
  final s = v is String ? v.trim() : null;
  return s == null || s.isEmpty ? null : s;
}

DateTime? _date(dynamic v) => DateTime.tryParse('${v ?? ''}')?.toLocal();
Map<String, dynamic> _map(dynamic v) => v is Map ? v.cast<String, dynamic>() : <String, dynamic>{};
List<Map<String, dynamic>> _maps(dynamic v) => v is List
    ? [
        for (final e in v)
          if (e is Map) e.cast<String, dynamic>(),
      ]
    : const [];
List<String> _strings(dynamic v) => v is List ? [for (final e in v) '$e'] : const [];

/// A client-made id for one cash movement / expense: the idempotency key of the server (and of the offline queue).
String newCashRequestId() => newSupplyRequestId();

/// Typed amount in the currency's own units -> integer minor units (null when invalid, or zero).
int? cashMinorFromText(String text, int exponent) => supplyMinorFromText(text, exponent);

String cashCategoryLabel(String c) => switch (c) {
  'float_topup' => 'Float top-up',
  'owner_injection' => 'Owner injection',
  'other_in' => 'Other (cash in)',
  'bank_deposit' => 'Bank deposit',
  'safe_drop' => 'Safe drop',
  'petty' => 'Petty cash',
  'owner_draw' => 'Owner draw',
  'other_out' => 'Other (cash out)',
  'rent' => 'Rent',
  'utilities' => 'Utilities',
  'salaries' => 'Salaries',
  'supplies' => 'Supplies',
  'transport' => 'Transport',
  'repairs' => 'Repairs',
  'marketing' => 'Marketing',
  'meals' => 'Meals',
  'taxes_fees' => 'Taxes & fees',
  'other' => 'Other',
  'expense' => 'Expense',
  'supplier_payment' => 'Supplier payment',
  '' => 'Other',
  final t => '${t[0].toUpperCase()}${t.substring(1).replaceAll('_', ' ')}',
};

String expenseMethodLabel(String m) => switch (m) {
  'cash' => 'Cash from the drawer',
  'bank' => 'Bank',
  'other' => 'Other',
  _ => m,
};

/// What the till knows about cash categories and approval limits. The category lists are the server's; offline the last answer is used.
class CashConfig {
  const CashConfig({
    this.cur,
    this.cashInCategories = _defaultIn,
    this.cashOutCategories = _defaultOut,
    this.expenseCategories = _defaultExpense,
    this.expenseMethods = const ['cash', 'bank', 'other'],
    this.noteRequiredFor = const ['other_in', 'other_out'],
    this.cashOutApprovalAboveMinor,
    this.expenseApprovalAboveMinor,
  });
  static const _defaultIn = ['float_topup', 'owner_injection', 'other_in'];
  static const _defaultOut = ['bank_deposit', 'safe_drop', 'petty', 'owner_draw', 'other_out'];
  static const _defaultExpense = ['rent', 'utilities', 'salaries', 'supplies', 'transport', 'repairs', 'marketing', 'meals', 'taxes_fees', 'other'];

  final InvCur? cur;
  final List<String> cashInCategories, cashOutCategories, expenseCategories, expenseMethods, noteRequiredFor;
  final int? cashOutApprovalAboveMinor, expenseApprovalAboveMinor;

  bool noteRequired(String category) => noteRequiredFor.contains(category) || category == 'other';

  factory CashConfig.fromJson(Map<String, dynamic> j) => CashConfig(
    cur: InvCur.fromJson(j),
    cashInCategories: _strings(j['cashInCategories']).isEmpty ? _defaultIn : _strings(j['cashInCategories']),
    cashOutCategories: _strings(j['cashOutCategories']).isEmpty ? _defaultOut : _strings(j['cashOutCategories']),
    expenseCategories: _strings(j['expenseCategories']).isEmpty ? _defaultExpense : _strings(j['expenseCategories']),
    expenseMethods: _strings(j['expenseMethods']).isEmpty ? const ['cash', 'bank', 'other'] : _strings(j['expenseMethods']),
    noteRequiredFor: _strings(j['noteRequiredFor']).isEmpty ? const ['other_in', 'other_out'] : _strings(j['noteRequiredFor']),
    cashOutApprovalAboveMinor: _int(j['cashOutApprovalAboveMinor']),
    expenseApprovalAboveMinor: _int(j['expenseApprovalAboveMinor']),
  );

  Map<String, dynamic> toJson() => {
    'currency': cur?.code,
    'currencyExponent': cur?.exponent,
    'cashInCategories': cashInCategories,
    'cashOutCategories': cashOutCategories,
    'expenseCategories': expenseCategories,
    'expenseMethods': expenseMethods,
    'noteRequiredFor': noteRequiredFor,
    'cashOutApprovalAboveMinor': cashOutApprovalAboveMinor,
    'expenseApprovalAboveMinor': expenseApprovalAboveMinor,
  };
}

class CashMovementResult {
  const CashMovementResult({required this.type, required this.category, required this.amountMinor, this.duplicate = false, this.cur});
  final String type, category;
  final int amountMinor;
  final bool duplicate;
  final InvCur? cur;
  factory CashMovementResult.fromJson(Map<String, dynamic> j) {
    final m = _map(j['movement']);
    return CashMovementResult(type: m['type'] as String? ?? '', category: m['category'] as String? ?? '', amountMinor: _int(m['amountMinor']) ?? 0, duplicate: j['duplicate'] == true, cur: InvCur.fromJson(j));
  }
}

abstract final class ExpenseStatus {
  static const recorded = 'recorded', approved = 'approved', rejected = 'rejected';
  static const filters = <(String, String)>[('all', 'All'), (recorded, 'Recorded'), (approved, 'Approved'), (rejected, 'Rejected')];
  static String label(String s) => switch (s) {
    recorded => 'Recorded',
    approved => 'Approved',
    rejected => 'Rejected',
    _ => s.isEmpty ? 'Recorded' : '${s[0].toUpperCase()}${s.substring(1)}',
  };
}

class Expense {
  const Expense({
    required this.id,
    required this.number,
    required this.category,
    required this.amountMinor,
    required this.method,
    this.cur,
    this.payee,
    this.note,
    this.occurredAt,
    this.sessionId,
    this.employeeId,
    this.employeeName,
    this.status = ExpenseStatus.recorded,
    this.decisionNote,
    this.hasReceipt = false,
    this.receiptMimeType,
  });
  final String id, number, category, method, status;
  final int amountMinor;
  final InvCur? cur;
  final String? payee, note, sessionId, employeeId, employeeName, decisionNote, receiptMimeType;
  final DateTime? occurredAt;
  final bool hasReceipt;

  /// the receipt is a PDF (known from the expense itself, so the app can say so without asking for a link)
  bool get receiptIsPdf => hasReceipt && (receiptMimeType ?? '').toLowerCase().contains('pdf');

  bool get decided => status != ExpenseStatus.recorded;

  factory Expense.fromJson(Map<String, dynamic> j, {InvCur? fallbackCur}) => Expense(
    id: '${j['id'] ?? j['_id'] ?? ''}',
    number: '${j['number'] ?? ''}',
    category: j['category'] as String? ?? 'other',
    amountMinor: _int(j['amountMinor']) ?? 0,
    method: j['method'] as String? ?? 'cash',
    cur: InvCur.fromJson(j) ?? fallbackCur,
    payee: _str(j['payee']),
    note: _str(j['note']),
    occurredAt: _date(j['occurredAt']),
    sessionId: _str(j['sessionId']),
    employeeId: _str(j['employeeId']),
    employeeName: _str(j['employeeName']),
    status: j['status'] as String? ?? ExpenseStatus.recorded,
    decisionNote: _str(j['decisionNote']),
    hasReceipt: j['hasReceipt'] == true,
    receiptMimeType: _str(j['receiptMimeType']),
  );
}

class ExpenseList {
  const ExpenseList({required this.expenses, this.totalsByCategoryMinor = const {}, this.cur});
  final List<Expense> expenses;
  final Map<String, int> totalsByCategoryMinor;
  final InvCur? cur;
  int get totalMinor => totalsByCategoryMinor.values.fold(0, (a, b) => a + b);

  factory ExpenseList.fromJson(Map<String, dynamic> j) {
    final cur = InvCur.fromJson(j);
    return ExpenseList(
      expenses: [for (final e in _maps(j['expenses'])) Expense.fromJson(e, fallbackCur: cur)],
      totalsByCategoryMinor: {for (final e in _map(j['totalsByCategoryMinor']).entries) e.key: _int(e.value) ?? 0},
      cur: cur,
    );
  }
}

class ExpenseSaved {
  const ExpenseSaved({required this.expense, this.duplicate = false});
  final Expense expense;
  final bool duplicate;
  factory ExpenseSaved.fromJson(Map<String, dynamic> j) {
    final cur = InvCur.fromJson(j);
    return ExpenseSaved(expense: Expense.fromJson(_map(j['expense']), fallbackCur: cur), duplicate: j['duplicate'] == true);
  }
}

/// A fresh, short-lived link to the private receipt (5 minutes). Never stored, never logged.
class ReceiptLink {
  const ReceiptLink({required this.url, this.mimeType, this.expiresInSeconds = 300});
  final String url;
  final String? mimeType;
  final int expiresInSeconds;
  bool get isPdf => (mimeType ?? '').toLowerCase().contains('pdf');
  factory ReceiptLink.fromJson(Map<String, dynamic> j) => ReceiptLink(url: '${j['url'] ?? ''}', mimeType: _str(j['mimeType']), expiresInSeconds: _int(j['expiresInSeconds']) ?? 300);
  @override
  String toString() => 'ReceiptLink(${isPdf ? 'pdf' : 'image'})'; // the URL is a credential: never printed
}

class DaybookLine {
  const DaybookLine({required this.type, required this.label, required this.amountMinor, required this.runningMinor, this.at, this.refType, this.refId, this.employeeName, this.saleId});
  final String type, label;
  final int amountMinor, runningMinor;
  final DateTime? at;
  final String? refType, refId, employeeName, saleId;

  /// The sale the existing sale detail should open: a sale or a void line's own id, or a refund line's `saleId` (a refund's own id is not a sale id).
  String? get saleTarget {
    final id = (refType == 'sale' || refType == 'void') ? refId : (refType == 'refund' ? saleId : null);
    return (id ?? '').isEmpty ? null : id;
  }

  bool get opensSale => saleTarget != null;

  factory DaybookLine.fromJson(Map<String, dynamic> j) => DaybookLine(
    type: j['type'] as String? ?? '',
    label: j['label'] as String? ?? '',
    amountMinor: _int(j['amountMinor']) ?? 0,
    runningMinor: _int(j['runningMinor']) ?? 0,
    at: _date(j['at']),
    refType: _str(j['refType']),
    refId: _str(j['refId']),
    employeeName: _str(j['employeeName']),
    saleId: _str(j['saleId']),
  );
}

class DaybookShift {
  const DaybookShift({
    required this.sessionId,
    required this.status,
    this.registerName,
    this.employeeName,
    this.openedAt,
    this.closedAt,
    this.openingMinor = 0,
    this.cashSalesMinor = 0,
    this.cashRefundsMinor = 0,
    this.cashInMinor = 0,
    this.cashOutMinor = 0,
    this.expensesMinor = 0,
    this.supplierPaymentsMinor = 0,
    this.expectedCashMinor = 0,
    this.countedMinor,
    this.varianceMinor,
    this.reconciled = true,
    this.unreconciledMinor = 0,
    this.lines = const [],
  });
  final String sessionId, status;
  final String? registerName, employeeName;
  final DateTime? openedAt, closedAt;
  final int openingMinor, cashSalesMinor, cashRefundsMinor, cashInMinor, cashOutMinor, expensesMinor, supplierPaymentsMinor, expectedCashMinor, unreconciledMinor;
  final int? countedMinor, varianceMinor;
  final bool reconciled;
  final List<DaybookLine> lines;
  bool get closed => status == 'closed';

  factory DaybookShift.fromJson(Map<String, dynamic> j) => DaybookShift(
    sessionId: '${j['sessionId'] ?? ''}',
    status: j['status'] as String? ?? '',
    registerName: _str(j['registerName']),
    employeeName: _str(j['employeeName']),
    openedAt: _date(j['openedAt']),
    closedAt: _date(j['closedAt']),
    openingMinor: _int(j['openingMinor']) ?? 0,
    cashSalesMinor: _int(j['cashSalesMinor']) ?? 0,
    cashRefundsMinor: _int(j['cashRefundsMinor']) ?? 0,
    cashInMinor: _int(j['cashInMinor']) ?? 0,
    cashOutMinor: _int(j['cashOutMinor']) ?? 0,
    expensesMinor: _int(j['expensesMinor']) ?? 0,
    supplierPaymentsMinor: _int(j['supplierPaymentsMinor']) ?? 0,
    expectedCashMinor: _int(j['expectedCashMinor']) ?? 0,
    countedMinor: _int(j['countedMinor']),
    varianceMinor: _int(j['varianceMinor']),
    reconciled: j['reconciled'] != false,
    unreconciledMinor: _int(j['unreconciledMinor']) ?? 0,
    lines: [for (final l in _maps(j['lines'])) DaybookLine.fromJson(l)],
  );
}

class DaybookTotals {
  const DaybookTotals({this.cashSalesMinor = 0, this.cashRefundsMinor = 0, this.cashInMinor = 0, this.cashOutMinor = 0, this.expensesMinor = 0, this.supplierPaymentsMinor = 0, this.varianceMinor = 0});
  final int cashSalesMinor, cashRefundsMinor, cashInMinor, cashOutMinor, expensesMinor, supplierPaymentsMinor, varianceMinor;
  factory DaybookTotals.fromJson(Map<String, dynamic> j) => DaybookTotals(
    cashSalesMinor: _int(j['cashSalesMinor']) ?? 0,
    cashRefundsMinor: _int(j['cashRefundsMinor']) ?? 0,
    cashInMinor: _int(j['cashInMinor']) ?? 0,
    cashOutMinor: _int(j['cashOutMinor']) ?? 0,
    expensesMinor: _int(j['expensesMinor']) ?? 0,
    supplierPaymentsMinor: _int(j['supplierPaymentsMinor']) ?? 0,
    varianceMinor: _int(j['varianceMinor']) ?? 0,
  );
}

class Daybook {
  const Daybook({required this.shifts, required this.totals, this.cur, this.from, this.to, this.ownShiftsOnly = false});
  final List<DaybookShift> shifts;
  final DaybookTotals totals;
  final InvCur? cur;
  final DateTime? from, to;
  final bool ownShiftsOnly;
  bool get reconciled => shifts.every((s) => s.reconciled);
  int get unreconciledMinor => shifts.fold(0, (a, s) => a + s.unreconciledMinor);

  factory Daybook.fromJson(Map<String, dynamic> j) => Daybook(
    shifts: [for (final s in _maps(j['shifts'])) DaybookShift.fromJson(s)],
    totals: DaybookTotals.fromJson(_map(j['totals'])),
    cur: InvCur.fromJson(j),
    from: _date(j['from']),
    to: _date(j['to']),
    ownShiftsOnly: j['ownShiftsOnly'] == true,
  );
}

/// Server error codes of the cash endpoints in plain English (the server enforces; this only explains).
String cashErrorMessage(String? code, {String? fallback}) => switch (code) {
  'NO_OPEN_SHIFT' => 'There is no open shift on this till. Open a shift first.',
  'NOTE_REQUIRED' => 'Add a short note when the reason is "Other".',
  'INVALID_AMOUNT' => 'Enter a valid amount above zero.',
  'INVALID_CATEGORY' => 'Choose a reason from the list.',
  'INVALID_TYPE' => 'Choose cash in or cash out.',
  'INVALID_METHOD' => 'Choose how it was paid: cash, bank or other.',
  'INVALID_DATE' => 'That date is not valid (it cannot be in the future).',
  'INVALID_DECISION' => 'Choose approve or reject.',
  'REQUEST_ID_REQUIRED' => 'Something went wrong with this request. Try again.',
  'ALREADY_DECIDED' => 'This expense was already approved or rejected.',
  'EXPENSE_NOT_FOUND' => 'That expense was not found.',
  'NO_RECEIPT' => 'This expense has no receipt photo.',
  'FILE_REQUIRED' => 'Choose a photo first.',
  'FILE_TOO_LARGE' => 'That file is too large. Take a smaller photo.',
  'FILE_TYPE' => 'Only JPEG, PNG or PDF files are accepted.',
  'RANGE_REQUIRED' => 'Choose a day.',
  'RANGE_TOO_LONG' => 'A daybook covers at most 31 days.',
  'POS_APPROVAL_REQUIRED' => 'A manager must approve this.',
  'POS_OWNER_REQUIRED' => 'This amount is above the manager limit. The store owner must do this.',
  'POS_ACTION_FORBIDDEN' => 'Your role is not allowed to do this.',
  'POS_PIN_REQUIRED' => 'Sign in with your PIN first.',
  _ => fallback ?? 'Something went wrong. Please try again.',
};

/// G4.6: the register's last closed shift, shown when the next one opens. Money in minor units with the response's currency + exponent.
class LastClose {
  const LastClose({required this.currency, required this.exponent, this.closedAt, this.closedByName, this.countedMinor, this.expectedMinor, this.varianceMinor, this.forced = false, this.denominations = const []});
  final String currency;
  final int exponent;
  final DateTime? closedAt;
  final String? closedByName;
  final int? countedMinor, expectedMinor, varianceMinor;
  final bool forced;
  final List<({int valueMinor, int count})> denominations;

  /// null when the register was never closed
  static LastClose? fromJson(Map<String, dynamic> j) {
    final l = j['lastClose'];
    if (l is! Map) return null;
    int? n(dynamic v) => v is num ? v.toInt() : null;
    return LastClose(
      currency: '${j['currency'] ?? 'USD'}'.toUpperCase(),
      exponent: j['currencyExponent'] is num ? (j['currencyExponent'] as num).toInt() : 2,
      closedAt: DateTime.tryParse('${l['closedAt'] ?? ''}')?.toLocal(),
      closedByName: l['closedByName'] as String?,
      countedMinor: n(l['countedMinor']),
      expectedMinor: n(l['expectedMinor']),
      varianceMinor: n(l['varianceMinor']),
      forced: l['forced'] == true,
      denominations: [
        for (final d in (l['denominations'] as List? ?? const []))
          if (d is Map) (valueMinor: n(d['valueMinor']) ?? 0, count: n(d['count']) ?? 0),
      ],
    );
  }
}

