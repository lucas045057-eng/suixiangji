const STORAGE_KEY = 'wealthmate-state-v1';

const DEFAULT_CATEGORIES = ['餐饮', '交通', '购物', '住房', '娱乐', '健康', '工资', '其他'];

const clone = (value) => JSON.parse(JSON.stringify(value));

const toDateKey = (date) => {
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, '0');
  const day = String(date.getDate()).padStart(2, '0');
  return `${year}-${month}-${day}`;
};

const round = (value, digits = 2) => {
  const factor = 10 ** digits;
  return Math.round((value + Number.EPSILON) * factor) / factor;
};

const monthOf = (date) => String(date).slice(0, 7);

export function createSeedState() {
  return {
    version: 1,
    settings: {
      currency: '¥',
      currentMonth: '2026-09',
      profileName: '林默',
    },
    categories: DEFAULT_CATEGORIES.map((name) => ({ id: name, name, active: true })),
    accounts: [
      { id: 'cash', name: '现金', type: 'asset', openingBalance: 208, icon: 'wallet', color: '#73c7b6' },
      { id: 'bank', name: '银行卡', type: 'asset', openingBalance: 1500, icon: 'card', color: '#6a6cf4' },
      { id: 'alipay', name: '支付宝', type: 'asset', openingBalance: 1000, icon: 'alipay', color: '#48a9ed' },
      { id: 'wechat', name: '微信', type: 'asset', openingBalance: 400, icon: 'wechat', color: '#46bb82' },
      { id: 'credit', name: '信用卡', type: 'liability', openingBalance: 2180, icon: 'credit', color: '#ef9b68' },
    ],
    transactions: [
      { id: 'tx-01', date: '2026-09-01', type: 'income', amount: 18500, category: '工资', accountId: 'bank', note: '9 月工资', merchant: '公司', createdAt: '2026-09-01T09:00:00+08:00' },
      { id: 'tx-02', date: '2026-09-01', type: 'expense', amount: 32, category: '餐饮', accountId: 'alipay', note: '今天中午外卖', merchant: '美团外卖', createdAt: '2026-09-01T12:30:00+08:00' },
      { id: 'tx-03', date: '2026-09-02', type: 'expense', amount: 68, category: '餐饮', accountId: 'alipay', note: '和同事午餐', merchant: '公司楼下', createdAt: '2026-09-02T12:30:00+08:00' },
      { id: 'tx-04', date: '2026-09-03', type: 'expense', amount: 168, category: '餐饮', accountId: 'alipay', note: '周末晚餐', merchant: '小馆子', createdAt: '2026-09-03T19:20:00+08:00' },
      { id: 'tx-05', date: '2026-09-04', type: 'expense', amount: 96, category: '交通', accountId: 'alipay', note: '打车去客户公司', merchant: '滴滴', createdAt: '2026-09-04T08:40:00+08:00' },
      { id: 'tx-06', date: '2026-09-05', type: 'expense', amount: 420, category: '购物', accountId: 'bank', note: '日用品补货', merchant: '盒马', createdAt: '2026-09-05T15:10:00+08:00' },
      { id: 'tx-07', date: '2026-09-06', type: 'expense', amount: 350, category: '住房', accountId: 'bank', note: '水电燃气', merchant: '生活缴费', createdAt: '2026-09-06T18:00:00+08:00' },
      { id: 'tx-08', date: '2026-09-07', type: 'expense', amount: 199, category: '娱乐', accountId: 'wechat', note: '电影和零食', merchant: '猫眼', createdAt: '2026-09-07T20:15:00+08:00' },
      { id: 'tx-09', date: '2026-09-08', type: 'expense', amount: 128, category: '餐饮', accountId: 'wechat', note: '晚餐', merchant: '日料店', createdAt: '2026-09-08T19:00:00+08:00' },
      { id: 'tx-10', date: '2026-09-09', type: 'expense', amount: 92, category: '交通', accountId: 'alipay', note: '往返地铁和打车', merchant: '出行', createdAt: '2026-09-09T18:20:00+08:00' },
      { id: 'tx-11', date: '2026-09-10', type: 'expense', amount: 88, category: '其他', accountId: 'cash', note: '咖啡和杂费', merchant: '便利店', createdAt: '2026-09-10T10:10:00+08:00' },
      { id: 'tx-12', date: '2026-09-11', type: 'expense', amount: 3647, category: '住房', accountId: 'bank', note: '本月房租', merchant: '房租', createdAt: '2026-09-11T09:10:00+08:00' },
    ],
    budgets: [
      { id: 'budget-food', month: '2026-09', category: '餐饮', limit: 620 },
      { id: 'budget-transport', month: '2026-09', category: '交通', limit: 300 },
      { id: 'budget-shopping', month: '2026-09', category: '购物', limit: 800 },
      { id: 'budget-entertainment', month: '2026-09', category: '娱乐', limit: 400 },
      { id: 'budget-home', month: '2026-09', category: '住房', limit: 4000 },
    ],
    goals: [
      { id: 'goal-emergency', name: '应急金', target: 30000, currentMode: 'netWorth', deadline: '2027-06' },
    ],
    netWorthSnapshots: [
      { month: '2026-05', value: 9120 },
      { month: '2026-06', value: 10480 },
      { month: '2026-07', value: 11630 },
      { month: '2026-08', value: 13120 },
      { month: '2026-09', value: 14140 },
    ],
    updatedAt: '2026-09-11T09:10:00+08:00',
  };
}

export function getAccountBalances(state) {
  return state.accounts.map((account) => {
    const delta = state.transactions.filter((transaction) => !transaction.deletedAt).reduce((sum, transaction) => {
      if (transaction.accountId !== account.id) return sum;
      if (account.type === 'liability') {
        return sum + (transaction.type === 'expense' ? transaction.amount : -transaction.amount);
      }
      return sum + (transaction.type === 'income' ? transaction.amount : -transaction.amount);
    }, 0);
    return { ...account, balance: round(account.openingBalance + delta) };
  });
}

export function deriveMetrics(state, monthKey = state.settings?.currentMonth) {
  const monthTransactions = state.transactions.filter((transaction) => !transaction.deletedAt && monthOf(transaction.date) === monthKey);
  const income = round(monthTransactions.filter((transaction) => transaction.type === 'income').reduce((sum, transaction) => sum + transaction.amount, 0));
  const expense = round(monthTransactions.filter((transaction) => transaction.type === 'expense').reduce((sum, transaction) => sum + transaction.amount, 0));
  const savings = round(income - expense);
  const savingsRate = income ? round(savings / income, 3) : 0;
  const accountBalances = getAccountBalances(state);
  const assets = round(accountBalances.filter((account) => account.type === 'asset').reduce((sum, account) => sum + account.balance, 0));
  const liabilities = round(accountBalances.filter((account) => account.type === 'liability').reduce((sum, account) => sum + account.balance, 0));
  const netWorth = round(assets - liabilities);
  const budgetUsage = state.budgets
    .filter((budget) => budget.month === monthKey)
    .map((budget) => {
      const spent = round(monthTransactions.filter((transaction) => transaction.type === 'expense' && transaction.category === budget.category).reduce((sum, transaction) => sum + transaction.amount, 0));
      const ratio = budget.limit ? spent / budget.limit : 0;
      const percent = round(ratio);
      return { ...budget, spent, percent, status: ratio >= 1 ? 'over' : ratio >= 0.8 ? 'warning' : 'healthy' };
    });
  const goal = state.goals[0];
  const goalProgress = goal ? round(Math.min(netWorth / goal.target, 1), 3) : 0;
  const remainingMonths = goal && savings > 0 && netWorth < goal.target ? Math.ceil((goal.target - netWorth) / savings) : 0;

  return { monthKey, monthTransactions, income, expense, savings, savingsRate, accountBalances, assets, liabilities, netWorth, budgetUsage, goal, goalProgress, remainingMonths };
}

