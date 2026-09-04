import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wealthmate_flutter/data/api_client.dart';
import 'package:wealthmate_flutter/ui/login_page.dart';
import 'package:wealthmate_flutter/ui/theme.dart';

void main() {
  testWidgets('login page explains missing API configuration', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: wealthMateTheme(),
      home: LoginPage(api: ApiClient(baseUrl: null), onLoggedIn: () {}),
    ));

    await tester.tap(find.text('登录'));
    await tester.pumpAndSettle();

    expect(find.text('同步服务尚未配置'), findsOneWidget);
  });
}
