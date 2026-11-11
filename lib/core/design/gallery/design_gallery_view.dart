import 'package:flutter/material.dart';
import 'package:solvexo_pos/config/debug_launch_params.dart';
import 'package:solvexo_pos/core/design/design.dart';
import 'package:solvexo_pos/utils/money.dart';

// Debug-only launch parameters (simulator screenshots): GALLERY_MODE =
// light|dark|both and GALLERY_SCROLL = px, via --dart-define or the
// DebugLaunchParams file (see lib/config/debug_launch_params.dart).
const String _kModeDefine = String.fromEnvironment('GALLERY_MODE');
const int _kScrollDefine = int.fromEnvironment('GALLERY_SCROLL');
String get _kModeParam => _kModeDefine.isNotEmpty
    ? _kModeDefine
    : (DebugLaunchParams.get('GALLERY_MODE') ?? '');
int get _kScrollParam => _kScrollDefine != 0
    ? _kScrollDefine
    : int.tryParse(DebugLaunchParams.get('GALLERY_SCROLL') ?? '') ?? 0;

/// Debug-only catalogue of every design-system component, in light and dark
/// (route `/design-gallery`, registered only when `kDebugMode`).
class DesignGalleryView extends StatefulWidget {
  const DesignGalleryView({super.key, this.startDark = false});

  /// Opens on the dark theme instead of the default light/both.
  final bool startDark;

  @override
  State<DesignGalleryView> createState() => _DesignGalleryViewState();
}

enum _Mode { light, dark, both }

class _DesignGalleryViewState extends State<DesignGalleryView> {
  late _Mode _mode = switch (_kModeParam) {
    'light' => _Mode.light,
    'dark' => _Mode.dark,
    'both' => _Mode.both,
    _ => widget.startDark ? _Mode.dark : _Mode.both,
  };

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final mode = (_mode == _Mode.both && !wide) ? _Mode.light : _mode;
    final chrome = mode == _Mode.dark ? AppTheme.dark : AppTheme.light;
    return Theme(
      data: chrome,
      child: Builder(
        builder: (context) {
          final p = context.palette;
          return Scaffold(
            backgroundColor: p.background,
            appBar: AppBar(
              title: const Text('Design gallery · Ink & Ember'),
              actions: [
                Padding(
                  padding: const EdgeInsets.only(right: Space.s3),
                  child: SegmentedButton<_Mode>(
                    showSelectedIcon: false,
                    segments: [
                      const ButtonSegment(
                        value: _Mode.light,
                        label: Text('Light'),
                      ),
                      const ButtonSegment(
                        value: _Mode.dark,
                        label: Text('Dark'),
                      ),
                      ButtonSegment(
                        value: _Mode.both,
                        label: const Text('Both'),
                        enabled: wide,
                      ),
                    ],
                    selected: {mode},
                    onSelectionChanged: (s) => setState(() => _mode = s.first),
                  ),
                ),
              ],
            ),
            body: mode == _Mode.both
                ? Row(
                    children: [
                      Expanded(
                        child: Theme(
                          data: AppTheme.light,
                          child: const _Pane(),
                        ),
                      ),
                      Expanded(
                        child: Theme(data: AppTheme.dark, child: const _Pane()),
                      ),
                    ],
                  )
                : const _Pane(),
          );
        },
      ),
    );
  }
}

void _noop() {}

class _Pane extends StatefulWidget {
  const _Pane();
  @override
  State<_Pane> createState() => _PaneState();
}

class _PaneState extends State<_Pane> {
  final _cartKey = GlobalKey();
  final _scrollCtl = ScrollController(
    initialScrollOffset: _kScrollParam.toDouble(),
  );
  final _pinCtl = ValueNotifier<String>('');
  final _search = TextEditingController();
  final _email = TextEditingController();
  final _pw = TextEditingController();
  int _chip = 0;
  int _qty = 2;
  double _amount = 1284.5;
  int _errorTick = 0;
  bool _pinError = false;
  bool _fieldError = false;
  int _cartCount = 0;

