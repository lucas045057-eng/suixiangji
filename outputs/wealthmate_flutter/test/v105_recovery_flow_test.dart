import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wealthmate_flutter/data/api_client.dart';
import 'package:wealthmate_flutter/features/auth/data/auth_repository.dart';
import 'package:wealthmate_flutter/features/auth/data/auth_remote_data_source.dart';
import 'package:wealthmate_flutter/features/auth/state/auth_store.dart';
import 'package:wealthmate_flutter/ui/login_page.dart';
import 'offline_owner_recovery_test.dart' show MemoryTokenStore;

void main() {
  testWidgets('forgot password uses recovery code then returns to ordinary login', (tester) async {
    final requests=<http.Request>[];
    final api=ApiClient(baseUrl:'http://recovery.test',tokenStore:MemoryTokenStore(),client:MockClient((request) async {
      requests.add(request);return http.Response(jsonEncode({'reset':true}),200);
    }));
    final auth=AuthStore(repository:AuthRepository(remote:AuthRemoteDataSource(api:api)));
    addTearDown(auth.dispose);
    await tester.pumpWidget(MaterialApp(home:LoginPage(auth:auth,onLoggedIn:(){})));
    await tester.tap(find.text('忘记密码'));await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField,'用户名'),'owner');
    await tester.enterText(find.widgetWithText(TextFormField,'已保存的恢复码'),'SAVED-RECOVERY-CODE');
    await tester.enterText(find.widgetWithText(TextFormField,'新密码'),'new-password');
    await tester.enterText(find.widgetWithText(TextFormField,'确认新密码'),'new-password');
    await tester.tap(find.text('重置密码'));await tester.pumpAndSettle();
    expect(requests.single.url.path,'/auth/recover');
    expect(requests.single.headers.containsKey('authorization'),isFalse);
    expect(jsonDecode(requests.single.body)['recovery_code'],'SAVED-RECOVERY-CODE');
    expect(find.byType(LoginPage),findsOneWidget);
    expect(api.token,isNull);
  });
}
