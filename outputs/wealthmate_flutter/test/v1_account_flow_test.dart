import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wealthmate_flutter/data/api_client.dart';
import 'package:wealthmate_flutter/domain/models.dart';
import 'package:wealthmate_flutter/features/auth/data/auth_remote_data_source.dart';
import 'package:wealthmate_flutter/features/auth/data/auth_repository.dart';
import 'package:wealthmate_flutter/features/auth/state/auth_store.dart';
import 'package:wealthmate_flutter/ui/login_page.dart';
import 'package:wealthmate_flutter/ui/profile_settings_page.dart';
import 'package:wealthmate_flutter/ui/exchange_rates_page.dart';
import 'package:wealthmate_flutter/ui/register_page.dart';
import 'package:wealthmate_flutter/main.dart';
import 'package:wealthmate_flutter/ui/app_shell.dart';
import 'offline_owner_recovery_test.dart' as fixtures;
import 'v1_session_partition_test.dart' show Harness;

Map<String, Object?> profile(String id) => {
      'id': id,
      'username': id,
      'display_name': 'Nickname',
      'quick_memories': []
    };

AuthStore authFor(ApiClient api) => AuthStore(
      repository: AuthRepository(
        remote: AuthRemoteDataSource(api: api),
      ),
    );

void main() {
  for (final scenario in [
    'optional nickname',
    'nickname maximum',
    'password maximum',
    'maximum lengths accepted'
  ]) {
    testWidgets('registration validation: $scenario', (tester) async {
      final requests = <http.Request>[];
      var entered = false;
      final api = ApiClient(
          baseUrl: 'http://v1.test',
          tokenStore: fixtures.MemoryTokenStore(),
          client: MockClient((request) async {
            requests.add(request);
            return http.Response(
                jsonEncode(request.url.path == '/auth/register'
                    ? {'access_token': 'registered'}
                    : profile('registered')),
                request.url.path == '/auth/register' ? 201 : 200);
          }));
      await tester.pumpWidget(MaterialApp(
          home: RegisterPage(
              auth: authFor(api), onLoggedIn: () => entered = true)));
      await tester.enterText(
          find.widgetWithText(TextFormField, '用户名'), 'alice');
      final password = scenario == 'password maximum'
          ? 'a' * 257
          : scenario == 'maximum lengths accepted'
              ? 'a' * 256
              : 'password123';
      await tester.enterText(
          find.widgetWithText(TextFormField, '密码'), password);
      await tester.enterText(
          find.widgetWithText(TextFormField, '确认密码'), password);
      if (scenario == 'nickname maximum') {
        await tester.enterText(
            find.widgetWithText(TextFormField, '昵称'), 'a' * 129);
      } else if (scenario == 'maximum lengths accepted') {
        await tester.enterText(
            find.widgetWithText(TextFormField, '昵称'), 'a' * 128);
      } else if (scenario == 'password maximum') {
        await tester.enterText(
            find.widgetWithText(TextFormField, '昵称'), 'Alice');
      }
      await tester.enterText(
          find.widgetWithText(TextFormField, '邀请码'), 'invite');
      await tester.ensureVisible(find.text('注册并登录'));
      await tester.tap(find.text('注册并登录'));
      await tester.pumpAndSettle();
      if (scenario == 'optional nickname' ||
          scenario == 'maximum lengths accepted') {
        expect(entered, isTrue);
        if (scenario == 'optional nickname') {
          expect(
              jsonDecode(requests.first.body), isNot(contains('display_name')));
        } else {
          expect((jsonDecode(requests.first.body) as Map)['display_name'],
              'a' * 128);
          expect(
              (jsonDecode(requests.first.body) as Map)['password'], 'a' * 256);
        }
      } else {
        expect(requests, isEmpty);
        expect(entered, isFalse);
      }
    });
  }

  testWidgets(
      'application registration initializes verified owner then deletion returns to login',
      (tester) async {
    final requests = <String>[];
    final h = Harness(client: MockClient((request) async {
      requests.add('${request.method} ${request.url.path}');
      if (request.url.path == '/auth/register')
        return http.Response(
            '{"access_token":"new-token","token_type":"bearer","user_id":"unverified-response-id","username":"alice"}',
            201);
      if (request.method == 'DELETE')
        return http.Response('{"deleted":true}', 200);
      if (request.url.path == '/sync/pull')
        return http.Response(
            '{"items":[],"accounts":[],"categories":[],"budgets":[],"server_version":0}',
            200);
      return http.Response(jsonEncode(profile('verified-new-user')), 200);
    }));
    await h.repository.loadForUser('old-A');
    await h.seed();
    await h.logout();
      await tester.pumpWidget(WealthMateApp(
          store: h.store, api: h.api, auth: h.store.authStore));
    expect(find.byType(LoginPage), findsOneWidget);
    await tester.tap(find.text('注册账号'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, '用户名'), 'alice');
    await tester.enterText(
        find.widgetWithText(TextFormField, '密码'), 'password123');
    await tester.enterText(
        find.widgetWithText(TextFormField, '确认密码'), 'password123');
    await tester.enterText(find.widgetWithText(TextFormField, '邀请码'), 'invite');
    await tester.ensureVisible(find.text('注册并登录'));
    await tester.tap(find.text('注册并登录'));
    await tester.pumpAndSettle();
    expect(find.byType(RegisterPage), findsNothing);
    expect(find.byType(AppShell), findsOneWidget);
    expect(h.repository.localOwnerUserId, 'verified-new-user');
    expect(h.store.state.transactions, isEmpty);
    expect(requests.take(2), ['POST /auth/register', 'GET /auth/me']);
    await tester.tap(find.text('我的'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('账户与登录'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('永久删除账号'), 400,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('永久删除账号'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextField, '删除验证密码'), 'password123');
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认永久删除'));
    await tester.pumpAndSettle();
    expect(find.byType(LoginPage), findsOneWidget);
    expect(find.byType(ProfileSettingsPage), findsNothing);
    expect(h.api.token, isNull);
    expect((await h.repository.local.forUser('old-A').load())!.toJson(),
        fixtures.ownerAState().toJson());
  });
  test(
      'registration sends invite contract and persists token before identity verification',
      () async {
    final requests = <http.Request>[];
    final tokens = fixtures.MemoryTokenStore();
    final api = ApiClient(
        baseUrl: 'http://v1.test',
        tokenStore: tokens,
        client: MockClient((request) async {
          requests.add(request);
          if (request.url.path == '/auth/register') {
            return http.Response(
                jsonEncode({
                  'access_token': 'new-token',
                  'token_type': 'bearer',
                  'user_id': 'new-user',
                  'username': 'alice',
                  'display_name': 'Alice'
                }),
                201);
          }
          expect(request.headers['authorization'], 'Bearer new-token');
          return http.Response(jsonEncode(profile('new-user')), 200);
        }));
    await api.register(
        username: 'alice',
        password: 'Password123!',
        displayName: 'Alice',
        inviteCode: 'invite-A');
    expect(tokens.token, 'new-token');
    expect(api.lastVerifiedUserId, isNull);
    expect((await api.fetchProfile()).id, 'new-user');
    expect(tokens.lastVerifiedUserId, 'new-user');
    expect(requests.map((r) => r.url.path), ['/auth/register', '/auth/me']);
    expect(jsonDecode(requests.first.body), {
      'username': 'alice',
      'password': 'Password123!',
      'display_name': 'Alice',
      'invite_code': 'invite-A'
    });
  });

  for (final status in [400, 409, 422, 429]) {
    test(
        'registration $status retains credentials and provides safe useful error',
        () async {
      final tokens = fixtures.MemoryTokenStore()..token = 'old';
      final api = ApiClient(
          baseUrl: 'http://v1.test',
          token: 'old',
          tokenStore: tokens,
          client: MockClient((_) async =>
              http.Response('{"detail":"private database trace"}', status)));
      await expectLater(
          api.register(
              username: 'alice',
              password: 'Password123!',
              displayName: 'A',
              inviteCode: 'x'),
          throwsA(isA<ApiFailure>().having((f) => f.message, 'safe explanation',
              allOf(isNot(contains('private')), isNot('同步服务暂时不可用')))));
      expect(tokens.token, 'old');
    });
  }

  for (final success in [false, true]) {
    test(
        'delete ${success ? 'purges only A after remote success' : 'wrong password retains credentials and all data'}',
        () async {
      http.Request? deletion;
      final h = Harness(client: MockClient((request) async {
        final id = request.headers['authorization']!.split(' ').last;
        if (request.method == 'DELETE') {
          deletion = request;
          return http.Response(
              success ? '{"deleted":true}' : '{"detail":"wrong password"}',
              success ? 200 : 403);
        }
        return http.Response(jsonEncode(profile(id)), 200);
      }));
      await h.login('B');
      await h.seed();
      await h.logout();
      await h.login('A');
      await h.seed();
      final deleted = await h.store.deleteAccount('current-password');
      expect(deleted, success);
      expect(deletion!.url.path, '/auth/me');
      expect(
          jsonDecode(deletion!.body), {'current_password': 'current-password'});
      if (success) {
        expect(h.api.token, isNull);
        expect(h.tokens.token, isNull);
        expect(await h.repository.local.loadOwnerUserId(), isNull);
        expect(h.store.state.transactions, isEmpty);
        expect(h.repository.queue.pending(), isEmpty);
        await h.login('A');
        expect(h.store.state.transactions, isEmpty);
      } else {
        expect(h.api.token, 'A');
        expect(h.tokens.token, 'A');
        h.expectA();
      }
      await h.logout();
      await h.login('B');
      h.expectA();
    });
  }

  testWidgets(
      'register validates fields then verifies identity before entering app',
      (tester) async {
    var entered = false;
    final requests = <String>[];
    final verified = Completer<http.Response>();
    final api = ApiClient(
        baseUrl: 'http://v1.test',
        tokenStore: fixtures.MemoryTokenStore(),
        client: MockClient((request) async {
          requests.add(request.url.path);
          if (request.url.path == '/auth/register')
            return http.Response('{"access_token":"new-token"}', 201);
          return verified.future;
        }));
    await tester.pumpWidget(MaterialApp(
        home: LoginPage(
            auth: authFor(api), onLoggedIn: () => entered = true)));
    await tester.tap(find.text('注册账号'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('注册并登录'));
    await tester.tap(find.text('注册并登录'));
    await tester.pumpAndSettle();
    expect(requests, isEmpty);
    Future<void> field(String label, String value) =>
        tester.enterText(find.widgetWithText(TextFormField, label), value);
    await field('用户名', 'bad space');
    await field('昵称', 'Alice');
    await field('密码', 'Password123!');
    await field('确认密码', 'different');
    await field('邀请码', 'invite');
    await tester.ensureVisible(find.text('注册并登录'));
    await tester.tap(find.text('注册并登录'));
    await tester.pumpAndSettle();
    expect(requests, isEmpty);
    await field('用户名', 'alice');
    await field('确认密码', 'Password123!');
    await tester.ensureVisible(find.text('注册并登录'));
    await tester.tap(find.text('注册并登录'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(requests, ['/auth/register', '/auth/me']);
    expect(entered, isFalse);
    verified.complete(http.Response(jsonEncode(profile('new-user')), 200));
    await tester.pumpAndSettle();
    expect(entered, isTrue);
  });

  testWidgets('deletion requires password and explicit confirmation',
      (tester) async {
    var deletes = 0;
    final h = Harness(client: MockClient((request) async {
      if (request.method == 'DELETE') {
        deletes++;
        return http.Response('{"deleted":true}', 200);
      }
      return http.Response(jsonEncode(profile('A')), 200);
    }));
    await h.login('A');
    await h.seed();
    await tester
        .pumpWidget(MaterialApp(home: ProfileSettingsPage(store: h.store)));
    await tester.pumpAndSettle();
    final delete = find.text('永久删除账号');
    await tester.scrollUntilVisible(delete, 400,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(delete);
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认永久删除'));
    await tester.pumpAndSettle();
    expect(deletes, 0);
    await tester.enterText(
        find.widgetWithText(TextField, '删除验证密码'), 'password');
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认永久删除'));
    await tester.pumpAndSettle();
    expect(deletes, 1);
    expect(h.api.token, isNull);
  });

  testWidgets('online exchange rate UI exposes trusted GET only',
      (tester) async {
    final methods = <String>[];
    final h = Harness(client: MockClient((request) async {
      methods.add(request.method);
      return http.Response(
          '{"base_currency":"USD","quote_currency":"CNY","rate":7.1,"rate_date":"2026-09-08","source":"trusted"}',
          200);
    }));
    await h.api.saveToken('A');
    await h.repository.loadForUser('A');
    await h.repository.save(const FinanceState(accounts: [
      Account(id: 'usd', name: 'USD', type: AccountType.asset, currency: 'USD')
    ]));
    await h.store.load();
    await tester
        .pumpWidget(MaterialApp(home: ExchangeRatesPage(store: h.store)));
    // The manual-entry control is part of the pre-Auth baseline UI. This test
    // is concerned with the trusted online GET contract, not its visibility.
    expect(find.text('手动录入'), findsOneWidget);
    await tester.tap(find.text('获取汇率'));
    await tester.pumpAndSettle();
    expect(methods, ['GET']);
    expect(h.store.state.exchangeRates.single.rate, 7.1);
  });
}
