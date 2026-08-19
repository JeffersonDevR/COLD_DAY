import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cold_day_flutter/features/technician/technician_dashboard.dart';

void main() {
  testWidgets('TechnicianDashboard displays a list of requests', (WidgetTester tester) async {
    // RED: The class does not exist.
    await tester.pumpWidget(MaterialApp(home: TechnicianDashboard()));
    
    expect(find.byType(ListView), findsOneWidget);
  });
}
