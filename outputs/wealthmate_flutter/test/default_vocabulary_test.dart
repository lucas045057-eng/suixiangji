import 'package:flutter_test/flutter_test.dart';
import 'package:wealthmate_flutter/domain/demo_state.dart';
import 'package:wealthmate_flutter/domain/finance_rules.dart';
import 'package:wealthmate_flutter/domain/models.dart';

void main() {
  // Mirrors backend app/auth/registration.py DEFAULT_CATEGORIES. Keep the two
  // lists in step: the offline demo must offer the same vocabulary as a new
  // server ledger, otherwise the same words resolve differently per mode.
  const backendDefaults = <String>{
    '餐饮',
    '交通',
    '住房',
    '购物',
    '娱乐',
    '健康',
    '话费',
    '水电',
    '药品',
    '人情往来',
    '工资',
    '稿费',
  };

  test('demo ledger carries every backend default category', () {
    final names = DemoData.create().categories.map((item) => item.name).toSet();
    expect(names.containsAll(backendDefaults), isTrue,
        reason: 'missing: ${backendDefaults.difference(names)}');
  });

  test('income categories keep their kind', () {
    final state = DemoData.create();
    for (final name in const ['工资', '稿费']) {
      final category = state.categories.firstWhere((item) => item.name == name);
      expect(category.type, TransactionType.income, reason: name);
    }
  });

  test('vocabulary v2 categories are expense categories', () {
    final state = DemoData.create();
    for (final name in const ['话费', '水电', '药品', '人情往来']) {
      final category = state.categories.firstWhere((item) => item.name == name);
      expect(category.type, TransactionType.expense, reason: name);
    }
  });

  test('local rules pick the specific new category over the generic ones', () {
    final state = DemoData.create();
    AgentDraft draft(String text) => FinanceRules.completeNaturalLanguageDraft(
          text,
          now: DateTime(2026, 10, 29),
          state: state,
        );

    expect(draft('充话费50元支付宝').categoryId, 'mobile');
    expect(draft('水电100元微信').categoryId, 'utilities');
    expect(draft('买药36.8元').categoryId, 'medical');
    expect(draft('随礼200元').categoryId, 'social');
  });

  test('零食 is not a demo category any more (dropped from the vocabulary)', () {
    final state = DemoData.create();
    expect(state.categories.any((item) => item.id == 'snacks'), isFalse);
    expect(state.categories.any((item) => item.name == '零食'), isFalse);
    // Local rules must not invent a dangling id for snack words either.
    final draft = FinanceRules.completeNaturalLanguageDraft(
      '买零食20元',
      now: DateTime(2026, 10, 29),
      state: state,
    );
    expect(draft.categoryId, isNot('snacks'));
  });
}
