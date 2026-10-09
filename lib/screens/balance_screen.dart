import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../services/app_repository.dart';
import '../widgets/expense_pacing_bar.dart';
import '../widgets/month_summary_card.dart';
import '../widgets/section_card.dart';
import '../widgets/source_carousel.dart';
import '../widgets/year_heat_grid.dart';

class BalanceScreen extends StatefulWidget {
  const BalanceScreen({super.key, required this.repo, required this.api});

  final AppRepository repo;
  final ApiClient api;

  @override
  State<BalanceScreen> createState() => _BalanceScreenState();
}

class _BalanceScreenState extends State<BalanceScreen> {
  late final AppRepository _repo = widget.repo;
  late final ApiClient _api = widget.api;

  BalanceSummary? _balance;
  YearSummary? _year;
  String _userId = '';
  String _currency = '';
  int _selectedSourceIndex = 0; // 0 = all, 1..n = source index
  int _selectedMonth = DateTime.now().month;
  final int _selectedYear = DateTime.now().year;
  bool _loading = true;
  String? _error;

  static const _monthNames = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (_userId.isEmpty) _userId = await _repo.getUserId();
      final year = DateTime.now().year;
      final results = await Future.wait([
        _api.getBalance(_userId),
        _api.getYear(_userId, year: year),
      ]);
      if (!mounted) return;
      setState(() {
        _balance = results[0] as BalanceSummary;
        _year = results[1] as YearSummary;
        _currency = (_balance?.currency.isNotEmpty == true)
            ? _balance!.currency
            : _year?.currency ?? '';
        _selectedMonth = DateTime.now().month;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error =
            "Can't reach the server — check you're on the same network as 192.168.68.53";
        _loading = false;
      });
    }
  }

  // ---------------- Derived data ----------------
  MonthEntry? get _selectedMonthEntry => _year?.entryFor(_selectedMonth);

  double get _monthIncome => _selectedMonthEntry?.incomeNum ?? 0;
  double get _monthExpense => _selectedMonthEntry?.expenseNum ?? 0;
  double get _monthSaved => _monthIncome - _monthExpense;

  List<BalanceSource> get _allSources => _balance?.sources ?? const [];

  // ---------------- Actions ----------------
  void _onSourceSelect(int index) {
    setState(() => _selectedSourceIndex = index);
  }

  void _onMonthTap(int month) {
    setState(() => _selectedMonth = month);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Balance')),
      body: RefreshIndicator(onRefresh: _loadAll, child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return ListView(
        children: [
          const SizedBox(height: 120),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              _error!,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: FilledButton(
              onPressed: _loadAll,
              child: const Text('Retry'),
            ),
          ),
        ],
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        // 1. Swipeable source carousel — centred card = the filter.
        SourceCarousel(
          sources: _allSources,
          totalBalance: _balance?.totalBalanceNum ?? 0,
          currency: _currency,
          selectedIndex: _selectedSourceIndex,
          onSelect: _onSourceSelect,
          repo: _repo,
        ),
        const SizedBox(height: 16),

        // 2. This-month summary (Income / Expense / Saved).
        SectionCard(
          child: MonthSummaryCard(
            currency: _currency,
            income: _monthIncome,
            expense: _monthExpense,
            saved: _monthSaved,
            monthLabel:
                '${_monthNames[_selectedMonth - 1]} $_selectedYear',
          ),
        ),
        const SizedBox(height: 16),

        // 3. Expense-to-income pacing bar.
        SectionCard(
          icon: Icons.assessment_outlined,
          title: 'Expense to income',
          subtitle:
              'Saved so far ${_monthSaved.toStringAsFixed(2)} $_currency',
          child: ExpensePacingBar(
            income: _monthIncome,
            expense: _monthExpense,
            year: _selectedYear,
            month: _selectedMonth,
          ),
        ),
        const SizedBox(height: 16),

        // 4. Calendar year view.
        YearHeatGrid(
          year: _selectedYear,
          months: _year?.months ?? const [],
          selectedMonth: _selectedMonth,
          onSelect: _onMonthTap,
        ),
      ],
    );
  }
}
