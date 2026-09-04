import 'models.dart';

class DemoData {
  static FinanceState create([DateTime? now]) {
    final current = now ?? DateTime.now();
    final month =
        '${current.year.toString().padLeft(4, '0')}-${current.month.toString().padLeft(2, '0')}';
    String date(int day) => '$month-${day.toString().padLeft(2, '0')}';

    return FinanceState(
      currentMonth: month,
      defaultAccountId: 'alipay',
      categories: const [
        Category(id: 'food', name: '餐饮'),
        Category(id: 'transport', name: '交通'),
        Category(id: 'shopping', name: '购物'),
        Category(id: 'home', name: '住房'),
        Category(id: 'entertainment', name: '娱乐'),
        Category(id: 'health', name: '健康'),
        Category(id: 'salary', name: '工资'),
        Category(id: 'other', name: '其他'),
      ],
      accounts: const [
        Account(
            id: 'cash',
            name: '现金',
            type: AccountType.asset,
            openingBalance: 208,
            isLiquid: true),
        Account(
            id: 'bank',
            name: '银行卡',
            type: AccountType.asset,
            openingBalance: 1500,
            isLiquid: true),
        Account(
            id: 'alipay',
            name: '支付宝',
            type: AccountType.asset,
            openingBalance: 1000,
            isLiquid: true,
            isDefaultPayment: true),
        Account(
            id: 'wechat',
            name: '微信',
            type: AccountType.asset,
            openingBalance: 400,
            isLiquid: true),
        Account(
            id: 'credit',
            name: '信用卡',
            type: AccountType.liability,
            openingBalance: 2180),
      ],
      transactions: [
        FinanceTransaction(
            id: 'tx-01',
            date: date(1),
            type: TransactionType.income,
            amount: 18500,
            categoryId: 'salary',
            accountId: 'bank',
            note: '9 月工资'),
        FinanceTransaction(
            id: 'tx-02',
            date: date(1),
            type: TransactionType.expense,
            amount: 32,
            categoryId: 'food',
            accountId: 'alipay',
            note: '今天中午外卖'),
        FinanceTransaction(
            id: 'tx-03',
            date: date(2),
            type: TransactionType.expense,
            amount: 68,
            categoryId: 'food',
            accountId: 'alipay',
            note: '和同事午餐'),
        FinanceTransaction(
            id: 'tx-04',
            date: date(3),
            type: TransactionType.expense,
            amount: 168,
            categoryId: 'food',
            accountId: 'alipay',
            note: '周末晚餐'),
        FinanceTransaction(
            id: 'tx-05',
            date: date(4),
            type: TransactionType.expense,
            amount: 96,
            categoryId: 'transport',
            accountId: 'alipay',
            note: '打车去客户公司'),
        FinanceTransaction(
            id: 'tx-06',
            date: date(5),
            type: TransactionType.expense,
            amount: 420,
            categoryId: 'shopping',
            accountId: 'bank',
            note: '日用品补货'),
        FinanceTransaction(
            id: 'tx-07',
            date: date(6),
            type: TransactionType.expense,
            amount: 350,
            categoryId: 'home',
            accountId: 'bank',
            note: '水电燃气'),
        FinanceTransaction(
            id: 'tx-08',
            date: date(7),
            type: TransactionType.expense,
            amount: 199,
            categoryId: 'entertainment',
            accountId: 'wechat',
            note: '电影和零食'),
        FinanceTransaction(
            id: 'tx-09',
            date: date(8),
            type: TransactionType.expense,
            amount: 128,
            categoryId: 'food',
            accountId: 'wechat',
            note: '晚餐'),
        FinanceTransaction(
            id: 'tx-10',
            date: date(9),
            type: TransactionType.expense,
            amount: 92,
            categoryId: 'transport',
            accountId: 'alipay',
            note: '往返地铁和打车'),
        FinanceTransaction(
            id: 'tx-11',
            date: date(10),
            type: TransactionType.expense,
            amount: 88,
            categoryId: 'other',
            accountId: 'cash',
            note: '咖啡和杂费'),
        FinanceTransaction(
            id: 'tx-12',
            date: date(11),
            type: TransactionType.expense,
            amount: 3647,
            categoryId: 'home',
            accountId: 'bank',
            note: '本月房租'),
      ],
      budgets: const [
        Budget(id: 'budget-food', month: '', categoryId: 'food', limit: 620),
        Budget(
            id: 'budget-transport',
            month: '',
            categoryId: 'transport',
            limit: 300),
        Budget(
            id: 'budget-shopping',
            month: '',
            categoryId: 'shopping',
            limit: 800),
        Budget(
            id: 'budget-entertainment',
            month: '',
            categoryId: 'entertainment',
            limit: 400),
        Budget(id: 'budget-home', month: '', categoryId: 'home', limit: 4000),
      ]
          .map((budget) => Budget(
              id: budget.id,
              month: month,
              categoryId: budget.categoryId,
              limit: budget.limit))
          .toList(),
      goals: const [
        Goal(
            id: 'goal-emergency',
            name: '应急金',
            target: 30000,
            liquidAccountIds: ['cash', 'bank', 'alipay', 'wechat']),
      ],
      reports: [
        Report(
            id: 'report-$month',
            month: month,
            title: '本月结余正在形成安全垫',
            summary: '本月报告基于当前账目和预算生成，详细建议仍需你确认。',
            generatedAt: current.toIso8601String()),
      ],
    );
  }
}
