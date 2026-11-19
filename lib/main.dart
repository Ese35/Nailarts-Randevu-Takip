import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(const NailartsApp());

class Customer {
  Customer({required this.id, required this.name, required this.phone});
  final String id;
  final String name;
  final String phone;

  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'phone': phone};

  factory Customer.fromJson(Map<String, dynamic> json) => Customer(
        id: json['id'] as String,
        name: json['name'] as String,
        phone: json['phone'] as String,
      );
}

class Appointment {
  Appointment({
    required this.id,
    required this.date,
    required this.time,
    required this.customerId,
    required this.service,
  });
  final String id;
  final DateTime date;
  final String time;
  final String customerId;
  final String service;

  Map<String, dynamic> toJson() => {
        'id': id,
        'date': date.toIso8601String(),
        'time': time,
        'customerId': customerId,
        'service': service,
      };

  factory Appointment.fromJson(Map<String, dynamic> json) => Appointment(
        id: json['id'] as String,
        date: DateTime.parse(json['date'] as String),
        time: json['time'] as String,
        customerId: json['customerId'] as String,
        service: json['service'] as String,
      );
}

class NailartsApp extends StatelessWidget {
  const NailartsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'CEREN Nail & Beauty Studio',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFE91E63)),
        scaffoldBackgroundColor: const Color(0xFFF8F5F6),
        cardTheme: const CardThemeData(
          color: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(16)),
          ),
        ),
      ),
      home: const MainShell(),
    );
  }
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  static const _customersKey = 'nailarts_customers';
  static const _appointmentsKey = 'nailarts_appointments';
  int _index = 0;
  List<Customer> customers = [];
  List<Appointment> appointments = [];
  bool loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final customerData = prefs.getStringList(_customersKey) ?? [];
    final appointmentData = prefs.getStringList(_appointmentsKey) ?? [];
    setState(() {
      customers = customerData
          .map((value) => Customer.fromJson(jsonDecode(value) as Map<String, dynamic>))
          .toList();
      appointments = appointmentData
          .map((value) => Appointment.fromJson(jsonDecode(value) as Map<String, dynamic>))
          .toList();
      loaded = true;
    });
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _customersKey,
      customers.map((item) => jsonEncode(item.toJson())).toList(),
    );
    await prefs.setStringList(
      _appointmentsKey,
      appointments.map((item) => jsonEncode(item.toJson())).toList(),
    );
  }

  Customer? customerById(String id) {
    for (final customer in customers) {
      if (customer.id == id) return customer;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (!loaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    const items = [
      (Icons.calendar_month_outlined, 'Takvim'),
      (Icons.people_outline, 'Müşteri Listesi'),
      (Icons.event_available_outlined, 'Aktif Randevular'),
      (Icons.add_circle_outline, 'Randevu Oluştur'),
      (Icons.chat_bubble_outline, 'Bilgilendirme Mesajı'),
    ];

    final pages = [
      CalendarPage(
        appointments: appointments,
        customerById: customerById,
      ),
      CustomersPage(
        customers: customers,
        onAdd: (customer) {
          setState(() => customers.insert(0, customer));
          _save();
        },
        onDelete: (customer) {
          setState(() {
            customers.removeWhere((item) => item.id == customer.id);
            appointments.removeWhere((item) => item.customerId == customer.id);
          });
          _save();
        },
      ),
      AppointmentsPage(
        appointments: appointments,
        customerById: customerById,
        onDelete: (appointment) {
          setState(() {
            appointments.removeWhere((item) => item.id == appointment.id);
          });
          _save();
        },
      ),
      CreateAppointmentPage(
        customers: customers,
        appointments: appointments,
        onAddCustomer: (customer) {
          setState(() => customers.insert(0, customer));
          _save();
        },
        onSave: (appointment) {
          setState(() {
            appointments.add(appointment);
            _index = 2;
          });
          _save();
        },
      ),
      WhatsAppPage(
        appointments: appointments,
        customerById: customerById,
      ),
    ];

    return LayoutBuilder(builder: (context, constraints) {
      final wide = constraints.maxWidth >= 760;
      if (wide) {
        return Scaffold(
          body: Row(
            children: [
              Container(
                width: 238,
                color: Colors.white,
                child: SafeArea(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.fromLTRB(24, 28, 24, 24),
                        child: Row(
                          children: [
                            _BrandMark(size: 48),
                            SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('CEREN',
                                      style: TextStyle(
                                          color: Color(0xFFE91E63),
                                          fontSize: 19,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 1.2)),
                                  SizedBox(height: 2),
                                  Text('Nail & Beauty Studio',
                                      style: TextStyle(
                                          color: Color(0xFF817680),
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 1.1)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      for (var i = 0; i < items.length; i++)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 3),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () => setState(() => _index = i),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 13),
                              decoration: BoxDecoration(
                                color: i == _index
                                    ? const Color(0xFFFCE4EC)
                                    : null,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(children: [
                                Icon(items[i].$1,
                                    size: 21,
                                    color: i == _index
                                        ? const Color(0xFFE91E63)
                                        : const Color(0xFF71676D)),
                                const SizedBox(width: 12),
                                Text(items[i].$2,
                                    style: TextStyle(
                                      color: i == _index
                                          ? const Color(0xFFE91E63)
                                          : const Color(0xFF71676D),
                                      fontWeight: i == _index
                                          ? FontWeight.w700
                                          : FontWeight.w500,
                                    )),
                              ]),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              Expanded(child: pages[_index]),
            ],
          ),
        );
      }

      return Scaffold(
        appBar: AppBar(
          title: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _BrandMark(size: 36),
              SizedBox(width: 10),
              Text('CEREN Nail & Beauty Studio'),
            ],
          ),
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
        ),
        body: pages[_index],
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (value) => setState(() => _index = value),
          destinations: [
            for (final item in items)
              NavigationDestination(icon: Icon(item.$1), label: item.$2),
          ],
        ),
      );
    });
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.22),
      child: Image.asset(
        'assets/images/ceren_beautystudio.png',
        width: size,
        height: size,
        fit: BoxFit.cover,
      ),
    );
  }
}

