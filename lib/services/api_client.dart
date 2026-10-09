import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Dart HTTP client for the Expense Tracker API.
class ApiClient {
  ApiClient();

  static const String baseUrl = 'http://192.168.68.53:3001';
  static const Duration timeout = Duration(seconds: 10);

  static const _dashboardCacheKey = 'cached_dashboard';

  /// Read the last cached dashboard JSON (for instant load on app open).
  Future<String?> getCachedDashboardJson() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_dashboardCacheKey);
  }

  Future<void> _cacheDashboard(String json) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_dashboardCacheKey, json);
  }

  /// `GET /dashboard?userId=…[&day=YYYY-MM-DD]` — everything the home screen
  /// needs. `day` selects the `selectedDay` summary (defaults to yesterday,
  /// capped at yesterday if today/future). Returns null on 404. Caches the
  /// raw response on success for instant next-load.
  Future<Dashboard?> getDashboard(String userId, {String? day}) async {
    final qs =
        day == null ? 'userId=$userId' : 'userId=$userId&day=$day';
    final resp = await http
        .get(Uri.parse('$baseUrl/dashboard?$qs'))
        .timeout(timeout);
    if (resp.statusCode == 404) return null;
    if (resp.statusCode != 200) {
      throw Exception('Dashboard fetch failed: HTTP ${resp.statusCode}');
    }
    final body = resp.body;
    await _cacheDashboard(body);
    return Dashboard.fromJson(jsonDecode(body) as Map<String, dynamic>);
  }

  /// `POST /user-settings` (partial upsert). Only provided fields are written.
  Future<void> postUserSettings(String userId, Map<String, dynamic> partial) async {
    final resp = await http
        .post(
          Uri.parse('$baseUrl/user-settings'),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({'userId': userId, ...partial}),
        )
        .timeout(timeout);
    if (resp.statusCode != 200 && resp.statusCode != 201) {
      throw Exception('user-settings POST failed: HTTP ${resp.statusCode}');
    }
  }

  /// `GET /user-settings/:userId`. Returns null on 404 (no row yet).
  Future<UserSettings?> getUserSettings(String userId) async {
    final resp = await http
        .get(Uri.parse('$baseUrl/user-settings/$userId'))
        .timeout(timeout);
    if (resp.statusCode == 404) return null;
    if (resp.statusCode != 200) {
      throw Exception('user-settings GET failed: HTTP ${resp.statusCode}');
    }
    return UserSettings.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
  }

  /// `GET /weeks?userId=…&week=YYYY-MM-DD` — week block for the ISO-Monday week
  /// containing `week` (omit for the current week). Returns null on 404.
  Future<WeekSummary?> getWeek(String userId, {String? week}) async {
    final qs = week == null ? 'userId=$userId' : 'userId=$userId&week=$week';
    final resp =
        await http.get(Uri.parse('$baseUrl/weeks?$qs')).timeout(timeout);
    if (resp.statusCode == 404) return null;
    if (resp.statusCode != 200) {
      throw Exception('Week fetch failed: HTTP ${resp.statusCode}');
    }
    return WeekSummary.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
  }

  /// `GET /transactions?userId=…&from=YYYY-MM-DD&to=YYYY-MM-DD` — date-range
  /// filtered transactions (from inclusive, to exclusive).
  Future<List<Transaction>> getTransactions(
    String userId, {
    required String from,
    required String to,
  }) async {
    final resp = await http
        .get(Uri.parse(
            '$baseUrl/transactions?userId=$userId&from=$from&to=$to'))
        .timeout(timeout);
    if (resp.statusCode != 200) {
      throw Exception('Transactions fetch failed: HTTP ${resp.statusCode}');
    }
    final decoded = jsonDecode(resp.body);
    final List<dynamic> list = decoded is List ? decoded : const [];
    return list
        .map((e) => Transaction.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  /// `GET /balance?userId=…` — total + per-source net balance.
  Future<BalanceSummary> getBalance(String userId) async {
    final resp = await http
        .get(Uri.parse('$baseUrl/balance?userId=$userId'))
        .timeout(timeout);
    if (resp.statusCode != 200) {
      throw Exception('Balance fetch failed: HTTP ${resp.statusCode}');
    }
    return BalanceSummary.fromJson(
        jsonDecode(resp.body) as Map<String, dynamic>);
  }

  /// `GET /year?userId=…&year=YYYY` — 12-month income/expense/saved summary.
  Future<YearSummary> getYear(String userId, {required int year}) async {
    final resp = await http
        .get(Uri.parse('$baseUrl/year?userId=$userId&year=$year'))
        .timeout(timeout);
    if (resp.statusCode != 200) {
      throw Exception('Year fetch failed: HTTP ${resp.statusCode}');
    }
    return YearSummary.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
  }

  /// First-launch seed: timezone + currency so `/dashboard` doesn't 404.
  Future<void> ensureUserSettings(
    String userId, {
    String timezone = 'Asia/Hong_Kong',
    String currency = 'HKD',
  }) =>
      postUserSettings(userId, {'timezone': timezone, 'currency': currency});
}

/// One day's summary. Fields are nullable because future days have no data yet
/// (the API returns `null`, not `0`, for days that haven't happened).
class DaySummary {
  const DaySummary({
    required this.date,
    this.target,
    this.spent,
    this.saved,
    this.remaining,
    this.projected = false,
  });

  final String date;
  final String? target;
  final String? spent;
  final String? saved;
  final String? remaining;
  final bool projected;

  double get targetNum => double.tryParse(target ?? '') ?? 0;
  double get spentNum => double.tryParse(spent ?? '') ?? 0;
  double get savedNum => double.tryParse(saved ?? '') ?? 0;
  double get remainingNum => double.tryParse(remaining ?? '') ?? 0;

  /// True if this day has any data (not a future/null day).
  bool get hasData => target != null || spent != null;

  factory DaySummary.fromJson(Map<String, dynamic> j) => DaySummary(
        date: j['date'] as String? ?? '',
        target: j['target']?.toString(),
        spent: j['spent']?.toString(),
        saved: j['saved']?.toString(),
        remaining: j['remaining']?.toString(),
        projected: j['projected'] as bool? ?? false,
      );
}

class WeekSummary {
  const WeekSummary({
    required this.start,
    required this.end,
    required this.budget,
    required this.target,
    required this.spent,
    required this.remaining,
    required this.daily,
  });

  final String start;
  final String end;
  final String budget;
  final String target;
  final String spent;
  final String remaining;
  final List<DaySummary> daily;

  double get budgetNum => double.tryParse(budget) ?? 0;
  double get targetNum => double.tryParse(target) ?? 0;
  double get spentNum => double.tryParse(spent) ?? 0;
  double get remainingNum => double.tryParse(remaining) ?? 0;

  factory WeekSummary.fromJson(Map<String, dynamic> j) => WeekSummary(
        start: j['start'] as String? ?? '',
        end: j['end'] as String? ?? '',
        budget: j['budget']?.toString() ?? '0',
        target: j['target']?.toString() ?? '0',
        spent: j['spent']?.toString() ?? '0',
        remaining: j['remaining']?.toString() ?? '0',
        daily: (j['daily'] as List? ?? const [])
            .map((e) => DaySummary.fromJson(e as Map<String, dynamic>))
            .toList(growable: false),
      );
}

/// Monthly summary from `/dashboard.month`.
class MonthSummary {
  const MonthSummary({
    required this.start,
    required this.end,
    required this.budget,
    required this.spent,
    required this.remaining,
    this.incomeStatus = '',
    this.incomeReceived = '0',
    this.incomeExpected = '0',
    this.extraIncome = '0',
  });

  final String start;
  final String end;
  final String budget;
  final String spent;
  final String remaining;
  final String incomeStatus;
  final String incomeReceived;
  final String incomeExpected;
  final String extraIncome;

  double get budgetNum => double.tryParse(budget) ?? 0;
  double get spentNum => double.tryParse(spent) ?? 0;
  double get remainingNum => double.tryParse(remaining) ?? 0;
  double get incomeReceivedNum => double.tryParse(incomeReceived) ?? 0;
  double get incomeExpectedNum => double.tryParse(incomeExpected) ?? 0;
  bool get isFulfilled => incomeStatus == 'fulfilled';

  factory MonthSummary.fromJson(Map<String, dynamic> j) => MonthSummary(
        start: j['start'] as String? ?? '',
        end: j['end'] as String? ?? '',
        budget: j['budget']?.toString() ?? '0',
        spent: j['spent']?.toString() ?? '0',
        remaining: j['remaining']?.toString() ?? '0',
        incomeStatus: j['incomeStatus'] as String? ?? '',
        incomeReceived: j['incomeReceived']?.toString() ?? '0',
        incomeExpected: j['incomeExpected']?.toString() ?? '0',
        extraIncome: j['extraIncome']?.toString() ?? '0',
      );
}

/// The full `/dashboard` response.
class Dashboard {
  const Dashboard({
    required this.currency,
    required this.today,
    required this.selectedDay,
    required this.week,
    this.month,
  });

  final String currency;
  final DaySummary today;
  final DaySummary selectedDay;
  final WeekSummary week;
  final MonthSummary? month;

  factory Dashboard.fromJson(Map<String, dynamic> j) => Dashboard(
        currency: j['currency'] as String? ?? '',
        today: DaySummary.fromJson(j['today'] as Map<String, dynamic>? ?? const {}),
        selectedDay: DaySummary.fromJson(
            j['selectedDay'] as Map<String, dynamic>? ?? const {}),
        week: WeekSummary.fromJson(j['week'] as Map<String, dynamic>? ?? const {}),
        month: j['month'] != null
            ? MonthSummary.fromJson(j['month'] as Map<String, dynamic>)
            : null,
      );
}

/// `/user-settings` row. `monthlyIncome` is null when income is derived from
/// transactions (incomeMode == "transactions").
class UserSettings {
  const UserSettings({
    this.monthlyIncome,
    required this.incomeMode,
    required this.incomeLookbackMonths,
    required this.savingsTarget,
    required this.timezone,
    required this.currency,
    required this.weekStart,
  });

  final String? monthlyIncome; // numeric string, nullable
  final String incomeMode; // "transactions" | "manual"
  final int incomeLookbackMonths;
  final String savingsTarget; // numeric string
  final String timezone;
  final String currency;
  final int weekStart;

  bool get isManual => incomeMode == 'manual';

  factory UserSettings.fromJson(Map<String, dynamic> j) => UserSettings(
        monthlyIncome: j['monthlyIncome']?.toString(),
        incomeMode: j['incomeMode'] as String? ?? 'transactions',
        incomeLookbackMonths: (j['incomeLookbackMonths'] as num?)?.toInt() ?? 3,
        savingsTarget: j['savingsTarget']?.toString() ?? '0',
        timezone: j['timezone'] as String? ?? 'UTC',
        currency: j['currency'] as String? ?? 'HKD',
        weekStart: (j['weekStart'] as num?)?.toInt() ?? 1,
      );
}

/// A single transaction row from `/transactions`.
class Transaction {
  const Transaction({
    required this.id,
    required this.packageName,
    required this.appName,
    required this.amount,
    required this.currency,
    required this.merchant,
    required this.occurredAt,
    required this.location,
  });

  final String id;
  final String packageName;
  final String appName;
  final String amount; // numeric string; sign: +credit / -debit
  final String currency;
  final String merchant;
  final String occurredAt; // ISO timestamp
  final String location;

  double get amountNum => double.tryParse(amount) ?? 0;
  bool get isCredit => amountNum >= 0;

  factory Transaction.fromJson(Map<String, dynamic> j) => Transaction(
        id: j['id']?.toString() ?? '',
        packageName: j['packageName'] as String? ?? '',
        appName: j['appName'] as String? ?? '',
        amount: j['amount']?.toString() ?? '0',
        currency: j['currency'] as String? ?? '',
        merchant: j['merchant'] as String? ?? '',
        occurredAt: j['occurredAt'] as String? ?? '',
        location: j['location'] as String? ?? '',
      );
}

/// `/balance` response — total + per-source net balances.
class BalanceSummary {
  const BalanceSummary({
    required this.currency,
    required this.totalBalance,
    required this.sources,
  });

  final String currency;
  final String totalBalance;
  final List<BalanceSource> sources;

  double get totalBalanceNum => double.tryParse(totalBalance) ?? 0;

  factory BalanceSummary.fromJson(Map<String, dynamic> j) => BalanceSummary(
        currency: j['currency'] as String? ?? '',
        totalBalance: j['totalBalance']?.toString() ?? '0',
        sources: (j['sources'] as List? ?? const [])
            .map((e) => BalanceSource.fromJson(e as Map<String, dynamic>))
            .toList(growable: false),
      );
}

/// One source's net balance (a source = the app that produced transactions).
class BalanceSource {
  const BalanceSource({
    required this.packageName,
    required this.appName,
    required this.balance,
    required this.transactionCount,
  });

  final String packageName;
  final String appName;
  final String balance;
  final int transactionCount;

  double get balanceNum => double.tryParse(balance) ?? 0;

  factory BalanceSource.fromJson(Map<String, dynamic> j) => BalanceSource(
        packageName: j['packageName'] as String? ?? '',
        appName: j['appName'] as String? ?? '',
        balance: j['balance']?.toString() ?? '0',
        transactionCount: (j['transactionCount'] as num?)?.toInt() ?? 0,
      );
}

/// `/year` response — 12 months of income/expense/saved.
class YearSummary {
  const YearSummary({
    required this.year,
    required this.currency,
    required this.months,
  });

  final int year;
  final String currency;
  final List<MonthEntry> months;

  /// Returns the entry for [month] (1-12), or null.
  MonthEntry? entryFor(int month) {
    for (final e in months) {
      if (e.month == month) return e;
    }
    return null;
  }

  factory YearSummary.fromJson(Map<String, dynamic> j) => YearSummary(
        year: (j['year'] as num?)?.toInt() ?? 0,
        currency: j['currency'] as String? ?? '',
        months: (j['months'] as List? ?? const [])
            .map((e) => MonthEntry.fromJson(e as Map<String, dynamic>))
            .toList(growable: false),
      );
}

/// One month's aggregated summary in the year view.
class MonthEntry {
  const MonthEntry({
    required this.month,
    this.income,
    this.expense,
    this.saved,
  });

  final int month; // 1-12
  final String? income;
  final String? expense;
  final String? saved;

  double get incomeNum => double.tryParse(income ?? '') ?? 0;
  double get expenseNum => double.tryParse(expense ?? '') ?? 0;
  double get savedNum => double.tryParse(saved ?? '') ?? 0;

  factory MonthEntry.fromJson(Map<String, dynamic> j) => MonthEntry(
        month: (j['month'] as num?)?.toInt() ?? 0,
        income: j['income']?.toString(),
        expense: j['expense']?.toString(),
        saved: j['saved']?.toString(),
      );
}