const categoryFromText = (text) => {
  const rules = [
    { category: '餐饮', words: ['外卖', '吃', '餐', '饭', '咖啡', '星巴克', '奶茶', '火锅', '日料', '美团'] },
    { category: '交通', words: ['打车', '滴滴', '地铁', '公交', '交通', '加油', '出行'] },
    { category: '购物', words: ['购物', '淘宝', '京东', '超市', '盒马', '买', '日用品'] },
    { category: '住房', words: ['房租', '房贷', '水电', '物业', '燃气'] },
    { category: '娱乐', words: ['电影', '游戏', '娱乐', '演唱会'] },
    { category: '健康', words: ['医院', '看病', '药', '健身'] },
    { category: '工资', words: ['工资', '薪资', '奖金', '报销', '到账', '收入'] },
  ];
  return rules.find((rule) => rule.words.some((word) => text.includes(word)))?.category ?? '其他';
};

const accountFromText = (text) => {
  if (text.includes('支付宝')) return 'alipay';
  if (text.includes('微信')) return 'wechat';
  if (text.includes('银行卡') || text.includes('银行')) return 'bank';
  if (text.includes('现金')) return 'cash';
  if (text.includes('信用卡')) return 'credit';
  return 'alipay';
};

export function parseNaturalLanguage(text, now = new Date()) {
  const amountMatch = text.replace(/,/g, '').match(/(?:¥|￥)?\s*(\d+(?:\.\d+)?)\s*(?:元|块|块钱)?/);
  const amount = amountMatch ? Number(amountMatch[1]) : 0;
  const type = /工资|薪资|奖金|报销|到账|收入|收到/.test(text) ? 'income' : 'expense';
  const date = new Date(now);
  if (text.includes('前天')) date.setDate(date.getDate() - 2);
  else if (text.includes('昨天')) date.setDate(date.getDate() - 1);
  const category = categoryFromText(text);
  const confidence = amount > 0 && category !== '其他' ? 0.98 : amount > 0 ? 0.72 : 0.35;
  return {
    amount,
    type,
    category,
    accountId: accountFromText(text),
    date: toDateKey(date),
    note: text,
    confidence,
  };
}

export function addTransaction(state, transaction) {
  const next = clone(state);
  const id = transaction.id ?? `tx-${Date.now()}-${Math.random().toString(36).slice(2, 7)}`;
  next.transactions.push({ ...transaction, id, amount: Number(transaction.amount), createdAt: transaction.createdAt ?? new Date().toISOString() });
  next.updatedAt = new Date().toISOString();
  return next;
}

export function loadState() {
  if (typeof window === 'undefined' || !window.localStorage) return createSeedState();
  try {
    const stored = window.localStorage.getItem(STORAGE_KEY);
    return stored ? JSON.parse(stored) : createSeedState();
  } catch {
    return createSeedState();
  }
}

export function saveState(state) {
  if (typeof window !== 'undefined' && window.localStorage) window.localStorage.setItem(STORAGE_KEY, JSON.stringify(state));
}

export function getMonthlySeries(state, count = 6) {
  const snapshots = [...(state.netWorthSnapshots ?? [])].sort((a, b) => a.month.localeCompare(b.month));
  const selected = snapshots.slice(-count);
  const liveMonth = state.settings?.currentMonth;
  const liveMetrics = deriveMetrics(state, liveMonth);
  return {
    labels: selected.map((item) => `${Number(item.month.slice(5))}月`),
    values: selected.map((item) => item.month === liveMonth ? liveMetrics.netWorth : item.value),
    months: selected.map((item) => item.month),
  };
}

export function generateInsights(metrics, state) {
  const insights = [];
  const highestBudget = [...metrics.budgetUsage].sort((a, b) => b.percent - a.percent)[0];
  if (highestBudget) {
    const percent = Math.round(highestBudget.percent * 100);
    insights.push({
      severity: highestBudget.status === 'healthy' ? 'good' : 'warning',
      icon: highestBudget.status === 'healthy' ? 'check' : 'alert',
      title: `${highestBudget.category}预算已使用 ${percent}%`,
      body: highestBudget.status === 'over'
        ? `本月已经超出预算 ${formatMoney(highestBudget.spent - highestBudget.limit)}，可以把接下来两周的预算先锁定下来。`
        : `还剩 ${formatMoney(highestBudget.limit - highestBudget.spent)}，目前节奏还在可控范围内。`,
      tag: highestBudget.status === 'over' ? '需要关注' : '保持节奏',
    });
  }
  if (metrics.goal) {
    insights.push({
      severity: 'neutral',
      icon: 'target',
      title: `应急金距离目标还有 ${formatMoney(Math.max(metrics.goal.target - metrics.netWorth, 0))}`,
      body: metrics.remainingMonths ? `按本月结余速度，预计还需 ${metrics.remainingMonths} 个月达成。每月先留出固定金额，目标会更稳。` : '当前已经达到目标，接下来可以把新增结余分配给下一个目标。',
      tag: '财富目标',
    });
  }
  insights.push({
    severity: metrics.savingsRate >= 0.3 ? 'good' : 'warning',
    icon: metrics.savingsRate >= 0.3 ? 'trend' : 'alert',
    title: `本月储蓄率 ${Math.round(metrics.savingsRate * 100)}%`,
    body: metrics.savingsRate >= 0.3 ? '结余正在形成稳定的安全垫，继续保持收入到账后先留存的习惯。' : '本月结余偏少，可以从一项可延后的支出开始做轻量调整。',
    tag: metrics.savingsRate >= 0.3 ? '积极信号' : '优化空间',
  });
  return insights;
}

