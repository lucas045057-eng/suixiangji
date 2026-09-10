import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wealthmate_flutter/data/api_client.dart';
import 'package:wealthmate_flutter/features/auth/data/auth_remote_data_source.dart';
import 'package:wealthmate_flutter/features/auth/data/auth_repository.dart';
import 'package:wealthmate_flutter/features/auth/state/auth_store.dart';
import 'package:wealthmate_flutter/ui/login_page.dart';
import 'package:wealthmate_flutter/ui/theme.dart';

void main() {
  testWidgets('login page explains missing API configuration', (tester) async {
    final auth = AuthStore(
      repository: AuthRepository(
        remote: AuthRemoteDataSource(api: ApiClient(baseUrl: null)),
      ),
    );
    await tester.pumpWidget(MaterialApp(
      theme: wealthMateTheme(),
      home: LoginPage(auth: auth, onLoggedIn: () {}),
    ));

    await tester.tap(find.text('登录'));
    await tester.pumpAndSettle();

    expect(find.text('同步服务尚未配置'), findsOneWidget);
  });
}
