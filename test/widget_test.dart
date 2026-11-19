import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nailarts_randevu_takip/main.dart';

void main() {
  testWidgets('Uygulama başlık ekranını açar', (tester) async {
    await tester.pumpWidget(const NailartsApp());
    await tester.pump();
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
