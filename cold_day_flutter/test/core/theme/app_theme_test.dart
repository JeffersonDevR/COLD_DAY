import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cold_day_flutter/core/theme/app_theme.dart';
import 'package:cold_day_flutter/core/widgets/app_widgets.dart';
import 'package:cold_day_flutter/features/home/home_screen.dart';

double _contrast(Color foreground, Color background) {
  final foregroundLuminance = foreground.computeLuminance();
  final backgroundLuminance = background.computeLuminance();
  final lighter = foregroundLuminance > backgroundLuminance
      ? foregroundLuminance
      : backgroundLuminance;
  final darker = foregroundLuminance > backgroundLuminance
      ? backgroundLuminance
      : foregroundLuminance;
  return (lighter + 0.05) / (darker + 0.05);
}

void main() {
  test('Sage+ink brand tokens are exposed by the light scheme', () {
    final scheme = AppColors.lightScheme();
    expect(scheme.primary, const Color(0xFF262D2A));
    expect(scheme.primaryContainer, const Color(0xFFDCECE7));
    expect(scheme.secondary, const Color(0xFF3E5B50));
    expect(scheme.secondaryContainer, const Color(0xFFD6E8E0));
    expect(scheme.tertiaryContainer, const Color(0xFFD3E2DB));
    expect(scheme.surface, const Color(0xFFFFFFFF));
    expect(scheme.onSurface, const Color(0xFF1A211F));
  });

  test('primary actions and body text meet readable contrast', () {
    for (final theme in [
      buildAppTheme(Brightness.light),
      buildAppTheme(Brightness.dark),
    ]) {
      final scheme = theme.colorScheme;
      expect(
        _contrast(scheme.onPrimary, scheme.primary),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        _contrast(scheme.onSurface, scheme.surface),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        _contrast(scheme.onSurfaceVariant, theme.scaffoldBackgroundColor),
        greaterThanOrEqualTo(4.5),
      );
    }
  });

  testWidgets('AppButton exposes its Spanish action through semantics', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light),
        home: Scaffold(
          body: AppButton(label: 'Buscar técnicos', onPressed: () {}),
        ),
      ),
    );

    expect(find.bySemanticsLabel('Buscar técnicos'), findsAtLeastNWidgets(1));
    expect(
      tester.getSize(find.byType(FilledButton)).height,
      greaterThanOrEqualTo(48),
    );
  });

  testWidgets('landing remains renderable at a narrow width', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light),
        home: const HomeScreen(),
      ),
    );
    expect(find.text('Cold Day'), findsOneWidget);
  });

  testWidgets('StatusBadge keeps a minimum interactive-safe visual rhythm', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light),
        home: const Scaffold(body: StatusBadge(label: 'Pendiente')),
      ),
    );
    expect(find.text('Pendiente'), findsOneWidget);
    expect(
      tester.getSize(find.byType(StatusBadge)).height,
      greaterThanOrEqualTo(28),
    );
  });

  testWidgets('AppTimeline renders real request event semantics', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light),
        home: const Scaffold(
          body: AppTimeline(
            events: [
              AppTimelineEvent(
                title: 'Solicitud creada',
                subtitle: '18 ago 2026',
                status: 'En oferta',
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Solicitud creada'), findsOneWidget);
    expect(find.text('En oferta'), findsOneWidget);
  });
}