const iconPaths = {
  spark: '<path d="m12 2 1.5 6.5L20 10l-6.5 1.5L12 18l-1.5-6.5L4 10l6.5-1.5L12 2Z"/><path d="m19 16 .6 2.4L22 19l-2.4.6L19 22l-.6-2.4L16 19l2.4-.6L19 16Z"/>',
  grid: '<rect x="3" y="3" width="7" height="7" rx="1.5"/><rect x="14" y="3" width="7" height="7" rx="1.5"/><rect x="3" y="14" width="7" height="7" rx="1.5"/><rect x="14" y="14" width="7" height="7" rx="1.5"/>',
  receipt: '<path d="M6 3h12a1 1 0 0 1 1 1v17l-3-2-2 2-2-2-2 2-2-2-3 2V4a1 1 0 0 1 1-1Z"/><path d="M9 8h6M9 12h6M9 16h3"/>',
  wallet: '<path d="M4 6.5A2.5 2.5 0 0 1 6.5 4H19a1 1 0 0 1 1 1v14H6.5A2.5 2.5 0 0 1 4 16.5v-10Z"/><path d="M4 7h14a2 2 0 0 1 2 2v2h-5a2 2 0 0 0 0 4h5v4"/><path d="M15 13h.01"/>',
  target: '<circle cx="12" cy="12" r="8.5"/><circle cx="12" cy="12" r="4.5"/><path d="m15.5 8.5 4-4M17 4.5h2.5V7"/>',
  chart: '<path d="M4 19V5M4 19h16"/><path d="m7 15 3-4 3 2 5-7"/>',
  settings: '<path d="M12 8.5a3.5 3.5 0 1 0 0 7 3.5 3.5 0 0 0 0-7Z"/><path d="m19.4 15 .1.1a1.8 1.8 0 1 1-2.5 2.5l-.1-.1a1.8 1.8 0 0 0-3 .8v.2a1.8 1.8 0 1 1-3.6 0v-.2a1.8 1.8 0 0 0-3-.8l-.1.1a1.8 1.8 0 1 1-2.5-2.5l.1-.1a1.8 1.8 0 0 0-.8-3h-.2a1.8 1.8 0 1 1 0-3.6h.2a1.8 1.8 0 0 0 .8-3l-.1-.1a1.8 1.8 0 1 1 2.5-2.5l.1.1a1.8 1.8 0 0 0 3-.8V2a1.8 1.8 0 1 1 3.6 0v.2a1.8 1.8 0 0 0 3 .8l.1-.1a1.8 1.8 0 1 1 2.5 2.5l-.1.1a1.8 1.8 0 0 0 .8 3h.2a1.8 1.8 0 1 1 0 3.6h-.2a1.8 1.8 0 0 0-.8 3Z"/>',
  plus: '<path d="M12 5v14M5 12h14"/>',
  bell: '<path d="M18 9a6 6 0 0 0-12 0c0 7-3 7-3 9h18c0-2-3-2-3-9ZM10 21h4"/>',
  arrow: '<path d="M5 12h13M13 6l6 6-6 6"/>',
  search: '<circle cx="10.8" cy="10.8" r="6.3"/><path d="m16 16 4 4"/>',
  more: '<circle cx="5" cy="12" r="1" fill="currentColor" stroke="none"/><circle cx="12" cy="12" r="1" fill="currentColor" stroke="none"/><circle cx="19" cy="12" r="1" fill="currentColor" stroke="none"/>',
  edit: '<path d="m4 16.5-.7 3.2 3.2-.7L18 7.5 15.5 5 4 16.5Z"/><path d="m14.5 6 2.5 2.5M5 20h14"/>',
  trash: '<path d="M5 7h14M10 11v5M14 11v5M9 7V4h6v3M7 7l1 14h8l1-14"/>',
  close: '<path d="m6 6 12 12M18 6 6 18"/>',
  chevron: '<path d="m9 5 7 7-7 7"/>',
  trend: '<path d="M4 16 9 11l3 3 7-8"/><path d="M14 6h5v5"/>',
  income: '<path d="M12 19V5M6 11l6-6 6 6"/><path d="M5 21h14"/>',
  expense: '<path d="M12 5v14M6 13l6 6 6-6"/><path d="M5 3h14"/>',
  brain: '<path d="M9.5 4.5a3 3 0 0 0-5.3 2A3.5 3.5 0 0 0 5 13a3.5 3.5 0 0 0 4.5 5.5V4.5ZM14.5 4.5a3 3 0 0 1 5.3 2A3.5 3.5 0 0 1 19 13a3.5 3.5 0 0 1-1.5 5.5V4.5ZM9.5 8h5M9.5 12h5M9.5 16h5"/>',
  calendar: '<rect x="3" y="4" width="18" height="17" rx="2"/><path d="M16 2v4M8 2v4M3 9h18"/>',
  download: '<path d="M12 3v12M7 10l5 5 5-5M4 21h16"/>',
  refresh: '<path d="M20 11a8 8 0 0 0-14.7-4L4 9M4 5v4h4M4 13a8 8 0 0 0 14.7 4L20 15M20 19v-4h-4"/>',
  alert: '<path d="M12 4 3 20h18L12 4Z"/><path d="M12 10v4M12 17h.01"/>',
  check: '<path d="m5 12 4 4L19 6"/>',
  filter: '<path d="M4 6h16M7 12h10M10 18h4"/>',
  card: '<rect x="3" y="5" width="18" height="14" rx="2"/><path d="M3 10h18M7 15h3"/>',
  alipay: '<path d="M5 5.5h14v13H5z"/><path d="M7.5 14c2.5-1.5 4.5-4.3 4.5-7M8 10h7M7.5 17c3.4-1.3 6.3-1.1 10.2.5"/>',
  wechat: '<path d="M4 13a5 5 0 0 1 5-5h3a5 5 0 0 1 5 5 5 5 0 0 1-5 5H9l-3 2 .7-2.7A5 5 0 0 1 4 13Z"/><path d="M8.5 12h.01M12 12h.01M15.5 12h.01"/>',
  credit: '<rect x="3" y="5" width="18" height="14" rx="2"/><path d="M3 10h18M7 15h5"/>',
  menu: '<path d="M4 7h16M4 12h16M4 17h16"/>',
};

