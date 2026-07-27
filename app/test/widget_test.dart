import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gongyi_app/main.dart';

void main() {
  testWidgets('App 启动显示加载页', (WidgetTester tester) async {
    await tester.pumpWidget(const GongyiApp());
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
