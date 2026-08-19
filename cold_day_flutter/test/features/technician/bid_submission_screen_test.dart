import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cold_day_flutter/features/technician/bid_submission_screen.dart';

void main() {
  testWidgets('BidSubmissionScreen displays a form', (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(home: BidSubmissionScreen()));
    
    expect(find.byType(Form), findsOneWidget);
    expect(find.byType(TextField), findsWidgets);
  });
}
