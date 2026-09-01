import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:joerl_dashboard/screens/dashboard_screen.dart';
import 'package:joerl_dashboard/theme/app_theme.dart';

void main() {
  // Note: we test DashboardScreen directly rather than the full
  // JoErlDashboardApp — the app root talks to window_manager/tray_manager
  // over platform channels that aren't available in the widget test
  // harness, so pumping it here would throw MissingPluginException.
  testWidgets('Dashboard shows the JOERL-WORLD header', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.dark, home: const DashboardScreen()),
    );
    await tester.pump();

    expect(find.text('JOERL-WORLD'), findsOneWidget);
  });
}