const icon = (name, size = 18) => `<svg width="${size}" height="${size}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${iconPaths[name] ?? iconPaths.spark}</svg>`;
const escapeHtml = (value = '') => String(value).replace(/[&<>"']/g, (char) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#039;' }[char]));
const formatMoney = (value) => `¥${new Intl.NumberFormat('zh-CN', { maximumFractionDigits: 0 }).format(Math.round(value))}`;
const formatDate = (value) => { const date = new Date(`${value}T00:00:00`); return `${date.getMonth() + 1}月${date.getDate()}日`; };
const formatLongDate = (value) => { const date = new Date(`${value}T00:00:00`); return `${date.getFullYear()}年${date.getMonth() + 1}月${date.getDate()}日`; };
const categoryClass = (category) => ({ 餐饮: 'food', 交通: 'transport', 住房: 'home', 娱乐: 'fun', 购物: 'shopping' }[category] ?? 'other');
const categoryIcon = (category) => ({ 餐饮: 'spark', 交通: 'arrow', 住房: 'wallet', 娱乐: 'spark', 购物: 'receipt', 工资: 'income', 其他: 'grid' }[category] ?? 'grid');
const accountById = (accountId) => currentState.accounts.find((account) => account.id === accountId);
const netWorthDelta = (metrics, state) => { const previous = [...(state.netWorthSnapshots ?? [])].filter((snapshot) => snapshot.month < metrics.monthKey).sort((a, b) => a.month.localeCompare(b.month)).at(-1)?.value; return round(metrics.netWorth - (previous ?? metrics.netWorth)); };

let currentState = loadState();
let activeView = 'dashboard';
let ledgerFilter = { query: '', category: 'all', type: 'all' };
let toastTimer;

const viewMeta = {
  dashboard: { kicker: '个人财务空间', title: '仪表盘' },
  ledger: { kicker: '记录每一笔流动', title: '账本' },
  wealth: { kicker: '让钱变得更清楚', title: '财富' },
  budgets: { kicker: '给每一类支出一个边界', title: '预算' },
  insights: { kicker: '把数字变成下一步', title: '洞察' },
};

const appShell = () => `
  <div class="app-shell">
    <aside class="sidebar">
      <div class="brand">${icon('spark', 17)}<span class="brand-name">随想记</span><span class="brand-beta">BETA</span></div>
      <div class="sidebar-section-title">Workspace</div>
      <nav class="nav-list" aria-label="主要导航">
        ${navItem('dashboard', '总览', 'grid')}
        ${navItem('ledger', '账本', 'receipt')}
        ${navItem('wealth', '财富', 'wallet')}
        ${navItem('budgets', '预算', 'target', currentState.budgets.length)}
        ${navItem('insights', '洞察', 'chart')}
      </nav>
      <div class="sidebar-section-title">Account</div>
      <nav class="nav-list">
        <button class="nav-item" data-action="restore-demo">${icon('refresh')}<span>恢复演示数据</span></button>
        <button class="nav-item" data-action="export-json">${icon('download')}<span>导出数据</span></button>
      </nav>
      <div class="sidebar-footer"><div class="profile-card"><div class="avatar">林</div><div class="profile-copy"><div class="profile-name">${escapeHtml(currentState.settings.profileName)}</div><div class="profile-note">个人空间 · 本地模式</div></div><button class="profile-menu" aria-label="更多设置">${icon('more', 16)}</button></div></div>
    </aside>
    <main class="main">
      <header class="topbar"><div><div class="eyebrow" id="view-kicker">${viewMeta[activeView].kicker}</div><h1 class="page-title" id="view-title">${viewMeta[activeView].title}</h1></div><div class="topbar-actions"><div class="sync-status"><span class="sync-dot"></span>已保存到本地</div><button class="icon-button" aria-label="通知">${icon('bell', 16)}</button><div class="avatar">林</div></div></header>
      <div class="content" id="view-content"></div>
    </main>
  </div>`;

const navItem = (view, label, symbol, badge = '') => `<button class="nav-item ${activeView === view ? 'active' : ''}" data-view="${view}">${icon(symbol)}<span>${label}</span>${badge ? `<span class="nav-badge">${badge}</span>` : ''}</button>`;

const statCard = (label, value, caption, symbol, tone, trend = '') => `<article class="stat-card"><div class="stat-top"><span>${label}</span><span class="stat-icon ${tone}">${icon(symbol, 15)}</span></div><div class="stat-value">${value}</div><div class="stat-sub">${trend ? `<span class="${trend.startsWith('+') ? 'trend-up' : 'trend-down'}">${trend}</span>` : ''}<span>${caption}</span></div></article>`;

const renderLineChart = (state) => {
  const series = getMonthlySeries(state, 5);
  const width = 720; const height = 185; const padX = 28; const padTop = 17; const padBottom = 28;
  const values = series.values; const min = Math.min(...values); const max = Math.max(...values); const range = max - min || 1;
  const points = values.map((value, index) => {
    const x = padX + index * ((width - padX * 2) / Math.max(values.length - 1, 1));
    const y = padTop + (1 - (value - min) / range) * (height - padTop - padBottom);
    return { x, y, value };
  });
  const path = points.map((point, index) => `${index ? 'L' : 'M'} ${point.x} ${point.y}`).join(' ');
  const area = `${path} L ${points.at(-1)?.x ?? padX} ${height - padBottom} L ${points[0]?.x ?? padX} ${height - padBottom} Z`;
  return `<svg class="chart-svg" viewBox="0 0 ${width} ${height}" role="img" aria-label="净资产趋势图"><defs><linearGradient id="chartFill" x1="0" x2="0" y1="0" y2="1"><stop offset="0" stop-color="#a7dfc7" stop-opacity=".42"/><stop offset="1" stop-color="#a7dfc7" stop-opacity="0"/></linearGradient></defs>${[0, 1, 2, 3].map((line) => `<line class="chart-grid-line" x1="${padX}" y1="${padTop + line * 43}" x2="${width - padX}" y2="${padTop + line * 43}"/>`).join('')}<path class="chart-area" d="${area}"/><path class="chart-path" d="${path}"/>${points.map((point) => `<circle class="chart-dot" cx="${point.x}" cy="${point.y}" r="4"/>`).join('')}${series.labels.map((label, index) => `<text class="chart-label" x="${points[index].x}" y="${height - 6}" text-anchor="middle">${label}</text>`).join('')}</svg>`;
};

const categoryTotals = (state, monthKey) => {
  const totals = {};
  state.transactions.filter((tx) => !tx.deletedAt && tx.type === 'expense' && monthOf(tx.date) === monthKey).forEach((tx) => { totals[tx.category] = (totals[tx.category] ?? 0) + tx.amount; });
  return Object.entries(totals).sort((a, b) => b[1] - a[1]);
};

const renderDonut = (metrics) => {
  const totals = categoryTotals(currentState, metrics.monthKey);
  const colors = { 餐饮: '#e7a167', 交通: '#6a6cf4', 住房: '#8dc8b8', 娱乐: '#d37de0', 购物: '#4a9bd7', 其他: '#b6c4bd' };
  const total = totals.reduce((sum, [, value]) => sum + value, 0) || 1;
  let cursor = 0;
  const stops = totals.map(([category, value]) => { const start = cursor; cursor += (value / total) * 100; return `${colors[category] ?? colors.其他} ${start}% ${cursor}%`; }).join(', ');
  return `<div class="donut" style="background:conic-gradient(${stops || '#dbe8e0 0 100%'});"><div class="donut-center"><strong>${formatMoney(metrics.expense)}</strong><span>本月支出</span></div></div>`;
};

const budgetRow = (budget, compact = false) => `<div class="budget-row"><div class="budget-row-top"><div class="budget-category"><span class="category-dot ${categoryClass(budget.category)}"></span>${budget.category}</div><span class="budget-amount">${formatMoney(budget.spent)} / ${formatMoney(budget.limit)}</span></div><div class="progress-track"><div class="progress-bar ${budget.status}" style="width:${Math.min(budget.percent * 100, 100)}%"></div></div><div class="budget-foot"><span>${budget.status === 'over' ? `超出 ${formatMoney(budget.spent - budget.limit)}` : `剩余 ${formatMoney(Math.max(budget.limit - budget.spent, 0))}`}</span><span class="budget-status ${budget.status}">${budget.status === 'over' ? '已超支' : budget.status === 'warning' ? '接近上限' : '进行中'}</span>${compact ? `<button class="text-button" data-action="edit-budget" data-budget-id="${budget.id}">调整</button>` : ''}</div></div>`;

const transactionItem = (transaction, detailed = false) => {
  const account = accountById(transaction.accountId);
  const label = transaction.merchant || transaction.note || transaction.category;
  const directionIcon = transaction.type === 'income' ? 'income' : categoryIcon(transaction.category);
  return `<div class="${detailed ? 'ledger-row' : 'transaction-item'}" data-search="${escapeHtml(`${label} ${transaction.category} ${account?.name ?? ''}`.toLowerCase())}"><div class="transaction-icon ${transaction.type === 'income' ? 'income' : categoryClass(transaction.category)}">${icon(directionIcon, detailed ? 18 : 15)}</div><div class="transaction-copy"><div class="transaction-name">${escapeHtml(label)}</div><div class="transaction-meta">${escapeHtml(transaction.category)} · ${escapeHtml(account?.name ?? '未指定')}${detailed ? ` · ${formatLongDate(transaction.date)}` : ''}</div></div><div class="transaction-amount ${transaction.type === 'income' ? 'amount-income' : 'amount-expense'}">${transaction.type === 'income' ? '+' : '-'}${formatMoney(transaction.amount)}</div>${detailed ? `<div class="ledger-actions"><button class="small-icon-button" data-action="edit-transaction" data-transaction-id="${transaction.id}" aria-label="编辑">${icon('edit', 14)}</button><button class="small-icon-button danger" data-action="delete-transaction" data-transaction-id="${transaction.id}" aria-label="删除">${icon('trash', 14)}</button></div>` : `<button class="transaction-menu" data-action="edit-transaction" data-transaction-id="${transaction.id}" aria-label="编辑">${icon('more', 15)}</button>`}</div>`;
};

const renderRecentTransactions = (metrics) => {
  const items = [...metrics.monthTransactions].sort((a, b) => `${b.date}${b.createdAt}`.localeCompare(`${a.date}${a.createdAt}`)).slice(0, 5);
  if (!items.length) return '<div class="empty-state">没有找到本月记录。<p>从右上角开始记一笔吧。</p></div>';
  const groups = Object.entries(items.reduce((acc, tx) => { (acc[tx.date] ??= []).push(tx); return acc; }, {}));
  return `<div class="transaction-list">${groups.map(([date, txs]) => `<div class="day-group"><p class="day-label">${formatDate(date)} · ${date === stateTodayKey() ? '今天' : ''}</p>${txs.map((tx) => transactionItem(tx)).join('')}</div>`).join('')}</div>`;
};

const stateTodayKey = () => `${currentState.settings.currentMonth}-01`;

const renderDashboard = () => {
  const metrics = deriveMetrics(currentState, currentState.settings.currentMonth);
  const goalPercent = Math.round(metrics.goalProgress * 100);
  const leadingInsight = generateInsights(metrics, currentState)[0];
  const totalBudget = metrics.budgetUsage.reduce((sum, item) => sum + item.limit, 0);
  const totalBudgetSpent = metrics.budgetUsage.reduce((sum, item) => sum + item.spent, 0);
  const budgetPercent = totalBudget ? Math.round((totalBudgetSpent / totalBudget) * 100) : 0;
  const delta = netWorthDelta(metrics, currentState);
  return `<div class="view-head"><div><h2>早上好，${escapeHtml(currentState.settings.profileName)} 👋</h2><p>${formatLongDate(stateTodayKey())} · 这是你的财务节奏</p></div><div class="view-actions"><button class="ghost-button" data-view="insights">查看月报 ${icon('arrow', 14)}</button><button class="primary-button" data-action="open-quick-add">${icon('plus', 15)}记一笔</button></div></div>
    <div class="hero"><section class="hero-card"><div class="hero-kicker">${formatMonth(metrics.monthKey)} · 现金流状态</div><h2 class="hero-heading">这个月，你留住了 <span>${formatMoney(metrics.savings)}</span></h2><p class="hero-copy">储蓄率 ${Math.round(metrics.savingsRate * 100)}%，净资产较上月${delta >= 0 ? '增加' : '减少'} ${formatMoney(Math.abs(delta))}。保持现在的节奏，应急金会越来越有底气。</p><span class="hero-arrow">${icon('arrow', 20)}</span></section><section class="agent-card"><div class="agent-label">${icon('brain', 16)} 随想记助手</div><h3>${escapeHtml(leadingInsight.title)}</h3><p>${escapeHtml(leadingInsight.body)}</p><button class="agent-link" data-view="insights">查看完整洞察 ${icon('arrow', 13)}</button></section></div>
    <div class="stats-grid">${statCard('本月收入', formatMoney(metrics.income), '较上月稳定', 'income', 'mint', '+6.2%')} ${statCard('本月支出', formatMoney(metrics.expense), `预算使用 ${budgetPercent}%`, 'expense', 'peach', '-3.4%')} ${statCard('本月储蓄率', `${Math.round(metrics.savingsRate * 100)}%`, '健康区间 > 30%', 'trend', 'purple', '+4.8%')} ${statCard('当前净资产', formatMoney(metrics.netWorth), '较上月变动', 'wallet', 'blue', `${delta >= 0 ? '+' : '-'}${formatMoney(Math.abs(delta))}`)}</div>
    <div class="dashboard-grid"><div class="stack"><section class="panel"><div class="panel-head"><div><h3 class="panel-title">净资产趋势</h3><p class="panel-note">过去 5 个月的变化</p></div><button class="panel-action" data-view="wealth">详情 ${icon('arrow', 12)}</button></div><div class="chart-wrap">${renderLineChart(currentState)}</div><div class="chart-legend"><span class="legend-item"><i class="legend-dot"></i>净资产</span><span class="legend-item"><i class="legend-dot purple"></i>本月目标 ${formatMoney(metrics.goal?.target ?? 0)}</span></div></section><section class="panel"><div class="panel-head"><div><h3 class="panel-title">最近账目</h3><p class="panel-note">${formatMonth(metrics.monthKey)} · ${metrics.monthTransactions.length} 笔记录</p></div><button class="panel-action" data-view="ledger">查看全部 ${icon('arrow', 12)}</button></div>${renderRecentTransactions(metrics)}</section></div><div class="stack"><section class="quick-add-panel"><div class="panel-head"><div><h3 class="panel-title">一句话记账</h3><p class="panel-note">说说刚刚发生了什么，Agent 帮你整理</p></div></div><div class="quick-input">${icon('spark', 16)}<span>例如：今天中午外卖 32 元，支付宝</span><button data-action="open-natural">${icon('brain', 12)}开始</button></div></section><section class="panel"><div class="panel-head"><div><h3 class="panel-title">本月预算</h3><p class="panel-note">${metrics.budgetUsage.filter((item) => item.status !== 'healthy').length ? '有 1 项需要留意' : '全部在计划内'}</p></div><button class="panel-action" data-view="budgets">管理 ${icon('arrow', 12)}</button></div><div class="budget-list">${metrics.budgetUsage.slice(0, 4).map((budget) => budgetRow(budget)).join('')}</div></section><section class="panel"><div class="panel-head"><div><h3 class="panel-title">应急金目标</h3><p class="panel-note">目标 ${formatMoney(metrics.goal?.target ?? 0)}</p></div><button class="panel-action" data-action="edit-goal">调整</button></div><div class="goal-top"><div class="goal-name">${escapeHtml(metrics.goal?.name ?? '应急金')}</div><div class="goal-percent">${goalPercent}%</div></div><div class="progress-track"><div class="progress-bar" style="width:${goalPercent}%"></div></div><div class="goal-footer"><span>已完成 ${formatMoney(metrics.netWorth)}</span><span>${metrics.remainingMonths ? `预计还需 ${metrics.remainingMonths} 个月` : '已达成'}</span></div></section></div></div>`;
};

const getFilteredTransactions = () => {
  const query = ledgerFilter.query.trim().toLowerCase();
  return [...currentState.transactions].filter((transaction) => !transaction.deletedAt).filter((transaction) => {
    const account = accountById(transaction.accountId);
    const matchesQuery = !query || `${transaction.note} ${transaction.merchant ?? ''} ${transaction.category} ${account?.name ?? ''}`.toLowerCase().includes(query);
    const matchesCategory = ledgerFilter.category === 'all' || transaction.category === ledgerFilter.category;
    const matchesType = ledgerFilter.type === 'all' || transaction.type === ledgerFilter.type;
    return matchesQuery && matchesCategory && matchesType;
  }).sort((a, b) => `${b.date}${b.createdAt}`.localeCompare(`${a.date}${a.createdAt}`));
};

const renderLedgerList = () => {
  const transactions = getFilteredTransactions();
  if (!transactions.length) return '<div class="empty-state">没有符合条件的账目。<p>换个筛选条件，或者记一笔新的。</p></div>';
  const groups = Object.entries(transactions.reduce((acc, tx) => { (acc[tx.date] ??= []).push(tx); return acc; }, {}));
  return groups.map(([date, txs]) => `<div class="ledger-date">${formatLongDate(date)}<small>${txs.length} 笔</small></div>${txs.map((tx) => transactionItem(tx, true)).join('')}`).join('');
};

const renderLedger = () => `<div class="view-head"><div><h2>账本</h2><p>每一笔都值得被看见，当前共有 ${currentState.transactions.filter((item) => !item.deletedAt).length} 笔记录。</p></div><div class="view-actions"><button class="primary-button" data-action="open-manual">${icon('plus', 15)}记一笔</button></div></div><div class="ledger-toolbar"><div class="search-field">${icon('search', 15)}<input id="ledger-search" value="${escapeHtml(ledgerFilter.query)}" placeholder="搜索商户、备注或分类" /></div><select class="select-field" id="ledger-category"><option value="all">所有分类</option>${currentState.categories.map((category) => `<option value="${category.name}" ${ledgerFilter.category === category.name ? 'selected' : ''}>${category.name}</option>`).join('')}</select><button class="filter-chip ${ledgerFilter.type === 'all' ? 'active' : ''}" data-action="ledger-type" data-type="all">全部</button><button class="filter-chip ${ledgerFilter.type === 'expense' ? 'active' : ''}" data-action="ledger-type" data-type="expense">支出</button><button class="filter-chip ${ledgerFilter.type === 'income' ? 'active' : ''}" data-action="ledger-type" data-type="income">收入</button></div><section class="panel ledger-panel" id="ledger-transactions">${renderLedgerList()}</section>`;

const renderWealth = () => {
  const metrics = deriveMetrics(currentState, currentState.settings.currentMonth);
  const goalPercent = Math.round(metrics.goalProgress * 100);
  const delta = netWorthDelta(metrics, currentState);
  return `<div class="view-head"><div><h2>财富</h2><p>资产、负债和目标，都放在同一个清晰的画面里。</p></div><div class="view-actions"><button class="ghost-button" data-action="export-json">${icon('download', 14)}导出快照</button><button class="primary-button" data-action="edit-goal">${icon('target', 14)}调整目标</button></div></div><div class="wealth-layout"><div class="stack"><section class="networth-card"><div class="eyebrow">当前净资产</div><h2>${formatMoney(metrics.netWorth)}</h2><div class="networth-caption">较上月${delta >= 0 ? '增加' : '减少'} ${formatMoney(Math.abs(delta))} · 资产负债表已更新</div><div class="networth-breakdown"><div class="breakdown-item"><span>总资产</span><strong class="positive">${formatMoney(metrics.assets)}</strong></div><div class="breakdown-item"><span>总负债</span><strong class="negative">${formatMoney(metrics.liabilities)}</strong></div><div class="breakdown-item"><span>本月结余</span><strong class="positive">+${formatMoney(metrics.savings)}</strong></div></div></section><section class="panel trend-panel"><div class="panel-head"><div><h3 class="panel-title">净资产趋势</h3><p class="panel-note">每月自动保存一条快照</p></div><span class="eyebrow">${currentState.netWorthSnapshots.length} 个月</span></div><div class="chart-wrap">${renderLineChart(currentState)}</div></section><section class="panel"><div class="panel-head"><div><h3 class="panel-title">账户余额</h3><p class="panel-note">${currentState.accounts.length} 个账户</p></div><button class="panel-action" data-action="open-manual">记一笔 ${icon('arrow', 12)}</button></div><div class="account-grid">${metrics.accountBalances.map((account) => `<article class="account-card ${account.type === 'liability' ? 'liability' : ''}"><div class="account-top"><div class="account-icon" style="color:${account.color};background:${account.color}1c">${icon(account.icon, 15)}</div><span class="account-name">${escapeHtml(account.name)}</span></div><div class="account-balance">${formatMoney(account.balance)}</div><div class="account-type">${account.type === 'liability' ? '负债账户' : '资产账户'}</div></article>`).join('')}</div></section></div><div class="stack"><section class="goal-card"><div class="goal-top"><div><div class="goal-name">${escapeHtml(metrics.goal?.name ?? '应急金')}</div><div class="goal-target">目标 ${formatMoney(metrics.goal?.target ?? 0)}</div></div><div class="goal-percent">${goalPercent}%</div></div><div class="progress-track"><div class="progress-bar" style="width:${goalPercent}%"></div></div><div class="goal-footer"><span>已完成 ${formatMoney(metrics.netWorth)}</span><span>${metrics.remainingMonths ? `预计 ${metrics.remainingMonths} 个月` : '目标已达成'}</span></div></section><section class="panel"><div class="panel-head"><div><h3 class="panel-title">财富健康度</h3><p class="panel-note">根据当前收支和负债情况</p></div><span class="stat-icon mint">${icon('check', 15)}</span></div><div class="insight-card good"><div class="insight-bullet">${icon('trend', 15)}</div><div class="insight-copy"><h3>现金流状态良好</h3><p>本月结余占收入的 ${Math.round(metrics.savingsRate * 100)}%，且负债只占总资产的 ${Math.round((metrics.liabilities / metrics.assets) * 100)}%。</p><span class="insight-tag">稳步积累</span></div></div></section><section class="panel"><div class="panel-head"><div><h3 class="panel-title">资产构成</h3><p class="panel-note">按当前账户余额</p></div></div><div class="category-analysis">${renderDonut(metrics)}<div class="analysis-legend">${metrics.accountBalances.filter((account) => account.type === 'asset').map((account) => `<div class="analysis-item"><span class="analysis-label"><i class="category-dot" style="background:${account.color}"></i>${escapeHtml(account.name)}</span><strong class="analysis-value">${formatMoney(account.balance)}</strong></div>`).join('')}</div></div></section></div></div>`;
};

const renderBudgets = () => {
  const metrics = deriveMetrics(currentState, currentState.settings.currentMonth);
  const totalLimit = metrics.budgetUsage.reduce((sum, item) => sum + item.limit, 0);
  const totalSpent = metrics.budgetUsage.reduce((sum, item) => sum + item.spent, 0);
  const overall = totalLimit ? totalSpent / totalLimit : 0;
  return `<div class="view-head"><div><h2>预算</h2><p>给每一类支出一个边界，让计划服务于生活。</p></div><div class="view-actions"><button class="primary-button" data-action="open-budget">${icon('plus', 15)}新增预算</button></div></div><div class="stats-grid">${statCard('本月预算', formatMoney(totalLimit), '5 个分类预算', 'target', 'mint')} ${statCard('已使用', formatMoney(totalSpent), `整体 ${Math.round(overall * 100)}%`, 'expense', overall >= .8 ? 'peach' : 'purple')} ${statCard('可用余额', formatMoney(Math.max(totalLimit - totalSpent, 0)), '剩余预算总额', 'wallet', 'blue')} ${statCard('预警项目', `${metrics.budgetUsage.filter((item) => item.status !== 'healthy').length} 项`, '达到 80% 会提醒', 'alert', 'peach')}</div><section class="panel"><div class="panel-head"><div><h3 class="panel-title">${formatMonth(currentState.settings.currentMonth)} 分类预算</h3><p class="panel-note">预算到达 80% 或 100% 时，会在这里标记</p></div><button class="panel-action" data-action="restore-demo">恢复示例 ${icon('refresh', 12)}</button></div><div class="budget-list">${metrics.budgetUsage.map((budget) => budgetRow(budget, true)).join('')}</div></section>`;
};

const renderInsights = () => {
  const metrics = deriveMetrics(currentState, currentState.settings.currentMonth);
  const insights = generateInsights(metrics, currentState);
  const totals = categoryTotals(currentState, metrics.monthKey);
  return `<div class="view-head"><div><h2>洞察</h2><p>让助手帮你把“发生了什么”翻译成“接下来做什么”。</p></div><div class="view-actions"><button class="ghost-button" data-action="export-json">${icon('download', 14)}导出数据</button><button class="primary-button" data-action="generate-report">${icon('spark', 14)}生成新月报</button></div></div><div class="insights-layout"><div class="stack"><section class="report-card"><div class="report-header"><div class="report-label">${icon('brain', 16)} 随想记月度报告</div><span class="report-date">${formatMonth(metrics.monthKey)}</span></div><h2>你的钱正在变得更有方向感。</h2><p>本月收入 ${formatMoney(metrics.income)}，支出 ${formatMoney(metrics.expense)}，最终留下 ${formatMoney(metrics.savings)}。整体储蓄率位于健康区间，住房是本月最值得留意的一项支出。</p><div class="report-highlights"><div class="highlight-box"><span>储蓄率</span><strong>${Math.round(metrics.savingsRate * 100)}%</strong></div><div class="highlight-box"><span>净资产</span><strong>${formatMoney(metrics.netWorth)}</strong></div><div class="highlight-box"><span>目标进度</span><strong>${Math.round(metrics.goalProgress * 100)}%</strong></div></div></section><section class="panel"><div class="panel-head"><div><h3 class="panel-title">支出分布</h3><p class="panel-note">${formatMonth(metrics.monthKey)} · 按分类统计</p></div></div><div class="category-analysis">${renderDonut(metrics)}<div class="analysis-legend">${totals.slice(0, 5).map(([category, amount]) => `<div class="analysis-item"><span class="analysis-label"><i class="category-dot ${categoryClass(category)}"></i>${category}</span><strong class="analysis-value">${formatMoney(amount)}</strong></div>`).join('')}</div></div></section></div><div class="stack"><section class="panel"><div class="panel-head"><div><h3 class="panel-title">助手观察</h3><p class="panel-note">基于当前本地数据生成</p></div><span class="stat-icon purple">${icon('spark', 15)}</span></div><div class="insight-list">${insights.map((insight) => `<article class="insight-card ${insight.severity}"><div class="insight-bullet">${icon(insight.icon, 15)}</div><div class="insight-copy"><h3>${escapeHtml(insight.title)}</h3><p>${escapeHtml(insight.body)}</p><span class="insight-tag">${escapeHtml(insight.tag)}</span></div></article>`).join('')}</div></section></div></div>`;
};

const formatMonth = (monthKey) => { const [year, month] = monthKey.split('-'); return `${year}年${Number(month)}月`; };

const renderView = () => {
  const content = document.querySelector('#view-content');
  if (!content) return;
  document.querySelector('#view-kicker').textContent = viewMeta[activeView].kicker;
  document.querySelector('#view-title').textContent = viewMeta[activeView].title;
  content.innerHTML = activeView === 'dashboard' ? renderDashboard() : activeView === 'ledger' ? renderLedger() : activeView === 'wealth' ? renderWealth() : activeView === 'budgets' ? renderBudgets() : renderInsights();
};

const refresh = () => { currentState = loadState(); renderView(); document.querySelector('.nav-list')?.replaceWith(new DOMParser().parseFromString(`<nav class="nav-list" aria-label="主要导航">${navItem('dashboard', '总览', 'grid')}${navItem('ledger', '账本', 'receipt')}${navItem('wealth', '财富', 'wallet')}${navItem('budgets', '预算', 'target', currentState.budgets.length)}${navItem('insights', '洞察', 'chart')}</nav>`, 'text/html').body.firstChild); };

const showToast = (message, tone = '') => { const region = document.querySelector('#toast-region'); if (!region) return; clearTimeout(toastTimer); region.innerHTML = `<div class="toast ${tone}">${icon(tone === 'error' ? 'alert' : 'check', 15)}<span>${escapeHtml(message)}</span></div>`; toastTimer = setTimeout(() => { region.innerHTML = ''; }, 2600); };

const closeModal = () => { const root = document.querySelector('#modal-root'); if (root) { root.innerHTML = ''; root.dataset.draft = ''; root.dataset.editingId = ''; } };

const accountOptions = (selected = 'alipay') => currentState.accounts.map((account) => `<option value="${account.id}" ${account.id === selected ? 'selected' : ''}>${escapeHtml(account.name)}${account.type === 'liability' ? ' · 信用' : ''}</option>`).join('');
const categoryOptions = (selected = '餐饮') => currentState.categories.map((category) => `<option value="${category.name}" ${category.name === selected ? 'selected' : ''}>${escapeHtml(category.name)}</option>`).join('');

const renderNaturalModal = (draft = null) => `<div class="modal-backdrop" data-action="close-modal"><section class="modal" role="dialog" aria-modal="true" aria-labelledby="natural-title"><div class="modal-head"><div><h2 id="natural-title">一句话记账</h2><p>把刚刚发生的事情告诉我，先由 Agent 整理成草稿。</p></div><button class="modal-close" data-action="close-modal" aria-label="关闭">${icon('close', 16)}</button></div><div class="composer-tabs"><button class="composer-tab active" data-action="open-natural">智能记账</button><button class="composer-tab" data-action="open-manual">手动填写</button></div><form data-form="natural"><div class="field full"><label for="nl-input">刚刚发生了什么？</label><textarea id="nl-input" name="text" placeholder="例如：今天中午和同事吃饭花了 128，支付宝">${escapeHtml(draft?.note ?? '')}</textarea><p class="helper-copy">支持金额、分类、支付账户和“昨天/今天”等时间描述。</p></div>${draft ? `<div class="draft-preview"><div class="draft-label">${icon('check', 13)}已整理成待确认草稿 <span class="confidence"><i class="confidence-dot"></i>置信度 ${Math.round(draft.confidence * 100)}%</span></div><div class="draft-main"><div class="draft-amount ${draft.type === 'income' ? 'amount-income' : ''}">${draft.type === 'income' ? '+' : '-'}${formatMoney(draft.amount || 0)}</div><div class="draft-detail"><span><strong>${escapeHtml(draft.category)}</strong> · ${escapeHtml(accountById(draft.accountId)?.name ?? '支付宝')}</span><span>${formatLongDate(draft.date)} · ${draft.type === 'income' ? '收入' : '支出'}</span></div></div></div>` : ''}<div class="modal-actions"><button type="button" class="ghost-button" data-action="close-modal">取消</button>${draft ? '<button type="button" class="secondary-button" data-action="confirm-draft">确认入账</button>' : '<button type="submit" class="primary-button">生成草稿 ' + icon('arrow', 13) + '</button>'}</div></form></section></div>`;

const renderManualModal = (transaction = null) => `<div class="modal-backdrop" data-action="close-modal"><section class="modal" role="dialog" aria-modal="true" aria-labelledby="manual-title"><div class="modal-head"><div><h2 id="manual-title">${transaction ? '编辑账目' : '记一笔'}</h2><p>${transaction ? '修正后，预算和财富看板会同步更新。' : '两步完成一笔日常记录。'}</p></div><button class="modal-close" data-action="close-modal" aria-label="关闭">${icon('close', 16)}</button></div><form data-form="transaction"><div class="field full"><label>账目类型</label><div class="direction-toggle"><button type="button" class="direction-option ${transaction?.type !== 'income' ? 'active expense' : ''}" data-action="set-direction" data-direction="expense">支出</button><button type="button" class="direction-option ${transaction?.type === 'income' ? 'active income' : ''}" data-action="set-direction" data-direction="income">收入</button></div><input type="hidden" name="type" value="${transaction?.type ?? 'expense'}" /></div><div class="form-grid"><div class="field"><label for="transaction-amount">金额</label><input id="transaction-amount" name="amount" inputmode="decimal" type="number" min="0.01" step="0.01" required value="${transaction?.amount ?? ''}" placeholder="0.00" /></div><div class="field"><label for="transaction-date">日期</label><input id="transaction-date" name="date" type="date" required value="${transaction?.date ?? stateTodayKey()}" /></div><div class="field"><label for="transaction-category">分类</label><select id="transaction-category" name="category">${categoryOptions(transaction?.category ?? '餐饮')}</select></div><div class="field"><label for="transaction-account">账户</label><select id="transaction-account" name="accountId">${accountOptions(transaction?.accountId ?? 'alipay')}</select></div><div class="field full"><label for="transaction-note">备注</label><input id="transaction-note" name="note" value="${escapeHtml(transaction?.note ?? '')}" placeholder="例如：午餐、通勤或房租" /></div></div><div class="modal-actions"><button type="button" class="ghost-button" data-action="close-modal">取消</button><button type="submit" class="primary-button">${transaction ? '保存修改' : '确认入账'} ${icon('check', 13)}</button></div></form></section></div>`;

const renderBudgetModal = (budget = null) => `<div class="modal-backdrop" data-action="close-modal"><section class="modal" role="dialog" aria-modal="true" aria-labelledby="budget-title"><div class="modal-head"><div><h2 id="budget-title">${budget ? '调整预算' : '新增预算'}</h2><p>先给这个月的支出设一个轻量边界。</p></div><button class="modal-close" data-action="close-modal" aria-label="关闭">${icon('close', 16)}</button></div><form data-form="budget"><div class="form-grid"><div class="field"><label for="budget-category">分类</label><select id="budget-category" name="category">${categoryOptions(budget?.category ?? '餐饮')}</select></div><div class="field"><label for="budget-limit">月度上限</label><input id="budget-limit" name="limit" type="number" min="1" step="1" required value="${budget?.limit ?? ''}" placeholder="例如：1000" /></div></div><div class="modal-actions"><button type="button" class="ghost-button" data-action="close-modal">取消</button><button type="submit" class="primary-button">保存预算 ${icon('check', 13)}</button></div></form></section></div>`;

const renderGoalModal = () => { const goal = currentState.goals[0]; return `<div class="modal-backdrop" data-action="close-modal"><section class="modal" role="dialog" aria-modal="true" aria-labelledby="goal-title"><div class="modal-head"><div><h2 id="goal-title">调整应急金目标</h2><p>目标越具体，结余就越有方向。</p></div><button class="modal-close" data-action="close-modal" aria-label="关闭">${icon('close', 16)}</button></div><form data-form="goal"><div class="field"><label for="goal-target">目标金额</label><input id="goal-target" name="target" type="number" min="1" step="100" required value="${goal?.target ?? 30000}" /></div><div class="modal-actions"><button type="button" class="ghost-button" data-action="close-modal">取消</button><button type="submit" class="primary-button">保存目标 ${icon('check', 13)}</button></div></form></section></div>`; };

const openModal = (html) => { const root = document.querySelector('#modal-root'); root.innerHTML = html; root.querySelector('textarea, input, select')?.focus(); };

const handleClick = (event) => {
  const target = event.target.closest('[data-view], [data-action]');
  if (!target) return;
  const view = target.dataset.view;
  if (view) { event.preventDefault(); activeView = view; renderView(); document.querySelectorAll('.nav-item[data-view]').forEach((item) => item.classList.toggle('active', item.dataset.view === view)); return; }
  const action = target.dataset.action;
  if (action === 'close-modal') { if (target.classList.contains('modal-backdrop') && event.target !== target) return; closeModal(); }
  if (action === 'open-quick-add' || action === 'open-natural') openModal(renderNaturalModal());
  if (action === 'open-manual') openModal(renderManualModal());
  if (action === 'parse-draft') {}
  if (action === 'confirm-draft') { const draft = JSON.parse(document.querySelector('#modal-root').dataset.draft || '{}'); if (!draft.amount) return showToast('草稿里还没有识别到金额', 'error'); currentState = addTransaction(currentState, draft); saveState(currentState); closeModal(); renderView(); showToast('已确认入账，数据同步更新'); }
  if (action === 'edit-transaction') { const transaction = currentState.transactions.find((item) => item.id === target.dataset.transactionId); if (transaction) { const root = document.querySelector('#modal-root'); root.dataset.editingId = transaction.id; openModal(renderManualModal(transaction)); } }
  if (action === 'delete-transaction') { const transaction = currentState.transactions.find((item) => item.id === target.dataset.transactionId); if (transaction && window.confirm(`确定删除“${transaction.note || transaction.category}”这笔账目吗？`)) { currentState = { ...currentState, transactions: currentState.transactions.map((item) => item.id === transaction.id ? { ...item, deletedAt: new Date().toISOString() } : item), updatedAt: new Date().toISOString() }; saveState(currentState); renderView(); showToast('账目已移入删除记录'); } }
  if (action === 'set-direction') { const form = target.closest('form'); form.querySelector('input[name="type"]').value = target.dataset.direction; form.querySelectorAll('.direction-option').forEach((item) => item.classList.remove('active', 'expense', 'income')); target.classList.add('active', target.dataset.direction); }
  if (action === 'ledger-type') { ledgerFilter.type = target.dataset.type; renderView(); }
  if (action === 'edit-budget') { const budget = currentState.budgets.find((item) => item.id === target.dataset.budgetId); if (budget) openModal(renderBudgetModal(budget)); }
  if (action === 'open-budget') openModal(renderBudgetModal());
  if (action === 'edit-goal') openModal(renderGoalModal());
  if (action === 'generate-report') showToast('月报已根据最新账目重新生成');
  if (action === 'restore-demo') { currentState = createSeedState(); ledgerFilter = { query: '', category: 'all', type: 'all' }; saveState(currentState); activeView = 'dashboard'; renderView(); document.querySelectorAll('.nav-item[data-view]').forEach((item) => item.classList.toggle('active', item.dataset.view === activeView)); showToast('演示数据已恢复'); }
  if (action === 'export-json') { const blob = new Blob([JSON.stringify(currentState, null, 2)], { type: 'application/json' }); const url = URL.createObjectURL(blob); const anchor = document.createElement('a'); anchor.href = url; anchor.download = `wealthmate-${currentState.settings.currentMonth}.json`; anchor.click(); URL.revokeObjectURL(url); showToast('数据文件已导出'); }
};

const handleSubmit = (event) => {
  const form = event.target;
  if (!form.matches('form[data-form]')) return;
  event.preventDefault();
  const data = Object.fromEntries(new FormData(form));
  if (form.dataset.form === 'natural') { const draft = parseNaturalLanguage(data.text, new Date(`${stateTodayKey()}T10:00:00`)); const root = document.querySelector('#modal-root'); root.dataset.draft = JSON.stringify(draft); root.innerHTML = renderNaturalModal(draft); return; }
  if (form.dataset.form === 'transaction') { const transaction = { amount: Number(data.amount), type: data.type, category: data.category, accountId: data.accountId, date: data.date, note: data.note || data.category }; const root = document.querySelector('#modal-root'); const editingId = root.dataset.editingId; if (editingId) currentState = { ...currentState, transactions: currentState.transactions.map((item) => item.id === editingId ? { ...item, ...transaction } : item), updatedAt: new Date().toISOString() }; else currentState = addTransaction(currentState, transaction); saveState(currentState); closeModal(); renderView(); showToast(editingId ? '账目已更新' : '已确认入账，数据同步更新'); }
  if (form.dataset.form === 'budget') { const existingId = currentState.budgets.find((item) => item.category === data.category)?.id; const budget = { id: existingId ?? `budget-${Date.now()}`, month: currentState.settings.currentMonth, category: data.category, limit: Number(data.limit) }; currentState = { ...currentState, budgets: [...currentState.budgets.filter((item) => item.id !== existingId), budget], updatedAt: new Date().toISOString() }; saveState(currentState); closeModal(); renderView(); showToast('预算已保存'); }
  if (form.dataset.form === 'goal') { currentState = { ...currentState, goals: [{ ...currentState.goals[0], target: Number(data.target) }], updatedAt: new Date().toISOString() }; saveState(currentState); closeModal(); renderView(); showToast('应急金目标已更新'); }
};

const handleInput = (event) => { if (event.target.id === 'ledger-search') { ledgerFilter.query = event.target.value; const list = document.querySelector('#ledger-transactions'); if (list) list.innerHTML = renderLedgerList(); } if (event.target.id === 'ledger-category') { ledgerFilter.category = event.target.value; const list = document.querySelector('#ledger-transactions'); if (list) list.innerHTML = renderLedgerList(); } };

if (typeof document !== 'undefined') {
  document.addEventListener('DOMContentLoaded', () => { document.querySelector('#app').innerHTML = appShell(); document.body.addEventListener('click', handleClick); document.body.addEventListener('submit', handleSubmit); document.body.addEventListener('input', handleInput); document.body.addEventListener('change', handleInput); renderView(); });
}

if (typeof window !== 'undefined' && 'serviceWorker' in navigator) {
  window.addEventListener('load', () => navigator.serviceWorker.register('./service-worker.js').catch(() => {}));
}
