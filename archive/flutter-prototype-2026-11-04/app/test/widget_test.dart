import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nook/main.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('shows the Nook dashboard and primary navigation', (
    tester,
  ) async {
    await tester.pumpWidget(const NookApp());
    await tester.pumpAndSettle();

    expect(find.text('Nook'), findsOneWidget);
    expect(find.bySemanticsLabel('首页'), findsOneWidget);
    expect(find.bySemanticsLabel('便签'), findsOneWidget);
    expect(find.bySemanticsLabel('密码库'), findsOneWidget);
    expect(find.bySemanticsLabel('日程'), findsOneWidget);
    expect(find.bySemanticsLabel('记账'), findsOneWidget);
  });

  testWidgets('creates a note and keeps it in local storage', (tester) async {
    await tester.pumpWidget(const NookApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('nav-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('create-entry')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(EditableText).first, '周末整理书桌');
    await tester.enterText(find.byType(EditableText).last, '把旧笔记归档');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('nav-1')));
    await tester.pumpAndSettle();
    expect(find.text('周末整理书桌'), findsOneWidget);

    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('nook.local.entries.v1'), contains('周末整理书桌'));
  });
}