class CalendarPage extends StatefulWidget {
  const CalendarPage({
    super.key,
    required this.appointments,
    required this.customerById,
  });

  final List<Appointment> appointments;
  final Customer? Function(String id) customerById;

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  late DateTime month;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    month = DateTime(now.year, now.month);
  }

  String monthName(int month) {
    const names = [
      'Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran',
      'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık'
    ];
    return names[month - 1];
  }

  bool sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  Widget build(BuildContext context) {
    final first = DateTime(month.year, month.month, 1);
    final leading = (first.weekday + 6) % 7;
    final dayCount = DateTime(month.year, month.month + 1, 0).day;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                  Expanded(
                    child: Text(
                      '${monthName(month.month)} ${month.year}',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF4A3F43),
                          ),
                    ),
                  ),
                  IconButton(
                  onPressed: () =>
                      setState(() => month = DateTime(month.year, month.month - 1)),
                  icon: const Icon(Icons.chevron_left),
                ),
                  IconButton(
                    onPressed: () =>
                        setState(() => month = DateTime(month.year, month.month + 1)),
                    icon: const Icon(Icons.chevron_right),
                  ),
                  ],
                ),
                const SizedBox(height: 10),
                Card(
                  shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                  side: const BorderSide(color: Color(0xFFF2E4E8)),
                  ),
                  child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(children: [
                  Row(
                    children: [
                      for (final name in ['Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz'])
                        Expanded(
                          child: Center(
                            child: Text(name,
                                style: TextStyle(
                                    color: Color(0xFF817680),
                                    fontWeight: FontWeight.w600)),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 7,
                      mainAxisSpacing: 3,
                      crossAxisSpacing: 3,
                      childAspectRatio: 1.18,
                    ),
                    itemCount: leading + dayCount,
                    itemBuilder: (context, index) {
                      if (index < leading) {
                        return const SizedBox();
                      }
                      final day = index - leading + 1;
                      final date = DateTime(month.year, month.month, day);
                      final dayAppointments = widget.appointments
                          .where((item) => sameDay(item.date, date))
                          .toList();
                      final today = sameDay(date, DateTime.now());
                      return InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () => _showDay(context, date, dayAppointments),
                        child: Container(
                          decoration: BoxDecoration(
                            color: today
                                ? const Color(0xFFFCE4EC)
                                : dayAppointments.isNotEmpty
                                    ? const Color(0xFFFFF4F7)
                                    : null,
                            borderRadius: BorderRadius.circular(10),
                            border: today
                                ? Border.all(color: const Color(0xFFE91E63))
                                : null,
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text('$day',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: today
                                        ? FontWeight.w800
                                        : FontWeight.w600,
                                    color: today
                                        ? const Color(0xFFE91E63)
                                        : null,
                                  )),
                              if (dayAppointments.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 3),
                                  child: Container(
                                    width: 6,
                                    height: 6,
                                    decoration: const BoxDecoration(
                                      color: Color(0xFFE91E63),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ]),
              ),
            ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showDay(
      BuildContext context, DateTime date, List<Appointment> dayAppointments) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${date.day}.${date.month}.${date.year}',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              if (dayAppointments.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: Text('Bu güne ait randevu bulunmuyor')),
                )
              else
                for (final item in dayAppointments)
                  Card(
                    child: ListTile(
                      leading: const CircleAvatar(
                        backgroundColor: Color(0xFFFCE4EC),
                        child: Icon(Icons.event, color: Color(0xFFE91E63)),
                      ),
                      title: Text('${item.time} - ${item.service}'),
                      subtitle: Text(
                        widget.customerById(item.customerId)?.name ??
                            'Bilinmeyen müşteri',
                      ),
                    ),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

class CustomersPage extends StatefulWidget {
  const CustomersPage({
    super.key,
    required this.customers,
    required this.onAdd,
    required this.onDelete,
  });

  final List<Customer> customers;
  final ValueChanged<Customer> onAdd;
  final ValueChanged<Customer> onDelete;

  @override
  State<CustomersPage> createState() => _CustomersPageState();
}

class _CustomersPageState extends State<CustomersPage> {
  String query = '';

  void _showCustomerDialog() {
    final name = TextEditingController();
    final phone = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Yeni Müşteri'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Müşteri adı soyadı',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Müşteri numarası',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('İptal')),
          FilledButton(
            onPressed: () {
              if (name.text.trim().isEmpty || phone.text.trim().isEmpty) return;
              widget.onAdd(Customer(
                id: DateTime.now().microsecondsSinceEpoch.toString(),
                name: name.text.trim(),
                phone: phone.text.trim(),
              ));
              Navigator.pop(context);
            },
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = widget.customers
        .where((item) =>
            item.name.toLowerCase().contains(query.toLowerCase()) ||
            item.phone.contains(query))
        .toList();

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                child: Text('Müşteri Listesi',
                    style: Theme.of(context).textTheme.headlineSmall),
              ),
              FilledButton.icon(
                onPressed: _showCustomerDialog,
                icon: const Icon(Icons.person_add_alt_1),
                label: const Text('Müşteri Ekle'),
              ),
            ]),
            const SizedBox(height: 16),
            TextField(
              onChanged: (value) => setState(() => query = value),
              decoration: const InputDecoration(
                hintText: 'Ad veya telefon ara',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                filled: true,
                fillColor: Colors.white,
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: filtered.isEmpty
                  ? const Center(child: Text('Kayıtlı müşteri bulunmuyor'))
                  : ListView.separated(
                      itemCount: filtered.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final customer = filtered[index];
                        return Card(
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: const Color(0xFFFCE4EC),
                              child: Text(
                                customer.name.isEmpty
                                    ? '?'
                                    : customer.name.characters.first.toUpperCase(),
                                style: const TextStyle(
                                    color: Color(0xFFE91E63),
                                    fontWeight: FontWeight.w800),
                              ),
                            ),
                            title: Text(customer.name),
                            subtitle: Text(customer.phone),
                            trailing: IconButton(
                              tooltip: 'Müşteriyi sil',
                              onPressed: () => widget.onDelete(customer),
                              icon: const Icon(Icons.delete_outline),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class AppointmentsPage extends StatelessWidget {
  const AppointmentsPage({
    super.key,
    required this.appointments,
    required this.customerById,
    required this.onDelete,
  });

  final List<Appointment> appointments;
  final Customer? Function(String id) customerById;
  final ValueChanged<Appointment> onDelete;

  @override
  Widget build(BuildContext context) {
    final future = [...appointments]
      ..sort((a, b) =>
          '${a.date.year}-${a.date.month}-${a.date.day}-${a.time}'
              .compareTo('${b.date.year}-${b.date.month}-${b.date.day}-${b.time}'));

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Aktif Randevular',
                style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 16),
            Expanded(
              child: future.isEmpty
                  ? const Center(child: Text('Aktif randevu bulunmuyor'))
                  : ListView.separated(
                      itemCount: future.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final item = future[index];
                        final customer = customerById(item.customerId);
                        return Card(
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 8),
                            leading: CircleAvatar(
                              backgroundColor: const Color(0xFFFCE4EC),
                              child: Text(
                                item.time,
                                style: const TextStyle(
                                    color: Color(0xFFE91E63),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800),
                              ),
                            ),
                            title: Text(customer?.name ?? 'Bilinmeyen müşteri'),
                            subtitle: Text(
                              '${item.date.day}.${item.date.month}.${item.date.year} • ${item.service}\n${customer?.phone ?? ''}',
                            ),
                            isThreeLine: true,
                            trailing: IconButton(
                              tooltip: 'Randevuyu sil',
                              onPressed: () => onDelete(item),
                              icon: const Icon(Icons.delete_outline),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class WhatsAppPage extends StatefulWidget {
  const WhatsAppPage({
    super.key,
    required this.appointments,
    required this.customerById,
  });

  final List<Appointment> appointments;
  final Customer? Function(String id) customerById;

  @override
  State<WhatsAppPage> createState() => _WhatsAppPageState();
}

class _WhatsAppPageState extends State<WhatsAppPage> {
  static const _token = String.fromEnvironment('WHATSAPP_ACCESS_TOKEN');
  static const _phoneNumberId =
      String.fromEnvironment('WHATSAPP_PHONE_NUMBER_ID');
  static const _apiVersion =
      String.fromEnvironment('WHATSAPP_API_VERSION', defaultValue: 'v22.0');

  final _message = TextEditingController(
    text:
        'Merhaba {{MusteriAdi}}! CEREN Nail & Beauty Studio randevunuzu hatırlatmak istiyoruz.',
  );
  bool _sending = false;

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  bool _isUpcoming(Appointment appointment) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final date = DateTime(
      appointment.date.year,
      appointment.date.month,
      appointment.date.day,
    );
    return !date.isBefore(today);
  }

  String _buildMessage(Appointment appointment, Customer customer) {
    final message = _message.text
        .replaceAll('{{MusteriAdi}}', customer.name)
        .replaceAll(
          '{{RandevuTarihi}}',
          '${appointment.date.day}.${appointment.date.month}.${appointment.date.year}',
        )
        .replaceAll('{{RandevuSaati}}', appointment.time)
        .replaceAll('{{Islem}}', appointment.service);

    return '$message\n\n'
        'Randevu Bilgileri:\n'
        'Müşteri: ${customer.name}\n'
        'Tarih: ${appointment.date.day}.${appointment.date.month}.${appointment.date.year}\n'
        'Saat: ${appointment.time}\n'
        'Yapılacak işlem: ${appointment.service}';
  }

  Future<void> _send(Appointment appointment) async {
    final customer = widget.customerById(appointment.customerId);
    if (customer == null) {
      _showMessage('Müşteri bilgisi bulunamadı');
      return;
    }
    if (_token.isEmpty || _phoneNumberId.isEmpty) {
      _showMessage(
        'WhatsApp API ayarları eksik. WHATSAPP_ACCESS_TOKEN ve '
        'WHATSAPP_PHONE_NUMBER_ID değerleri tanımlanmalı.',
      );
      return;
    }

    final recipient = customer.phone.replaceAll(RegExp(r'\D'), '');
    if (recipient.isEmpty) {
      _showMessage('Müşteri telefon numarası geçersiz');
      return;
    }

    setState(() => _sending = true);
    try {
      final uri = Uri.parse(
        'https://graph.facebook.com/$_apiVersion/$_phoneNumberId/messages',
      );
      final response = await http.post(
        uri,
        headers: {
          'Authorization': 'Bearer $_token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'messaging_product': 'whatsapp',
          'recipient_type': 'individual',
          'to': recipient,
          'type': 'text',
          'text': {
            'preview_url': false,
            'body': _buildMessage(appointment, customer),
          },
        }),
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        _showMessage('WhatsApp mesajı gönderildi');
      } else {
        _showMessage(
          'WhatsApp API hatası (${response.statusCode})',
        );
      }
    } catch (_) {
      _showMessage('WhatsApp API bağlantısı kurulamadı');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final upcoming = widget.appointments
        .where(_isUpcoming)
        .toList()
      ..sort((a, b) =>
          '${a.date.year}-${a.date.month}-${a.date.day}-${a.time}'
              .compareTo('${b.date.year}-${b.date.month}-${b.date.day}-${b.time}'));

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Bilgilendirme Mesajı Gönder',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _message,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Mesaj şablonu',
                border: OutlineInputBorder(),
                filled: true,
                fillColor: Colors.white,
                helperText:
                    'Kullanılabilir alanlar: {{MusteriAdi}}, {{RandevuTarihi}}, {{RandevuSaati}}, {{Islem}}',
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: upcoming.isEmpty
                  ? const Center(
                      child: Text('Yaklaşan randevu bulunmuyor'),
                    )
                  : ListView.separated(
                      itemCount: upcoming.length,
                      separatorBuilder: (_, _) =>
                          const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final appointment = upcoming[index];
                        final customer =
                            widget.customerById(appointment.customerId);
                        return Card(
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            leading: const CircleAvatar(
                              backgroundColor: Color(0xFFFCE4EC),
                              child: Icon(
                                Icons.chat,
                                color: Color(0xFFE91E63),
                              ),
                            ),
                            title: Text(
                              customer?.name ?? 'Bilinmeyen müşteri',
                            ),
                            subtitle: Text(
                              '${appointment.date.day}.${appointment.date.month}.${appointment.date.year} • ${appointment.time}\n${appointment.service}\n${customer?.phone ?? ''}',
                            ),
                            isThreeLine: true,
                            trailing: FilledButton(
                              onPressed:
                                  _sending ? null : () => _send(appointment),
                              child: const Text('Gönder'),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class TwentyFourHourTimePickerDialog extends StatefulWidget {
  const TwentyFourHourTimePickerDialog({
    super.key,
    required this.initialTime,
  });

  final TimeOfDay initialTime;

  @override
  State<TwentyFourHourTimePickerDialog> createState() =>
      _TwentyFourHourTimePickerDialogState();
}

class _TwentyFourHourTimePickerDialogState
    extends State<TwentyFourHourTimePickerDialog> {
  late int selectedHour = widget.initialTime.hour;
  late int selectedMinute = widget.initialTime.minute;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Randevu saati'),
      content: Row(
        children: [
          Expanded(
            child: DropdownButtonFormField<int>(
              initialValue: selectedHour,
              menuMaxHeight: 320,
              decoration: const InputDecoration(
                labelText: 'Saat',
                border: OutlineInputBorder(),
              ),
              items: [
                for (var hour = 0; hour < 24; hour++)
                  DropdownMenuItem(
                    value: hour,
                    child: Text(hour.toString().padLeft(2, '0')),
                  ),
              ],
              onChanged: (value) {
                if (value != null) setState(() => selectedHour = value);
              },
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: Text(':', style: TextStyle(fontSize: 24)),
          ),
          Expanded(
            child: DropdownButtonFormField<int>(
              initialValue: selectedMinute,
              menuMaxHeight: 320,
              decoration: const InputDecoration(
                labelText: 'Dakika',
                border: OutlineInputBorder(),
              ),
              items: [
                for (var minute = 0; minute < 60; minute++)
                  DropdownMenuItem(
                    value: minute,
                    child: Text(minute.toString().padLeft(2, '0')),
                  ),
              ],
              onChanged: (value) {
                if (value != null) setState(() => selectedMinute = value);
              },
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('İptal'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            TimeOfDay(hour: selectedHour, minute: selectedMinute),
          ),
          child: const Text('Seç'),
        ),
      ],
    );
  }
}

class CreateAppointmentPage extends StatefulWidget {
  const CreateAppointmentPage({
    super.key,
    required this.customers,
    required this.appointments,
    required this.onAddCustomer,
    required this.onSave,
  });

  final List<Customer> customers;
  final List<Appointment> appointments;
  final ValueChanged<Customer> onAddCustomer;
  final ValueChanged<Appointment> onSave;

  @override
  State<CreateAppointmentPage> createState() => _CreateAppointmentPageState();
}

class _CreateAppointmentPageState extends State<CreateAppointmentPage> {
  DateTime date = DateTime.now();
  TimeOfDay time = const TimeOfDay(hour: 10, minute: 0);
  String? customerId;
  final service = TextEditingController();

  @override
  void dispose() {
    service.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final value = await showDatePicker(
      context: context,
      initialDate: date,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
    );
    if (value != null) setState(() => date = value);
  }

  Future<void> _pickTime() async {
    final value = await showDialog<TimeOfDay>(
      context: context,
      builder: (_) => TwentyFourHourTimePickerDialog(initialTime: time),
    );
    if (value != null) setState(() => time = value);
  }

  void _addCustomerQuick() {
    final name = TextEditingController();
    final phone = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Yeni Müşteri'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              decoration: const InputDecoration(
                  labelText: 'Ad soyad', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                  labelText: 'Telefon', border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('İptal')),
          FilledButton(
            onPressed: () {
              if (name.text.trim().isEmpty || phone.text.trim().isEmpty) return;
              final customer = Customer(
                id: DateTime.now().microsecondsSinceEpoch.toString(),
                name: name.text.trim(),
                phone: phone.text.trim(),
              );
              widget.onAddCustomer(customer);
              setState(() => customerId = customer.id);
              Navigator.pop(context);
            },
            child: const Text('Ekle'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final timeText =
        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Randevu Oluştur',
                  style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.calendar_month),
                        title: const Text('Randevu günü'),
                        subtitle: Text(
                            '${date.day}.${date.month}.${date.year}',
                            style: const TextStyle(fontWeight: FontWeight.w700)),
                        trailing: TextButton(
                            onPressed: _pickDate, child: const Text('Seç')),
                      ),
                      const Divider(),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.schedule),
                        title: const Text('Randevu saati'),
                        subtitle: Text(timeText,
                            style:
                                const TextStyle(fontWeight: FontWeight.w700)),
                        trailing: TextButton(
                            onPressed: _pickTime, child: const Text('Seç')),
                      ),
                      const Divider(),
                      Row(children: [
                        const Expanded(
                          child: Text('Müşteri',
                              style: TextStyle(fontWeight: FontWeight.w700)),
                        ),
                        TextButton.icon(
                          onPressed: _addCustomerQuick,
                          icon: const Icon(Icons.person_add_alt),
                          label: const Text('Yeni müşteri'),
                        ),
                      ]),
                      DropdownButtonFormField<String>(
                        initialValue: customerId,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          hintText: 'Müşteri seçin',
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          for (final customer in widget.customers)
                            DropdownMenuItem(
                              value: customer.id,
                              child: Text('${customer.name} • ${customer.phone}'),
                            ),
                        ],
                        onChanged: (value) =>
                            setState(() => customerId = value),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: service,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          labelText: 'Yapılacak işlem',
                          hintText: 'Örn. Kalıcı oje, protez tırnak...',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        onPressed: () {
                          if (customerId == null ||
                              service.text.trim().isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text(
                                      'Müşteri ve yapılacak işlem zorunlu')),
                            );
                            return;
                          }
                          final conflict = widget.appointments.any((item) =>
                              item.date.year == date.year &&
                              item.date.month == date.month &&
                              item.date.day == date.day &&
                              item.time == timeText);
                          if (conflict) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content:
                                      Text('Bu tarih ve saatte randevu mevcut')),
                            );
                            return;
                          }
                          widget.onSave(Appointment(
                            id: DateTime.now().microsecondsSinceEpoch.toString(),
                            date: date,
                            time: timeText,
                            customerId: customerId!,
                            service: service.text.trim(),
                          ));
                        },
                        icon: const Icon(Icons.check),
                        label: const Padding(
                          padding: EdgeInsets.symmetric(vertical: 14),
                          child: Text('Randevuyu Kaydet'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
