import 'package:contact_call_exporter/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows exporter actions', (WidgetTester tester) async {
    await tester.pumpWidget(const ContactCallExporterApp());

    expect(find.text('مصدّر الأرقام'), findsWidgets);
    expect(find.text('استخراج جهات الاتصال'), findsOneWidget);
    expect(find.text('استخراج سجل المكالمات'), findsOneWidget);
    expect(find.byIcon(Icons.archive_outlined), findsOneWidget);
  });
}
