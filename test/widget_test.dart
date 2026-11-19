import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nailarts_randevu_takip/main.dart';

void main() {
  testWidgets('Uygulama başlık ekranını açar', (tester) async {
    await tester.pumpWidget(const NailartsApp());
    await tester.pump();
    expect(find.byType(MaterialApp), findsOneWidget);
  });

  testWidgets('Saat seçici 24 saat ve 00-59 dakika seçenekleri sunar',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: TwentyFourHourTimePickerDialog(
            initialTime: TimeOfDay(hour: 10, minute: 0),
          ),
        ),
      ),
    );

    expect(find.text('AM'), findsNothing);
    expect(find.text('PM'), findsNothing);
    expect(find.text('Saat'), findsOneWidget);
    expect(find.text('Dakika'), findsOneWidget);
    expect(find.byType(DropdownButtonFormField<int>), findsNWidgets(2));
  });
}
