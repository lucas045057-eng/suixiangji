import 'dart:async';

import 'package:flutter/material.dart';

import '../state/finance_store.dart';
import 'budgets_page.dart';
import 'dashboard_page.dart';
import 'ledger_page.dart';
import 'settings_page.dart';
import 'stats_page.dart';
import 'wealth_page.dart';

class AppShell extends StatefulWidget {
  const AppShell({required this.store, super.key});

  final FinanceStore store;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int selectedIndex = 0;
  late final List<Widget?> _pageCache;

  @override
  void initState() {
    super.initState();
    _pageCache = List<Widget?>.filled(5, null);
    _pageCache[0] = _buildPage(0);
    if (!widget.store.isDemoMode) {
      unawaited(widget.store.loadProfile().then((_) => widget.store.sync()));
    }
  }

  List<Widget> get pages => List<Widget>.generate(
      5, (index) => _pageCache[index] ?? const SizedBox.shrink());

  Widget _buildPage(int index) {
    return switch (index) {
      0 => DashboardPage(store: widget.store, openBudgets: _openBudgets),
      1 => LedgerPage(store: widget.store),
      2 => StatsPage(store: widget.store),
      3 => WealthPage(store: widget.store),
      _ => SettingsPage(store: widget.store),
    };
  }

  void _selectPage(int index) {
    _pageCache[index] ??= _buildPage(index);
    setState(() => selectedIndex = index);
  }

  void _openBudgets() {
    Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => BudgetsPage(store: widget.store)));
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 900;
        return Scaffold(
          body: wide ? _buildDesktop(context) : _buildMobile(),
          bottomNavigationBar: wide ? null : _buildMobileNavigation(),
        );
      },
    );
  }

  Widget _buildMobile() => IndexedStack(index: selectedIndex, children: pages);

  Widget _buildDesktop(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 210,
          color: const Color(0xFF12201D),
          padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Text('随想记',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w800)),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(12, 4, 12, 36),
                child: Text('你的钱，有自己的节奏',
                    style: TextStyle(color: Color(0xFF9DB8AC), fontSize: 11)),
              ),
              Expanded(
                child: ListView(
                  children: [
                    _desktopNav(Icons.grid_view_rounded, '首页', 0),
                    _desktopNav(Icons.receipt_long_rounded, '账本', 1),
                    _desktopNav(Icons.bar_chart_rounded, '统计', 2),
                    _desktopNav(Icons.account_balance_wallet_rounded, '财富', 3),
                    _desktopNav(Icons.person_outline_rounded, '我的', 4),
                    const SizedBox(height: 18),
                    ListTile(
                      onTap: _openBudgets,
                      leading: const Icon(Icons.track_changes,
                          color: Color(0xFF9DB8AC)),
                      title: const Text('预算',
                          style: TextStyle(
                              color: Color(0xFFB7C8BF), fontSize: 13)),
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 12),
                    ),
                  ],
                ),
              ),
              const Divider(color: Color(0x334A665B)),
              const ListTile(
                contentPadding: EdgeInsets.symmetric(horizontal: 12),
                leading: CircleAvatar(
                    radius: 16,
                    backgroundColor: Color(0xFFF3B187),
                    child: Text('林',
                        style: TextStyle(
                            color: Color(0xFF56301E),
                            fontSize: 12,
                            fontWeight: FontWeight.w800))),
                title: Text('林默',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700)),
                subtitle: Text('本地模式',
                    style: TextStyle(color: Color(0xFF8B9C95), fontSize: 10)),
              ),
            ],
          ),
        ),
        Expanded(child: IndexedStack(index: selectedIndex, children: pages)),
        Container(
          width: 260,
          padding: const EdgeInsets.fromLTRB(0, 32, 22, 32),
          child: _DesktopDetailPanel(store: widget.store),
        ),
      ],
    );
  }

  Widget _desktopNav(IconData icon, String label, int index) {
    final active = selectedIndex == index;
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: ListTile(
        selected: active,
        onTap: () => _selectPage(index),
        leading: Icon(icon,
            color: active ? const Color(0xFF12201D) : const Color(0xFFA9BBB4),
            size: 20),
        title: Text(label,
            style: TextStyle(
                color:
                    active ? const Color(0xFF12201D) : const Color(0xFFA9BBB4),
                fontSize: 13,
                fontWeight: FontWeight.w700)),
        selectedTileColor: const Color(0xFFBDEBDC),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
      ),
    );
  }

  Widget _buildMobileNavigation() {
    return NavigationBar(
      selectedIndex: selectedIndex,
      onDestinationSelected: _selectPage,
      destinations: const [
        NavigationDestination(icon: Icon(Icons.grid_view_rounded), label: '首页'),
        NavigationDestination(
            icon: Icon(Icons.receipt_long_rounded), label: '账本'),
        NavigationDestination(icon: Icon(Icons.bar_chart_rounded), label: '统计'),
        NavigationDestination(
            icon: Icon(Icons.account_balance_wallet_rounded), label: '财富'),
        NavigationDestination(
            icon: Icon(Icons.person_outline_rounded), label: '我的'),
      ],
    );
  }
}

class _DesktopDetailPanel extends StatelessWidget {
  const _DesktopDetailPanel({required this.store});

  final FinanceStore store;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final metrics = store.metrics;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              color: const Color(0xFFF0EEFF),
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('随想记助手',
                          style: TextStyle(
                              color: Color(0xFF4C4A9C),
                              fontWeight: FontWeight.w800,
                              fontSize: 12)),
                      const SizedBox(height: 14),
                      Text(
                          metrics.budgetProgress.isEmpty
                              ? '还没有预算提醒'
                              : '先看看本月预算节奏',
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 8),
                      Text(
                          store.isDemoMode
                              ? '当前为离线演示，数据只保存在本机。'
                              : '已连接同步服务，变更会进入同步队列。',
                          style: const TextStyle(
                              color: Color(0xFF686795),
                              fontSize: 11,
                              height: 1.5)),
                    ]),
              ),
            ),
            const SizedBox(height: 14),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('本月结余',
                          style: TextStyle(
                              color: Color(0xFF6C7C74),
                              fontSize: 11,
                              fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      Text('¥${metrics.savings.toStringAsFixed(0)}',
                          style: const TextStyle(
                              fontSize: 24, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 4),
                      Text('储蓄率 ${(metrics.savingsRate * 100).round()}%',
                          style: const TextStyle(
                              color: Color(0xFF2F9F7D),
                              fontSize: 11,
                              fontWeight: FontWeight.w700)),
                    ]),
              ),
            ),
          ],
        );
      },
    );
  }
}
