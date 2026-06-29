// Basic Flutter widget test for IGRIS Mobile App

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:igris_mobile/main.dart';

void main() {
  testWidgets('App launches smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(
      const ProviderScope(
        child: IgrisApp(),
      ),
    );

    // Verify that the app renders
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
