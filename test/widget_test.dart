import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nailarts_randevu_takip/main.dart';

void main() {
  testWidgets('Uygulama başlık ekranını açar', (tester) async {
    await tester.pumpWidget(const NailartsApp());
    await tester.pump();
    expect(find.byType(MaterialApp), findsOneWidget);
  });

  testWidgets('Saat seçici 24 saat ve 00-59 dakika seçenekleri sunar', (
    tester,
  ) async {
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

  test('Randevular arasında en az iki saat bırakılır', () {
    final booked = DateTime(2026, 11, 19, 10);

    expect(
      hasMinimumAppointmentGap(
        booked.add(const Duration(hours: 1, minutes: 59)),
        [booked],
      ),
      isFalse,
    );
    expect(
      hasMinimumAppointmentGap(booked.add(const Duration(hours: 2)), [booked]),
      isTrue,
    );
    expect(
      hasMinimumAppointmentGap(DateTime(2026, 11, 20, 0), [
        DateTime(2026, 11, 19, 23),
      ]),
      isFalse,
    );
  });

  test('WhatsApp telefonları ülke kodu ile normalize edilir', () {
    expect(normalizePhoneForWhatsApp('0555 123 45 67'), '905551234567');
    expect(normalizePhoneForWhatsApp('+90 (555) 123-45-67'), '905551234567');
    expect(normalizePhoneForWhatsApp('0090 555 123 45 67'), '905551234567');
  });

  test('Bulut eşitlemesi cihaz kayıtlarını koruyup silinenleri dışlar', () {
    final localCustomer = Customer(
      id: 'existing',
      name: 'Yerel ad',
      phone: '05551234567',
    );
    final cloudCustomer = Customer(
      id: 'existing',
      name: 'Eski bulut adı',
      phone: '05550000000',
    );
    final merged = mergeAccountData(
      localCustomers: [
        localCustomer,
        Customer(id: 'deleted', name: 'Silinmiş', phone: '05551111111'),
      ],
      localAppointments: [
        Appointment(
          id: 'local-appointment',
          date: DateTime(2026, 11, 19),
          time: '10:00',
          customerId: 'existing',
          service: 'Kalıcı oje',
        ),
        Appointment(
          id: 'deleted-appointment',
          date: DateTime(2026, 11, 19),
          time: '12:00',
          customerId: 'existing',
          service: 'Manikür',
        ),
      ],
      cloudCustomers: [
        cloudCustomer,
        Customer(id: 'cloud-only', name: 'Bulut müşteri', phone: '05552222222'),
      ],
      cloudAppointments: [
        Appointment(
          id: 'cloud-appointment',
          date: DateTime(2026, 11, 20),
          time: '14:00',
          customerId: 'cloud-only',
          service: 'Pedikür',
        ),
        Appointment(
          id: 'orphan-appointment',
          date: DateTime(2026, 11, 20),
          time: '16:00',
          customerId: 'deleted',
          service: 'Manikür',
        ),
      ],
      deletedCustomerIds: {'deleted'},
      deletedAppointmentIds: {'deleted-appointment'},
    );

    expect(
      merged.customers.map((customer) => customer.id),
      containsAll(['existing', 'cloud-only']),
    );
    expect(
      merged.customers
          .singleWhere((customer) => customer.id == 'existing')
          .name,
      'Yerel ad',
    );
    expect(
      merged.appointments.map((appointment) => appointment.id),
      containsAll(['local-appointment', 'cloud-appointment']),
    );
    expect(
      merged.appointments.map((appointment) => appointment.id),
      isNot(contains('orphan-appointment')),
    );
  });

  testWidgets('Takvim paneli randevu ayrıntılarını tarihe göre filtreler', (
    tester,
  ) async {
    final now = DateTime.now();
    final customer = Customer(
      id: '1',
      name: 'Ayşe Yılmaz',
      phone: '5551234567',
    );
    final appointment = Appointment(
      id: '1',
      date: DateTime(now.year, now.month, 1),
      time: '10:00',
      customerId: customer.id,
      service: 'Kalıcı oje',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CalendarPage(
            appointments: [appointment],
            customerById: (id) => id == customer.id ? customer : null,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Kalıcı oje'), findsOneWidget);
    await tester.tap(find.text('2').first);
    await tester.pumpAndSettle();
    expect(find.text('Kalıcı oje'), findsNothing);
    expect(find.text('Bu gün için randevu bulunmuyor.'), findsOneWidget);

    await tester.ensureVisible(find.text('Tümünü gör'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tümünü gör'));
    await tester.pumpAndSettle();
    expect(find.text('Kalıcı oje'), findsOneWidget);
  });
}
