// PactReviewDialog (RF-SR-005/006/007, HU-SR-003): muestra el desglose del
// pacto de servicio y devuelve la decisión del cliente (aceptar/rechazar).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cold_day_flutter/features/request/pact_review_dialog.dart';

void main() {
  const agreement = {
    'id': 5,
    'technician_id': 7,
    'labor_cost': 80000,
    'transport_cost': 15000,
    'diagnosis_cost': 35000,
    'total': 130000,
    'observations': 'Fuga de gas refrigerante',
    'status': 'proposed',
  };

  testWidgets('muestra el desglose completo del pacto', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SizedBox.shrink())),
    );

    unawaited(PactReviewDialog.show(
      tester.element(find.byType(Scaffold)),
      agreement: agreement,
    ));
    await tester.pumpAndSettle();

    expect(find.text('Mano de obra'), findsOneWidget);
    expect(find.text('\$80.000'), findsOneWidget);
    expect(find.text('\$15.000'), findsOneWidget);
    expect(find.text('\$35.000'), findsOneWidget);
    expect(find.text('Total'), findsOneWidget);
    expect(find.text('\$130.000'), findsOneWidget);
    // El diálogo antepone "Diagnóstico: " al texto de observaciones.
    expect(find.textContaining('Fuga de gas refrigerante'), findsOneWidget);
  });

  testWidgets('"Aceptar pacto" devuelve aceptar', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SizedBox.shrink())),
    );

    PactReviewDecision? decision;
    unawaited(PactReviewDialog.show(
      tester.element(find.byType(Scaffold)),
      agreement: agreement,
    ).then((value) => decision = value));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Aceptar pacto'));
    await tester.pumpAndSettle();

    expect(decision, PactReviewDecision.accept);
  });

  testWidgets('"Rechazar pacto" devuelve rechazar', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SizedBox.shrink())),
    );

    PactReviewDecision? decision;
    unawaited(PactReviewDialog.show(
      tester.element(find.byType(Scaffold)),
      agreement: agreement,
    ).then((value) => decision = value));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Rechazar pacto'));
    await tester.pumpAndSettle();

    expect(decision, PactReviewDecision.reject);
  });
}