  @override
  void dispose() {
    _scrollCtl.dispose();
    _pinCtl.dispose();
    _search.dispose();
    _email.dispose();
    _pw.dispose();
    super.dispose();
  }

  void _digit(String d) {
    if (_pinCtl.value.length >= 4) return;
    setState(() {
      _pinError = false;
      _pinCtl.value += d;
    });
    if (_pinCtl.value.length == 4 && _pinCtl.value != '1234') {
      setState(() {
        _pinError = true;
        _errorTick++;
      });
      Future.delayed(const Duration(milliseconds: 600), () {
        if (mounted) setState(() => _pinCtl.value = '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return ColoredBox(
      color: p.background,
      child: ListView(
        controller: _scrollCtl,
        padding: const EdgeInsets.all(Space.s4),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    p.isDark ? 'DARK' : 'LIGHT',
                    style: context.type.label.copyWith(
                      color: p.textMuted,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: Space.s4),
                  _colors(context),
                  _primaryOptions(context),
                  _accentVsDanger(context),
                  _type(context),
                  _buttons(context),
                  _fields(context),
                  _cards(context),
                  _products(context),
                  _controls(context),
                  _amounts(context),
                  _pin(context),
                  _overlays(context),
                  _states(context),
                  _badges(context),
                  _receipt(context),
                  _shell(context),
                  const SizedBox(height: Space.s8),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(
    BuildContext context,
    String title,
    Widget child, {
    Widget? trailing,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: Space.s8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: SectionHeader(title)),
            if (trailing != null) trailing,
          ],
        ),
        child,
      ],
    ),
  );

  Widget _colors(BuildContext context) {
    final p = context.palette;
    final items = <(String, Color)>[
      ('background', p.background),
      ('surface', p.surface),
      ('raised', p.surfaceRaised),
      ('fill', p.fill),
      ('border', p.border),
      ('text', p.textPrimary),
      ('text 2', p.textSecondary),
      ('muted', p.textMuted),
      ('accent', p.accent),
      ('accent strong', p.accentStrong),
      ('accent soft', p.accentSoft),
      ('accent fg', p.accentFg),
      ('success', p.success),
      ('warning', p.warning),
      ('danger', p.danger),
      ('info', p.info),
    ];
    return _section(
      context,
      'Colors',
      Wrap(
        spacing: Space.s2,
        runSpacing: Space.s2,
        children: [
          for (final (n, c) in items)
            Column(
              children: [
                Container(
                  width: 76,
                  height: 48,
                  decoration: BoxDecoration(
                    color: c,
                    borderRadius: Radii.rSm,
                    border: Border.all(color: p.border),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  n,
                  style: context.type.caption.copyWith(color: p.textSecondary),
                ),
              ],
            ),
        ],
      ),
    );
  }

  /// Side-by-side decision aid for the filled primary button.
  Widget _primaryOptions(BuildContext context) {
    final p = context.palette;
    Widget option(
      String title,
      String note,
      AppButtonVariant v,
      Color fill,
      Color on,
    ) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: context.type.label.copyWith(color: p.textPrimary)),
          Text(note, style: context.type.caption.copyWith(color: p.textMuted)),
          Space.gap2,
          AppButton(
            label: 'Charge',
            icon: Icons.payments_rounded,
            variant: v,
            size: AppButtonSize.lg,
            onPressed: () {},
          ),
          Space.gap2,
          AppButton(label: 'Open register', variant: v, onPressed: () {}),
          Space.gap2,
          AppButton(
            label: 'Saving',
            variant: v,
            loading: true,
            onPressed: () {},
          ),
        ],
      ),
    );
    return _section(
      context,
      'Primary button: which fill?',
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          option(
            '(a) #DC7758 + dark ink',
            'brand coral, 5.8:1',
            AppButtonVariant.primaryBright,
            p.accent,
            p.onAccent,
          ),
          Space.gap3,
          option(
            '(b) accentFill + white (default)',
            '#B4553A, 4.9:1',
            AppButtonVariant.primary,
            p.accentFill,
            p.onAccentFill,
          ),
        ],
      ),
    );
  }

  Widget _accentVsDanger(BuildContext context) {
    final p = context.palette;
    Widget col(
      String t,
      Color fill,
      Color on,
      StatusTone tone,
      AppButtonVariant v,
    ) => Expanded(
      child: Column(
        children: [
          Container(
            height: 64,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: fill, borderRadius: Radii.rMd),
            child: Text(t, style: context.type.subtitle.copyWith(color: on)),
          ),
          const SizedBox(height: Space.s2),
          AppButton(label: t, variant: v, onPressed: () {}),
          const SizedBox(height: Space.s2),
          StatusBadge(t, tone: tone, dot: true),
        ],
      ),
    );
    return _section(
      context,
      'Accent vs danger',
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          col(
            'Accent',
            p.accent,
            p.onAccent,
            StatusTone.accent,
            AppButtonVariant.primary,
          ),
          const SizedBox(width: Space.s3),
          col(
            'Danger',
            p.danger,
            p.onDanger,
            StatusTone.danger,
            AppButtonVariant.danger,
          ),
        ],
      ),
    );
  }

  Widget _type(BuildContext context) {
    final p = context.palette;
    final t = context.type;
    Widget row(String n, TextStyle s, [String? text]) => Padding(
      padding: const EdgeInsets.only(bottom: Space.s2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          SizedBox(
            width: 90,
            child: Text(n, style: t.caption.copyWith(color: p.textMuted)),
          ),
          Expanded(
            child: Text(
              text ?? 'Fresh bread & oat milk',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: s.copyWith(color: p.textPrimary),
            ),
          ),
        ],
      ),
    );
    return _section(
      context,
      'Typography',
      AppCard(
        child: Column(
          children: [
            row('display', t.display),
            row('headline', t.headline),
            row('title', t.title),
            row('subtitle', t.subtitle),
            row('body', t.body),
            row('bodySmall', t.bodySmall),
            row('label', t.label),
            row('caption', t.caption),
            row('amountXl', t.amountXl, Money.format(1284.5)),
            row('amountLg', t.amountLg, Money.format(1284.5)),
            row('amountMd', t.amountMd, Money.format(1284.5)),
          ],
        ),
      ),
    );
  }

  Widget _buttons(BuildContext context) => _section(
    context,
    'Buttons',
    Column(
      children: [
        AppButton(
          label: 'Charge',
          icon: Icons.payments_rounded,
          size: AppButtonSize.lg,
          onPressed: () {},
        ),
        Space.gap3,
        Row(
          children: [
            Expanded(
              child: AppButton(
                label: 'Secondary',
                variant: AppButtonVariant.secondary,
                onPressed: () {},
              ),
            ),
            Space.gap3,
            Expanded(
              child: AppButton(
                label: 'Ghost',
                variant: AppButtonVariant.ghost,
                onPressed: () {},
              ),
            ),
          ],
        ),
        Space.gap3,
        Row(
          children: [
            Expanded(
              child: AppButton(
                label: 'Void sale',
                variant: AppButtonVariant.danger,
                icon: Icons.delete_outline_rounded,
                onPressed: () {},
              ),
            ),
            Space.gap3,
            Expanded(
              child: AppButton(
                label: 'Saving',
                loading: true,
                onPressed: () {},
              ),
            ),
          ],
        ),
        Space.gap3,
        const AppButton(label: 'Disabled', onPressed: null),
      ],
    ),
  );

  Widget _fields(BuildContext context) => _section(
    context,
    'Text fields',
    Column(
      children: [
        AppTextField(
          label: 'Email',
          controller: _email,
          prefixIcon: Icons.mail_outline_rounded,
          keyboardType: TextInputType.emailAddress,
          errorText: _fieldError ? 'Enter a valid email' : null,
        ),
        Space.gap3,
        AppTextField(
          label: 'Password',
          controller: _pw,
          prefixIcon: Icons.lock_outline_rounded,
          obscureText: true,
          showObscureToggle: true,
        ),
        Space.gap3,
        const AppTextField(label: 'SKU', mono: true, hint: 'SKU-00231'),
        Space.gap3,
        AppButton(
          label: _fieldError ? 'Clear error' : 'Trigger error + shake',
          variant: AppButtonVariant.secondary,
          onPressed: () => setState(() => _fieldError = !_fieldError),
        ),
      ],
    ),
  );

  Widget _cards(BuildContext context) => _section(
    context,
    'Cards & stat tiles',
    Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: StatTile(
                label: 'Sales today',
                value: _amount,
                formatter: Money.format,
                icon: Icons.trending_up_rounded,
                delta: '+12% vs yesterday',
                deltaPositive: true,
              ),
            ),
            Space.gap3,
            Expanded(
              child: StatTile(
                label: 'Refunds',
                value: 42.0,
                formatter: Money.format,
                icon: Icons.undo_rounded,
                delta: '3 orders',
                deltaPositive: false,
              ),
            ),
          ],
        ),
        Space.gap3,
        AppCard(
          onTap: () {},
          raised: true,
          child: Text(
            'Pressable raised card',
            style: context.type.body.copyWith(
              color: context.palette.textPrimary,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _products(BuildContext context) {
    final items = <(String, String, int?, bool)>[
      ('Sourdough loaf', 4.5.toString(), 40, false),
      ('Oat milk 1L', '3.2', 8, false),
      ('Cold brew bottle', '5.75', 2, false),
      ('Gift wrap', '1.0', null, true),
      ('Almond croissant', '3.9', 0, false),
      ('Sea salt crackers', '2.45', 18, false),
    ];
    return _section(
      context,
      'Product tiles',
      trailing: Container(
        key: _cartKey,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: context.palette.accentSoft,
          shape: BoxShape.circle,
        ),
        child: Badge(
          isLabelVisible: _cartCount > 0,
          label: Text('$_cartCount'),
          child: Icon(
            Icons.shopping_bag_outlined,
            color: context.palette.accentFg,
          ),
        ),
      ),
      LayoutBuilder(
        builder: (context, c) {
          final cols = c.maxWidth >= 520 ? 4 : 3;
          return GridView.count(
            crossAxisCount: cols,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: Space.s3,
            crossAxisSpacing: Space.s3,
            childAspectRatio: 0.74,
            children: [
              for (final (name, price, stock, unlimited) in items)
                ProductTile(
                  name: name,
                  priceText: Money.format(double.parse(price)),
                  stock: stock,
                  unlimited: unlimited,
                  cartKey: _cartKey,
                  inCartQty: name == 'Oat milk 1L' ? _cartCount : 0,
                  onAdd: () => setState(() => _cartCount++),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _controls(BuildContext context) => _section(
    context,
    'Quantity · chips · search',
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            QuantityStepper(
              value: _qty,
              onChanged: (v) => setState(() => _qty = v),
              max: 9,
            ),
            Space.gap4,
            QuantityStepper(
              value: _qty,
              onChanged: (v) => setState(() => _qty = v),
              compact: true,
              max: 9,
            ),
          ],
        ),
        Space.gap4,
        Transform.translate(
          offset: const Offset(-Space.s4, 0),
          child: SizedBox(
            width: MediaQuery.sizeOf(context).width,
            child: CategoryChips(
              labels: const [
                'All',
                'Bakery',
                'Dairy',
                'Drinks',
                'Snacks',
                'Household goods',
                'Gifts',
              ],
              selectedIndex: _chip,
              onSelected: (i) => setState(() => _chip = i),
            ),
          ),
        ),
        Space.gap4,
        AppSearchBar(
          controller: _search,
          hint: 'Search or scan product',
          onScan: () {},
        ),
      ],
    ),
  );

  Widget _amounts(BuildContext context) {
    final p = context.palette;
    return _section(
      context,
      'Amounts (rolling)',
      AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Total',
              style: context.type.label.copyWith(color: p.textSecondary),
            ),
            AmountText(Money.format(_amount), style: context.type.amountXl),
            Space.gap3,
            AppButton(
              label: 'Change amount',
              variant: AppButtonVariant.secondary,
              expand: false,
              onPressed: () =>
                  setState(() => _amount = (_amount * 7 + 1234.57) % 99999),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pin(BuildContext context) => _section(
    context,
    'PIN pad (try 1234; anything else shakes)',
    Center(
      child: Column(
        children: [
          PinDots(
            length: 4,
            filled: _pinCtl.value.length,
            errorTick: _errorTick,
            hasError: _pinError,
          ),
          Space.gap6,
          PinPad(
            onDigit: _digit,
            onBackspace: () => setState(() {
              _pinError = false;
              if (_pinCtl.value.isNotEmpty) {
                _pinCtl.value = _pinCtl.value.substring(
                  0,
                  _pinCtl.value.length - 1,
                );
              }
            }),
            onClear: () => setState(() => _pinCtl.value = ''),
          ),
        ],
      ),
    ),
  );

  Widget _overlays(BuildContext context) => _section(
    context,
    'Sheet · dialog · toast',
    Wrap(
      spacing: Space.s2,
      runSpacing: Space.s2,
      children: [
        AppButton(
          label: 'Bottom sheet',
          expand: false,
          variant: AppButtonVariant.secondary,
          onPressed: () => AppBottomSheet.show(
            context,
            title: 'Discount',
            builder: (_) => Column(
              children: [
                const AppTextField(
                  label: 'Amount',
                  mono: true,
                  keyboardType: TextInputType.number,
                ),
                Space.gap4,
                AppButton(
                  label: 'Apply',
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
        ),
        AppButton(
          label: 'Confirm dialog',
          expand: false,
          variant: AppButtonVariant.secondary,
          onPressed: () => AppDialog.confirm(
            context,
            title: 'Void this sale?',
            message: 'The order will be cancelled and stock restored.',
            confirmLabel: 'Void sale',
            destructive: true,
          ),
        ),
        for (final t in ToastType.values)
          AppButton(
            label: 'Toast · ${t.name}',
            expand: false,
            variant: AppButtonVariant.ghost,
            onPressed: () => AppToast.show(
              'This is a ${t.name} message that is a little long to check wrapping.',
              type: t,
              title: t.name.toUpperCase(),
              context: context,
              actionLabel: t == ToastType.error ? 'Retry' : null,
              onAction: () {},
            ),
          ),
      ],
    ),
  );

  Widget _states(BuildContext context) => _section(
    context,
    'Empty state · skeleton',
    Column(
      children: [
        const SizedBox(
          height: 340,
          child: EmptyState(
            icon: Icons.receipt_long_rounded,
            title: 'No sales yet',
            message: 'Completed sales will show up here.',
            actionLabel: 'Start a sale',
            onAction: _noop,
          ),
        ),
        const SizedBox(
          height: 300,
          child: SkeletonList(itemCount: 4, padding: EdgeInsets.zero),
        ),
      ],
    ),
  );

  Widget _badges(BuildContext context) => _section(
    context,
    'Status badges',
    const Wrap(
      spacing: Space.s2,
      runSpacing: Space.s2,
      children: [
        StatusBadge(
          'Paid',
          tone: StatusTone.success,
          icon: Icons.check_rounded,
        ),
        StatusBadge('Pending sync', tone: StatusTone.warning, dot: true),
        StatusBadge(
          'Refunded',
          tone: StatusTone.danger,
          icon: Icons.undo_rounded,
        ),
        StatusBadge('Held', tone: StatusTone.info, dot: true),
        StatusBadge('Owner', tone: StatusTone.accent),
        StatusBadge('Draft'),
      ],
    ),
  );

  Widget _receipt(BuildContext context) {
    final p = context.palette;
    return _section(
      context,
      'Receipt panel',
      SizedBox(
        height: 400,
        child: ReceiptPanel(
          header: Padding(
            padding: const EdgeInsets.all(Space.s4),
            child: Text(
              'Current sale',
              style: context.type.title.copyWith(color: p.textPrimary),
            ),
          ),
          body: ListView(
            padding: const EdgeInsets.symmetric(horizontal: Space.s4),
            children: [
              for (final l in const [
                ('Sourdough loaf', '2 × 4.50'),
                ('Oat milk 1L', '1 × 3.20'),
                ('Cold brew bottle', '3 × 5.75'),
              ])
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: Space.s2),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          l.$1,
                          style: context.type.body.copyWith(
                            color: p.textPrimary,
                          ),
                        ),
                      ),
                      Text(
                        l.$2,
                        style: context.type.amountMd.copyWith(
                          color: p.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          footer: Padding(
            padding: const EdgeInsets.all(Space.s4),
            child: Column(
              children: [
                const ReceiptDivider(
                  padding: EdgeInsets.only(bottom: Space.s2),
                ),
                ReceiptRow('Subtotal', Money.format(29.45)),
                ReceiptRow(
                  'Discount',
                  '-${Money.format(2.0)}',
                  valueColor: p.successFg,
                ),
                ReceiptRow('Tax (8%)', Money.format(2.2)),
                const ReceiptDivider(),
                ReceiptRow('Total', Money.format(29.65), strong: true),
                Space.gap3,
                AppButton(
                  label: 'Charge',
                  size: AppButtonSize.lg,
                  onPressed: () {},
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _shell(BuildContext context) => _section(
    context,
    'App shell',
    AppButton(
      label: 'Open shell demo',
      variant: AppButtonVariant.secondary,
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) =>
              Theme(data: Theme.of(context), child: const _ShellDemo()),
        ),
      ),
    ),
  );
}

class _ShellDemo extends StatefulWidget {
  const _ShellDemo();
  @override
  State<_ShellDemo> createState() => _ShellDemoState();
}

class _ShellDemoState extends State<_ShellDemo> {
  int _i = 0;
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    const dests = [
      AppDestination(
        icon: Icons.point_of_sale_outlined,
        selectedIcon: Icons.point_of_sale_rounded,
        label: 'Sale',
      ),
      AppDestination(
        icon: Icons.receipt_long_outlined,
        selectedIcon: Icons.receipt_long_rounded,
        label: 'Orders',
        badge: 3,
      ),
      AppDestination(
        icon: Icons.inventory_2_outlined,
        selectedIcon: Icons.inventory_2_rounded,
        label: 'Products',
      ),
      AppDestination(
        icon: Icons.settings_outlined,
        selectedIcon: Icons.settings_rounded,
        label: 'Settings',
      ),
    ];
    return AppShell(
      destinations: dests,
      currentIndex: _i,
      onDestinationSelected: (i) => setState(() => _i = i),
      railHeader: (ext) => Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: p.accent, borderRadius: Radii.rMd),
            child: Icon(Icons.bolt_rounded, color: p.onAccent),
          ),
          if (ext) ...[
            const SizedBox(width: Space.s3),
            Text(
              'Solvexo',
              style: context.type.title.copyWith(color: p.textPrimary),
            ),
          ],
        ],
      ),
      topBanner: Container(
        width: double.infinity,
        color: p.warningSoft,
        padding: const EdgeInsets.all(Space.s2),
        child: Text(
          'Offline — sales will sync later',
          textAlign: TextAlign.center,
          style: context.type.caption.copyWith(
            color: p.warningFg,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                dests[_i].label,
                style: context.type.display.copyWith(color: p.textPrimary),
              ),
              Space.gap4,
              AppButton(
                label: 'Back to gallery',
                expand: false,
                variant: AppButtonVariant.secondary,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
