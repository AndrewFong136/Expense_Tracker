import 'dart:convert';

import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../services/app_repository.dart';
import '../widgets/app_icon_circle.dart';
import '../widgets/section_card.dart';
import '../widgets/weekly_overview_chart.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.repo, required this.api, required this.dashboardRev});

  final AppRepository repo;
  final ApiClient api;
  final ValueNotifier<int> dashboardRev;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final AppRepository _repo = widget.repo;
  late final ApiClient _api = widget.api;

  Dashboard? _dash;
  bool _loading = true;
  String? _error;
  String _userId = '';
  bool _retried = false;

  // Weekly summary + daily transactions state.
  WeekSummary? _weekSummary;
  DateTime _selectedWeekStart = DateTime.now();
  DateTime _selectedDay = DateTime.now();
  List<Transaction> _transactions = const [];
  bool _txLoading = false;

  @override
  void initState() {
    super.initState();
    _loadFromCache();
    _load();
    widget.dashboardRev.addListener(_onRevChanged);
  }

  @override
  void dispose() {
    widget.dashboardRev.removeListener(_onRevChanged);
    super.dispose();
  }

  /// Instant load from cache (stale-while-revalidate). Renders the home screen
  /// immediately from the last successful /dashboard response, before the
  /// network refresh completes.
  Future<void> _loadFromCache() async {
    final cached = await _api.getCachedDashboardJson();
    if (cached == null || _dash != null) return;
    try {
      final d = Dashboard.fromJson(jsonDecode(cached) as Map<String, dynamic>);
      if (!mounted) return;
      final today = DateTime.now();
      setState(() {
        _dash = d;
        _weekSummary = d.week;
        _selectedWeekStart = _mondayOf(today);
        _selectedDay = _dateOnly(today);
        _loading = false;
      });
      _fetchTransactions();
    } catch (_) {}
  }

  void _onRevChanged() => _load(silent: true);

  Future<void> _load({bool silent = false}) async {
    final effectiveSilent = silent || _dash != null;
    if (!effectiveSilent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      if (_userId.isEmpty) _userId = await _repo.getUserId();
      final d = await _api.getDashboard(_userId, day: _yyyymmdd(_selectedDay));
      if (!mounted) return;
      if (d == null) {
        if (!_retried) {
          _retried = true;
          await Future.delayed(const Duration(seconds: 2));
          if (!mounted) return;
          await _load(silent: effectiveSilent);
          return;
        }
        if (effectiveSilent) return;
        setState(() {
          _error = 'Setting up your budget — tap retry in a moment.';
          _loading = false;
        });
        return;
      }
      _retried = false;
      final today = DateTime.now();
      final currentMonday = _mondayOf(today);
      final isFirstLoad = _weekSummary == null;
      setState(() {
        _dash = d;
        if (isFirstLoad) {
          _weekSummary = d.week;
          _selectedWeekStart = currentMonday;
          _selectedDay = _dateOnly(today);
        } else if (_selectedWeekStart == currentMonday) {
          _weekSummary = d.week;
        }
        _loading = false;
      });
      if (isFirstLoad) _fetchTransactions();
    } catch (e) {
      if (!mounted) return;
      if (effectiveSilent) return;
      setState(() {
        _error =
            "Can't reach the server";
        _loading = false;
      });
    }
  }

  Future<void> _manualRetry() async {
    _retried = false;
    await _load();
  }

  // ---------------- Week navigation ----------------
  Future<void> _loadWeek(DateTime monday) async {
    final currentMonday = _mondayOf(DateTime.now());
    final clamped = monday.isAfter(currentMonday) ? currentMonday : monday;
    final isCurrent = clamped == currentMonday;
    setState(() {
      _selectedWeekStart = clamped;
      _weekSummary = (isCurrent && _dash != null) ? _dash!.week : null;
    });
    if (isCurrent) return;
    try {
      if (_userId.isEmpty) _userId = await _repo.getUserId();
      final w = await _api.getWeek(_userId, week: _yyyymmdd(clamped));
      if (!mounted) return;
      setState(() => _weekSummary = w);
    } catch (_) {
      // leave null (chart shows spinner)
    }
  }

  void _shiftWeek(int days) => _loadWeek(_selectedWeekStart.add(Duration(days: days)));

  Future<void> _pickWeek() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedWeekStart,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) _loadWeek(_mondayOf(_dateOnly(picked)));
  }

  // ---------------- Daily transactions ----------------
  void _onBarTap(int idx) {
    final ws = _weekSummary;
    if (ws == null || idx < 0 || idx >= ws.daily.length) return;
    final day = _parseDate(ws.daily[idx].date);
    if (day == null) return;
    setState(() => _selectedDay = day);
    _load(silent: true);
    _fetchTransactions();
  }

  Future<void> _pickDay() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDay,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() => _selectedDay = _dateOnly(picked));
      _load(silent: true);
      _fetchTransactions();
    }
  }

  Future<void> _fetchTransactions() async {
    setState(() => _txLoading = true);
    try {
      if (_userId.isEmpty) _userId = await _repo.getUserId();
      final from = _yyyymmdd(_selectedDay);
      final to = _yyyymmdd(_selectedDay.add(const Duration(days: 1)));
      final txs = await _api.getTransactions(_userId, from: from, to: to);
      if (!mounted) return;
      setState(() {
        _transactions = txs;
        _txLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _transactions = const [];
        _txLoading = false;
      });
    }
  }

  // ---------------- Date helpers ----------------
  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
  static DateTime _mondayOf(DateTime d) =>
      _dateOnly(d).subtract(Duration(days: d.weekday - 1));
  static String _yyyymmdd(DateTime d) {
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '${d.year}-$m-$day';
  }
  static DateTime? _parseDate(String s) {
    if (s.length < 10) return null;
    final y = int.tryParse(s.substring(0, 4));
    final m = int.tryParse(s.substring(5, 7));
    final d = int.tryParse(s.substring(8, 10));
    if (y == null || m == null || d == null) return null;
    return DateTime(y, m, d);
  }
  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  static String _formatDay(DateTime d) => '${_months[d.month - 1]} ${d.day}';
  static String _formatDateTime(DateTime? dt) {
    if (dt == null) return '';
    final h = dt.hour;
    final ampm = h >= 12 ? 'PM' : 'AM';
    final hr = h % 12 == 0 ? 12 : h % 12;
    final min = dt.minute.toString().padLeft(2, '0');
    return '${_months[dt.month - 1]} ${dt.day}, $hr:$min $ampm';
  }

  String _money(double v, String currency) => '${v.toStringAsFixed(2)} $currency';

  Widget _amount(String numberValue, String currency, TextStyle amountStyle) {
    final color = amountStyle.color ?? const Color(0xFF000000);
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(numberValue, style: amountStyle),
          const SizedBox(width: 4),
          Text(
            currency,
            style: amountStyle.copyWith(
              fontSize: (amountStyle.fontSize ?? 22) * 0.6,
              color: color.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Rabbix')),
      body: RefreshIndicator(onRefresh: _manualRetry, child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final d = _dash;
    if (d == null) {
      return ListView(
        children: [
          const SizedBox(height: 120),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              _error ?? 'No data',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: FilledButton(
              onPressed: _manualRetry,
              child: const Text('Retry'),
            ),
          ),
        ],
      );
    }
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        _todaySpendCard(theme, d),
        const SizedBox(height: 16),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _remainingCard(theme, d)),
              const SizedBox(width: 12),
              Expanded(child: _selectedDayCard(theme, d)),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _weeklyHeader(theme),
        const SizedBox(height: 8),
        SizedBox(
          height: 180,
          width: double.infinity,
          child: _weeklyChart(theme),
        ),
        const SizedBox(height: 16),
        _dailyTransactionsSection(theme),
      ],
    );
  }

  // ---- Hero ----
  Widget _todaySpendCard(ThemeData theme, Dashboard d) {
    final start = theme.colorScheme.primary;
    final end = Color.lerp(start, Colors.black, 0.22)!;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [start, end],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "TODAY'S SPEND",
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.85),
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  d.today.spentNum.toStringAsFixed(2),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 40,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  d.currency,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _remainingCard(ThemeData theme, Dashboard d) {
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.6);
    return SectionCard(
      title: 'Remaining',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _amount(
            d.today.remainingNum.toStringAsFixed(2),
            d.currency,
            (theme.textTheme.headlineSmall ?? const TextStyle()).copyWith(
              fontWeight: FontWeight.w800,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Target ${_money(d.today.targetNum, d.currency)}',
            style: theme.textTheme.bodySmall?.copyWith(color: muted),
          ),
        ],
      ),
    );
  }

  Widget _selectedDayCard(ThemeData theme, Dashboard d) {
    final sd = d.selectedDay;
    final saved = sd.savedNum;
    final savedColor = saved >= 0 ? Colors.green : Colors.red;
    final target = sd.targetNum;
    final spent = sd.spentNum;
    final remaining = target - spent;
    final over = spent > target;
    final progress = over
        ? 1.0
        : (target > 0 ? (remaining / target).clamp(0.0, 1.0) : 0.0);
    final barColor = over ? Colors.red : Colors.green;
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.6);
    final parsed = _parseDate(sd.date);
    final dayLabel = parsed != null ? _formatDay(parsed) : 'Selected day';
    return SectionCard(
      title: dayLabel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _amount(
            '${saved >= 0 ? '+' : ''}${saved.toStringAsFixed(2)}',
            d.currency,
            (theme.textTheme.headlineSmall ?? const TextStyle()).copyWith(
              fontWeight: FontWeight.w800,
              color: savedColor,
            ),
          ),
          const SizedBox(height: 4),
          Text('saved', style: theme.textTheme.bodySmall?.copyWith(color: muted)),
          const SizedBox(height: 12),
          Text('Actual ${_money(spent, d.currency)}',
              style: theme.textTheme.bodySmall),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: theme.colorScheme.onSurface.withValues(alpha: 0.1),
              color: barColor,
            ),
          ),
          const SizedBox(height: 4),
          Text('Target ${_money(target, d.currency)}',
              style: theme.textTheme.bodySmall?.copyWith(color: muted)),
        ],
      ),
    );
  }

  // ---- Weekly summary header + chart ----
  Widget _weeklyHeader(ThemeData theme) {
    final ws = _weekSummary;
    final startStr = ws?.start ?? '';
    final endStr = ws?.end ?? '';
    final start = _parseDate(startStr);
    final end = _parseDate(endStr);
    final range = (start != null && end != null)
        ? '${_formatDay(start)} – ${_formatDay(end)}'
        : '…';
    final currentMonday = _mondayOf(DateTime.now());
    final canGoForward = _selectedWeekStart.isBefore(currentMonday);
    return Row(
      children: [
        Text(
          'Weekly Summary',
          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const Spacer(),
        IconButton(
          icon: const Icon(Icons.chevron_left),
          onPressed: () => _shiftWeek(-7),
          visualDensity: VisualDensity.compact,
        ),
        GestureDetector(
          onTap: _pickWeek,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              range,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right),
          onPressed: canGoForward ? () => _shiftWeek(7) : null,
          visualDensity: VisualDensity.compact,
        ),
      ],
    );
  }

  Widget _weeklyChart(ThemeData theme) {
    final ws = _weekSummary;
    if (ws == null) return const Center(child: CircularProgressIndicator());
    const labels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    final daily = ws.daily;
    final values = List.generate(daily.length.clamp(0, 7), (i) {
      return (label: labels[i], saved: daily[i].savedNum);
    });
    final target = ws.targetNum;
    final spent = ws.spentNum;
    final remaining = target - spent;
    final over = spent > target;
    final progress = over
        ? 1.0
        : (target > 0 ? (remaining / target).clamp(0.0, 1.0) : 0.0);
    final progressColor = over ? Colors.red : Colors.green;
    final currency = _dash?.currency ?? '';
    final centerAmount = over
        ? (spent - target).toStringAsFixed(2)
        : remaining.toStringAsFixed(2);
    final currentMonday = _mondayOf(DateTime.now());
    final todayIndex =
        _selectedWeekStart == currentMonday ? DateTime.now().weekday - 1 : null;
    final selectedStr = _yyyymmdd(_selectedDay);
    int? selectedIndex;
    for (var i = 0; i < daily.length; i++) {
      if (daily[i].date == selectedStr) {
        selectedIndex = i;
        break;
      }
    }
    return WeeklyOverviewChart(
      values: values,
      progress: progress,
      progressColor: progressColor,
      centerAmount: centerAmount,
      centerLabel: over ? '$currency over' : '$currency left',
      sublabel: 'target ${target.toStringAsFixed(2)}',
      todayIndex: todayIndex,
      selectedIndex: selectedIndex,
      onBarTap: _onBarTap,
    );
  }

  // ---- Daily transactions ----
  Widget _dailyTransactionsSection(ThemeData theme) {
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.6);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Daily Transactions',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: _pickDay,
              icon: const Icon(Icons.calendar_today_outlined, size: 18),
              label: Text(_formatDay(_selectedDay)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_txLoading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_transactions.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text(
                'No transactions recorded.',
                style: theme.textTheme.bodyMedium?.copyWith(color: muted),
              ),
            ),
          )
        else
          ..._transactions.map((t) => _transactionTile(theme, t)),
      ],
    );
  }

  Widget _transactionTile(ThemeData theme, Transaction t) {
    final isCredit = t.isCredit;
    final amountColor = isCredit ? Colors.green : Colors.red;
    final sign = isCredit ? '+' : '';
    final dt = DateTime.tryParse(t.occurredAt)?.toLocal();
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      leading: AppIconCircle(packageName: t.packageName, repo: _repo),
      title: Text(
        t.appName.isNotEmpty ? t.appName : t.packageName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        _formatDateTime(dt),
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
        ),
      ),
      trailing: Text(
        '$sign${t.amountNum.toStringAsFixed(2)} ${t.currency}',
        style: theme.textTheme.bodyLarge?.copyWith(
          color: amountColor,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
