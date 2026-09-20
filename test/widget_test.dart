import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:instapharm/main.dart';

void main() {
  testWidgets('affiche l’écran d’erreur de config Supabase', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: InstaPharmApp(bootError: 'Clés Supabase manquantes'),
      ),
    );

    expect(find.text('Configuration'), findsOneWidget);
    expect(find.textContaining('Clés Supabase manquantes'), findsOneWidget);
    expect(find.byIcon(Icons.settings_outlined), findsOneWidget);
  });

  testWidgets('MaterialApp se construit avec un bootError', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: InstaPharmApp(bootError: 'test'),
      ),
    );
    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.byType(Scaffold), findsOneWidget);
  });
}
