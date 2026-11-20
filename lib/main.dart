import 'dart:async';
import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'firebase_bootstrap.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Object? startupError;
  try {
    await FirebaseBootstrap.initialize();
  } catch (error) {
    startupError = error;
  }
  runApp(NailartsApp(startupError: startupError));
}

class Customer {
  Customer({required this.id, required this.name, required this.phone});
  final String id;
  final String name;
  final String phone;

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'phone': phone};

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

class FirebaseAccountApi {
  FirebaseFunctions get _functions =>
      FirebaseFunctions.instanceFor(region: 'europe-west1');

  Map<String, dynamic> _readMap(Object? value, String label) {
    if (value is! Map) throw FormatException('$label biçimi geçersiz.');
    return Map<String, dynamic>.from(value);
  }

  List<Map<String, dynamic>> _readRecords(Object? value, String label) {
    if (value is! List) throw FormatException('$label listesi geçersiz.');
    return value
        .map((record) => _readMap(record, label))
        .toList(growable: false);
  }

  Set<String> _readIds(Object? value, String label) {
    if (value is! List || value.any((id) => id is! String)) {
      throw FormatException('$label kimlik listesi geçersiz.');
    }
    return value.cast<String>().toSet();
  }

  Future<
    ({
      List<Customer> customers,
      List<Appointment> appointments,
      Set<String> deletedCustomerIds,
      Set<String> deletedAppointmentIds,
    })
  >
  loadAccountData() async {
    final response = await _functions
        .httpsCallable('loadAccountData')
        .call<Object?>();
    final data = _readMap(response.data, 'Bulut verisi');
    final customers = _readRecords(
      data['customers'],
      'Müşteri',
    ).map(Customer.fromJson).toList();
    final appointments = _readRecords(
      data['appointments'],
      'Randevu',
    ).map(Appointment.fromJson).toList();
    return (
      customers: customers,
      appointments: appointments,
      deletedCustomerIds: _readIds(
        data['deletedCustomerIds'],
        'Silinen müşteri',
      ),
      deletedAppointmentIds: _readIds(
        data['deletedAppointmentIds'],
        'Silinen randevu',
      ),
    );
  }

  Future<({Set<String> deletedCustomerIds, Set<String> deletedAppointmentIds})>
  syncAccountData({
    required List<Customer> customers,
    required List<Appointment> appointments,
    required Set<String> deletedCustomerIds,
    required Set<String> deletedAppointmentIds,
  }) async {
    final response = await _functions
        .httpsCallable('syncAccountData')
        .call<Object?>({
          'customers': customers.map((customer) => customer.toJson()).toList(),
          'appointments': appointments
              .map((appointment) => appointment.toJson())
              .toList(),
          'deletedCustomerIds': deletedCustomerIds.toList(),
          'deletedAppointmentIds': deletedAppointmentIds.toList(),
        });
    final data = _readMap(response.data, 'Eşitleme yanıtı');
    return (
      deletedCustomerIds: _readIds(
        data['deletedCustomerIds'],
        'Silinen müşteri',
      ),
      deletedAppointmentIds: _readIds(
        data['deletedAppointmentIds'],
        'Silinen randevu',
      ),
    );
  }

  Future<String?> sendAppointmentReminder({
    required String phone,
    required String customerName,
    required String appointmentDate,
    required String appointmentTime,
    required String service,
  }) async {
    final response = await _functions
        .httpsCallable('sendAppointmentReminder')
        .call<Object?>({
          'phone': phone,
          'customerName': customerName,
          'appointmentDate': appointmentDate,
          'appointmentTime': appointmentTime,
          'service': service,
        });
    final data = _readMap(response.data, 'WhatsApp yanıtı');
    return data['messageId'] as String?;
  }
}

String normalizePhoneForWhatsApp(String phone) {
  var digits = phone.replaceAll(RegExp(r'\D'), '');
  if (digits.startsWith('00')) digits = digits.substring(2);
  if (digits.startsWith('0')) {
    digits = '90${digits.substring(1)}';
  } else if (digits.length == 10) {
    digits = '90$digits';
  }
  return digits;
}

({List<Customer> customers, List<Appointment> appointments}) mergeAccountData({
  required List<Customer> localCustomers,
  required List<Appointment> localAppointments,
  required List<Customer> cloudCustomers,
  required List<Appointment> cloudAppointments,
  required Set<String> deletedCustomerIds,
  required Set<String> deletedAppointmentIds,
}) {
  final customers = <String, Customer>{
    for (final item in cloudCustomers)
      if (!deletedCustomerIds.contains(item.id)) item.id: item,
    for (final item in localCustomers)
      if (!deletedCustomerIds.contains(item.id)) item.id: item,
  };
  final appointments = <String, Appointment>{
    for (final item in cloudAppointments)
      if (!deletedAppointmentIds.contains(item.id) &&
          !deletedCustomerIds.contains(item.customerId))
        item.id: item,
    for (final item in localAppointments)
      if (!deletedAppointmentIds.contains(item.id) &&
          !deletedCustomerIds.contains(item.customerId))
        item.id: item,
  };
  return (
    customers: customers.values.toList(),
    appointments: appointments.values.toList(),
  );
}

bool hasMinimumAppointmentGap(
  DateTime candidate,
  Iterable<DateTime> existingAppointments,
) {
  const minimumGapInSeconds = 2 * 60 * 60;
  return existingAppointments.every((existing) {
    return existing.difference(candidate).inSeconds.abs() >=
        minimumGapInSeconds;
  });
}

Future<Contact?> _pickDeviceContact(BuildContext context) async {
  if (kIsWeb) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Rehber seçimi yalnızca yerel iOS/Android uygulamasında kullanılabilir.',
        ),
      ),
    );
    return null;
  }

  try {
    if (defaultTargetPlatform == TargetPlatform.android) {
      final permission = await FlutterContacts.permissions.request(
        PermissionType.read,
      );
      if (permission != PermissionStatus.granted) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Rehber izni verilmedi.')),
          );
        }
        return null;
      }
    }

    return await FlutterContacts.native.showPicker(
      properties: {ContactProperty.phone},
    );
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Rehber açılamadı: $error')));
    }
    return null;
  }
}

class NailartsApp extends StatelessWidget {
  const NailartsApp({super.key, this.startupError});

  final Object? startupError;

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
      home: FirebaseGate(startupError: startupError),
    );
  }
}

class FirebaseGate extends StatelessWidget {
  const FirebaseGate({super.key, this.startupError});

  final Object? startupError;

  @override
  Widget build(BuildContext context) {
    if (startupError != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Uygulama yapılandırma hatası: $startupError'),
          ),
        ),
      );
    }
    if (!FirebaseBootstrap.initialized) return const MainShell();

    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.userChanges(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Scaffold(
            body: Center(
              child: Text('Firebase oturum hatası: ${snapshot.error}'),
            ),
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final user = snapshot.data;
        if (user == null) return const FirebaseLoginPage();
        if (user.email?.trim().toLowerCase() != FirebaseBootstrap.adminEmail) {
          return FirebaseUnauthorizedPage(email: user.email ?? '');
        }
        if (!user.emailVerified) return FirebaseVerifyEmailPage(user: user);
        return const MainShell(cloudEnabled: true);
      },
    );
  }
}

class FirebaseLoginPage extends StatefulWidget {
  const FirebaseLoginPage({super.key});

  @override
  State<FirebaseLoginPage> createState() => _FirebaseLoginPageState();
}

class FirebaseUnauthorizedPage extends StatelessWidget {
  const FirebaseUnauthorizedPage({super.key, required this.email});

  final String email;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('$email bu uygulamayı kullanmaya yetkili değil.'),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => FirebaseAuth.instance.signOut(),
                child: const Text('Çıkış yap'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FirebaseLoginPageState extends State<FirebaseLoginPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _busy = false;
  String? _message;
  bool _messageIsError = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
    } on FirebaseAuthException catch (error) {
      if (!mounted) return;
      setState(() {
        _message = error.message ?? 'Firebase kimlik doğrulaması başarısız.';
        _messageIsError = true;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _message = 'İşlem tamamlanamadı: $error';
        _messageIsError = true;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Card(
            margin: const EdgeInsets.all(24),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _BrandMark(size: 56),
                  const SizedBox(height: 16),
                  Text(
                    'Giriş yap',
                    style: Theme.of(context).textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    decoration: const InputDecoration(labelText: 'E-posta'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _passwordController,
                    obscureText: true,
                    autofillHints: const [AutofillHints.password],
                    decoration: const InputDecoration(labelText: 'Şifre'),
                  ),
                  if (_message != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _message!,
                      style: TextStyle(
                        color: _messageIsError
                            ? Theme.of(context).colorScheme.error
                            : const Color(0xFF5D735F),
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Giriş yap'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class FirebaseVerifyEmailPage extends StatefulWidget {
  const FirebaseVerifyEmailPage({super.key, required this.user});

  final User user;

  @override
  State<FirebaseVerifyEmailPage> createState() =>
      _FirebaseVerifyEmailPageState();
}

class _FirebaseVerifyEmailPageState extends State<FirebaseVerifyEmailPage> {
  String? _message;
  bool _busy = false;

  Future<void> _checkVerification() async {
    setState(() => _busy = true);
    try {
      await FirebaseAuth.instance.currentUser?.reload();
      if (mounted) {
        setState(() => _message = 'E-posta doğrulaması henüz tamamlanmadı.');
      }
    } on FirebaseAuthException catch (error) {
      if (mounted) setState(() => _message = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resendVerification() async {
    try {
      await widget.user.sendEmailVerification();
      if (mounted) {
        setState(() => _message = 'Doğrulama e-postası yeniden gönderildi.');
      }
    } on FirebaseAuthException catch (error) {
      if (mounted) setState(() => _message = error.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Card(
            margin: const EdgeInsets.all(24),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'E-posta adresinizi doğrulayın',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Doğrulama bağlantısı ${widget.user.email} adresine gönderildi.',
                  ),
                  if (_message != null) ...[
                    const SizedBox(height: 12),
                    Text(_message!),
                  ],
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _busy ? null : _checkVerification,
                    child: const Text('Doğrulamayı kontrol et'),
                  ),
                  TextButton(
                    onPressed: _resendVerification,
                    child: const Text('E-postayı yeniden gönder'),
                  ),
                  TextButton(
                    onPressed: FirebaseAuth.instance.signOut,
                    child: const Text('Çıkış yap'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class MainShell extends StatefulWidget {
  const MainShell({super.key, this.cloudEnabled = false});

  final bool cloudEnabled;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  static const _customersKey = 'nailarts_customers';
  static const _appointmentsKey = 'nailarts_appointments';
  static const _deletedCustomersKey = 'nailarts_deleted_customers';
  static const _deletedAppointmentsKey = 'nailarts_deleted_appointments';
  final _accountApi = FirebaseAccountApi();
  final Set<String> _deletedCustomerIds = {};
  final Set<String> _deletedAppointmentIds = {};
  Future<void> _saveTail = Future<void>.value();
  int _index = 0;
  List<Customer> customers = [];
  List<Appointment> appointments = [];
  bool loaded = false;
  String? _loadError;
  String? _cloudError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final customerData = prefs.getStringList(_customersKey) ?? [];
      final appointmentData = prefs.getStringList(_appointmentsKey) ?? [];
      final localCustomers = customerData
          .map(
            (value) =>
                Customer.fromJson(jsonDecode(value) as Map<String, dynamic>),
          )
          .toList();
      final localAppointments = appointmentData
          .map(
            (value) =>
                Appointment.fromJson(jsonDecode(value) as Map<String, dynamic>),
          )
          .toList();
      _deletedCustomerIds
        ..clear()
        ..addAll(prefs.getStringList(_deletedCustomersKey) ?? []);
      _deletedAppointmentIds
        ..clear()
        ..addAll(prefs.getStringList(_deletedAppointmentsKey) ?? []);
      if (!mounted) return;
      setState(() {
        customers = localCustomers;
        appointments = localAppointments;
        loaded = !widget.cloudEnabled;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _loadError = 'Cihazdaki kayıtlar yüklenemedi: $error';
        });
      }
      return;
    }

    if (widget.cloudEnabled) await _loadCloudData();
  }

  Future<void> _loadCloudData() async {
    try {
      final cloudData = await _accountApi.loadAccountData();
      final deletedCustomerIds = {
        ...cloudData.deletedCustomerIds,
        ..._deletedCustomerIds,
      };
      final deletedAppointmentIds = {
        ...cloudData.deletedAppointmentIds,
        ..._deletedAppointmentIds,
      };
      final merged = mergeAccountData(
        localCustomers: customers,
        localAppointments: appointments,
        cloudCustomers: cloudData.customers,
        cloudAppointments: cloudData.appointments,
        deletedCustomerIds: deletedCustomerIds,
        deletedAppointmentIds: deletedAppointmentIds,
      );
      if (!mounted) return;
      setState(() {
        customers = merged.customers;
        appointments = merged.appointments;
        loaded = true;
      });
      await _persistLocal();
      await _syncCloudSnapshot();
    } catch (error) {
      if (mounted) {
        setState(() {
          loaded = true;
          _cloudError =
              'Bulut eşitlemesi tamamlanamadı; cihaz kayıtları korundu. $error';
        });
      }
    }
  }

  Future<void> _save() {
    final pending = _saveTail.then((_) async {
      await _persistLocal();
      if (widget.cloudEnabled) await _syncCloudSnapshot();
    });
    _saveTail = pending.catchError((Object error) {
      _setCloudError('Kayıt eşitlemesi tamamlanamadı: $error');
    });
    return _saveTail;
  }

  Future<void> _persistLocal() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _customersKey,
      customers.map((item) => jsonEncode(item.toJson())).toList(),
    );
    await prefs.setStringList(
      _appointmentsKey,
      appointments.map((item) => jsonEncode(item.toJson())).toList(),
    );
    await prefs.setStringList(
      _deletedCustomersKey,
      _deletedCustomerIds.toList(),
    );
    await prefs.setStringList(
      _deletedAppointmentsKey,
      _deletedAppointmentIds.toList(),
    );
  }

  Future<void> _syncCloudSnapshot() async {
    final deleted = await _accountApi.syncAccountData(
      customers: customers,
      appointments: appointments,
      deletedCustomerIds: _deletedCustomerIds,
      deletedAppointmentIds: _deletedAppointmentIds,
    );
    if (deleted.deletedCustomerIds.isNotEmpty ||
        deleted.deletedAppointmentIds.isNotEmpty) {
      customers.removeWhere(
        (customer) => deleted.deletedCustomerIds.contains(customer.id),
      );
      appointments.removeWhere(
        (appointment) =>
            deleted.deletedAppointmentIds.contains(appointment.id) ||
            deleted.deletedCustomerIds.contains(appointment.customerId),
      );
      if (mounted) setState(() {});
    }
    _deletedCustomerIds.clear();
    _deletedAppointmentIds.clear();
    await _persistLocal();
    if (mounted) setState(() => _cloudError = null);
  }

  void _setCloudError(String message) {
    if (mounted) setState(() => _cloudError = message);
  }

  Future<void> _retryCloudSync() async {
    await _saveTail;
    if (!mounted) return;
    setState(() => loaded = false);
    await _loadCloudData();
  }

  Widget _pageWithCloudStatus(Widget page) {
    if (_cloudError == null) return page;
    return Column(
      children: [
        MaterialBanner(
          content: Text(_cloudError!),
          actions: [
            TextButton(
              onPressed: () => unawaited(_retryCloudSync()),
              child: const Text('Yeniden dene'),
            ),
          ],
        ),
        Expanded(child: page),
      ],
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
    if (_loadError != null) {
      return Scaffold(body: Center(child: Text(_loadError!)));
    }
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
      CalendarPage(appointments: appointments, customerById: customerById),
      CustomersPage(
        customers: customers,
        onAdd: (customer) {
          setState(() {
            _deletedCustomerIds.remove(customer.id);
            customers.insert(0, customer);
          });
          unawaited(_save());
        },
        onDelete: (customer) {
          setState(() {
            customers.removeWhere((item) => item.id == customer.id);
            _deletedCustomerIds.add(customer.id);
            _deletedAppointmentIds.addAll(
              appointments
                  .where((item) => item.customerId == customer.id)
                  .map((item) => item.id),
            );
            appointments.removeWhere((item) => item.customerId == customer.id);
          });
          unawaited(_save());
        },
      ),
      AppointmentsPage(
        appointments: appointments,
        customerById: customerById,
        onDelete: (appointment) {
          setState(() {
            appointments.removeWhere((item) => item.id == appointment.id);
            _deletedAppointmentIds.add(appointment.id);
          });
          unawaited(_save());
        },
      ),
      CreateAppointmentPage(
        customers: customers,
        appointments: appointments,
        onAddCustomer: (customer) {
          setState(() {
            _deletedCustomerIds.remove(customer.id);
            customers.insert(0, customer);
          });
          unawaited(_save());
        },
        onSave: (appointment) {
          setState(() {
            _deletedAppointmentIds.remove(appointment.id);
            appointments.add(appointment);
            _index = 2;
          });
          unawaited(_save());
        },
      ),
      WhatsAppPage(
        appointments: appointments,
        customerById: customerById,
        cloudEnabled: widget.cloudEnabled,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
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
                                    Text(
                                      'CEREN',
                                      style: TextStyle(
                                        color: Color(0xFFE91E63),
                                        fontSize: 19,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 1.2,
                                      ),
                                    ),
                                    SizedBox(height: 2),
                                    Text(
                                      'Nail & Beauty Studio',
                                      style: TextStyle(
                                        color: Color(0xFF817680),
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 1.1,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        for (var i = 0; i < items.length; i++)
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 3,
                            ),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () => setState(() => _index = i),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 13,
                                ),
                                decoration: BoxDecoration(
                                  color: i == _index
                                      ? const Color(0xFFFCE4EC)
                                      : null,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      items[i].$1,
                                      size: 21,
                                      color: i == _index
                                          ? const Color(0xFFE91E63)
                                          : const Color(0xFF71676D),
                                    ),
                                    const SizedBox(width: 12),
                                    Text(
                                      items[i].$2,
                                      style: TextStyle(
                                        color: i == _index
                                            ? const Color(0xFFE91E63)
                                            : const Color(0xFF71676D),
                                        fontWeight: i == _index
                                            ? FontWeight.w700
                                            : FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        if (widget.cloudEnabled) ...[
                          const Spacer(),
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: TextButton.icon(
                              onPressed: () => FirebaseAuth.instance.signOut(),
                              icon: const Icon(Icons.logout),
                              label: const Text('Çıkış yap'),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                Expanded(child: _pageWithCloudStatus(pages[_index])),
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
            actions: [
              if (widget.cloudEnabled)
                IconButton(
                  onPressed: () => FirebaseAuth.instance.signOut(),
                  icon: const Icon(Icons.logout),
                  tooltip: 'Çıkış yap',
                ),
            ],
          ),
          body: _pageWithCloudStatus(pages[_index]),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: (value) => setState(() => _index = value),
            destinations: [
              for (final item in items)
                NavigationDestination(icon: Icon(item.$1), label: item.$2),
            ],
          ),
        );
      },
    );
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
  DateTime? selectedDate;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    month = DateTime(now.year, now.month);
  }

  String monthName(int month) {
    const names = [
      'Ocak',
      'Şubat',
      'Mart',
      'Nisan',
      'Mayıs',
      'Haziran',
      'Temmuz',
      'Ağustos',
      'Eylül',
      'Ekim',
      'Kasım',
      'Aralık',
    ];
    return names[month - 1];
  }

  bool sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  DateTime _appointmentStart(Appointment appointment) {
    final timeParts = appointment.time.split(':');
    final hour = int.tryParse(timeParts.first) ?? 0;
    final minute = timeParts.length > 1 ? int.tryParse(timeParts[1]) ?? 0 : 0;
    return DateTime(
      appointment.date.year,
      appointment.date.month,
      appointment.date.day,
      hour,
      minute,
    );
  }

  @override
  Widget build(BuildContext context) {
    final first = DateTime(month.year, month.month, 1);
    final leading = (first.weekday + 6) % 7;
    final dayCount = DateTime(month.year, month.month + 1, 0).day;

    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 900;
          final calendar = Column(
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
                    tooltip: 'Önceki ay',
                    onPressed: () => setState(
                      () => month = DateTime(month.year, month.month - 1),
                    ),
                    icon: const Icon(Icons.chevron_left),
                  ),
                  IconButton(
                    tooltip: 'Sonraki ay',
                    onPressed: () => setState(
                      () => month = DateTime(month.year, month.month + 1),
                    ),
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _buildCalendarCard(leading, dayCount),
            ],
          );
          final appointments = _buildAppointmentPanel(wide ? 580 : 380);

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1280),
                child: wide
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 6, child: calendar),
                          const SizedBox(width: 20),
                          Expanded(flex: 5, child: appointments),
                        ],
                      )
                    : Column(
                        children: [
                          calendar,
                          const SizedBox(height: 16),
                          appointments,
                        ],
                      ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildCalendarCard(int leading, int dayCount) {
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Color(0xFFF2E4E8)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                for (final name in [
                  'Pzt',
                  'Sal',
                  'Çar',
                  'Per',
                  'Cum',
                  'Cmt',
                  'Paz',
                ])
                  Expanded(
                    child: Center(
                      child: Text(
                        name,
                        style: const TextStyle(
                          color: Color(0xFF817680),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                mainAxisSpacing: 3,
                crossAxisSpacing: 3,
                childAspectRatio: 1.18,
              ),
              itemCount: leading + dayCount,
              itemBuilder: (context, index) {
                if (index < leading) return const SizedBox();
                final day = index - leading + 1;
                final date = DateTime(month.year, month.month, day);
                final dayAppointments = widget.appointments
                    .where((item) => sameDay(item.date, date))
                    .toList();
                final today = sameDay(date, DateTime.now());
                final selected =
                    selectedDate != null && sameDay(date, selectedDate!);
                return InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => setState(() => selectedDate = date),
                  child: Container(
                    decoration: BoxDecoration(
                      color: selected || today
                          ? const Color(0xFFFCE4EC)
                          : dayAppointments.isNotEmpty
                          ? const Color(0xFFFFF4F7)
                          : null,
                      borderRadius: BorderRadius.circular(10),
                      border: selected || today
                          ? Border.all(
                              color: selected
                                  ? const Color(0xFFE91E63)
                                  : const Color(0xFFF3A6BF),
                            )
                          : null,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '$day',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: selected || today
                                ? FontWeight.w800
                                : FontWeight.w600,
                            color: selected || today
                                ? const Color(0xFFE91E63)
                                : null,
                          ),
                        ),
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
          ],
        ),
      ),
    );
  }

  Widget _buildAppointmentPanel(double height) {
    final appointments = [...widget.appointments]
      ..sort((a, b) => _appointmentStart(a).compareTo(_appointmentStart(b)));
    final visibleAppointments = selectedDate == null
        ? appointments
        : appointments
              .where((item) => sameDay(item.date, selectedDate!))
              .toList();

    return SizedBox(
      height: height,
      child: Card(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: Color(0xFFF2E4E8)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Randevu Detayları',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          selectedDate == null
                              ? 'Tüm kayıtlı randevular'
                              : '${selectedDate!.day}.${selectedDate!.month}.${selectedDate!.year} tarihli randevular',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: const Color(0xFF817680)),
                        ),
                      ],
                    ),
                  ),
                  if (selectedDate != null)
                    TextButton(
                      onPressed: () => setState(() => selectedDate = null),
                      child: const Text('Tümünü gör'),
                    ),
                ],
              ),
              const Divider(height: 20),
              Expanded(
                child: visibleAppointments.isEmpty
                    ? Center(
                        child: Text(
                          selectedDate == null
                              ? 'Henüz randevu oluşturulmadı.'
                              : 'Bu gün için randevu bulunmuyor.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Color(0xFF817680)),
                        ),
                      )
                    : ListView.separated(
                        itemCount: visibleAppointments.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final appointment = visibleAppointments[index];
                          final customer = widget.customerById(
                            appointment.customerId,
                          );
                          return Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFF8FA),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: const Color(0xFFF5E7EB),
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 58,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFCE4EC),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    appointment.time,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: Color(0xFFE91E63),
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        customer?.name ?? 'Bilinmeyen müşteri',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        '${appointment.date.day}.${appointment.date.month}.${appointment.date.year}',
                                        style: const TextStyle(
                                          color: Color(0xFF817680),
                                        ),
                                      ),
                                      if (customer?.phone.isNotEmpty == true)
                                        Text(
                                          customer!.phone,
                                          style: const TextStyle(
                                            color: Color(0xFF817680),
                                          ),
                                        ),
                                      const SizedBox(height: 4),
                                      Text(appointment.service),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
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
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: () async {
                  final contact = await _pickDeviceContact(context);
                  if (contact == null) return;
                  name.text = contact.displayName ?? '';
                  if (contact.phones.isNotEmpty) {
                    phone.text = contact.phones.first.number;
                  } else if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Seçilen kişinin telefon numarası yok.'),
                      ),
                    );
                  }
                },
                icon: const Icon(Icons.contacts_outlined),
                label: const Text('Rehberden seç'),
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
            onPressed: () {
              if (name.text.trim().isEmpty || phone.text.trim().isEmpty) return;
              widget.onAdd(
                Customer(
                  id: DateTime.now().microsecondsSinceEpoch.toString(),
                  name: name.text.trim(),
                  phone: phone.text.trim(),
                ),
              );
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
        .where(
          (item) =>
              item.name.toLowerCase().contains(query.toLowerCase()) ||
              item.phone.contains(query),
        )
        .toList();

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Müşteri Listesi',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
                FilledButton.icon(
                  onPressed: _showCustomerDialog,
                  icon: const Icon(Icons.person_add_alt_1),
                  label: const Text('Müşteri Ekle'),
                ),
              ],
            ),
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
                                    : customer.name.characters.first
                                          .toUpperCase(),
                                style: const TextStyle(
                                  color: Color(0xFFE91E63),
                                  fontWeight: FontWeight.w800,
                                ),
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
      ..sort(
        (a, b) =>
            '${a.date.year}-${a.date.month}-${a.date.day}-${a.time}'.compareTo(
              '${b.date.year}-${b.date.month}-${b.date.day}-${b.time}',
            ),
      );

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Aktif Randevular',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
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
                              horizontal: 16,
                              vertical: 8,
                            ),
                            leading: CircleAvatar(
                              backgroundColor: const Color(0xFFFCE4EC),
                              child: Text(
                                item.time,
                                style: const TextStyle(
                                  color: Color(0xFFE91E63),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                ),
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
    required this.cloudEnabled,
  });

  final List<Appointment> appointments;
  final Customer? Function(String id) customerById;
  final bool cloudEnabled;

  @override
  State<WhatsAppPage> createState() => _WhatsAppPageState();
}

class _WhatsAppPageState extends State<WhatsAppPage> {
  final _accountApi = FirebaseAccountApi();
  bool _sending = false;

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

  Future<void> _send(Appointment appointment) async {
    if (!widget.cloudEnabled) {
      _showMessage(
        'WhatsApp gönderimi için Firebase sunucusu yapılandırılmalı.',
      );
      return;
    }
    final customer = widget.customerById(appointment.customerId);
    if (customer == null) {
      _showMessage('Müşteri bilgisi bulunamadı');
      return;
    }
    final recipient = normalizePhoneForWhatsApp(customer.phone);
    if (!RegExp(r'^[1-9]\d{7,14}$').hasMatch(recipient)) {
      _showMessage('Telefon numarasını ülke koduyla birlikte kontrol edin.');
      return;
    }

    setState(() => _sending = true);
    try {
      await _accountApi.sendAppointmentReminder(
        phone: recipient,
        customerName: customer.name,
        appointmentDate:
            '${appointment.date.day.toString().padLeft(2, '0')}.'
            '${appointment.date.month.toString().padLeft(2, '0')}.'
            '${appointment.date.year}',
        appointmentTime: appointment.time,
        service: appointment.service,
      );
      _showMessage('WhatsApp mesajı sunucuya gönderildi.');
    } on FirebaseFunctionsException catch (error) {
      _showMessage(error.message ?? 'WhatsApp sunucu isteği başarısız oldu.');
    } catch (error) {
      _showMessage('WhatsApp isteği tamamlanamadı: $error');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final upcoming = widget.appointments.where(_isUpcoming).toList()
      ..sort(
        (a, b) =>
            '${a.date.year}-${a.date.month}-${a.date.day}-${a.time}'.compareTo(
              '${b.date.year}-${b.date.month}-${b.date.day}-${b.time}',
            ),
      );

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
            Card(
              child: ListTile(
                leading: const Icon(
                  Icons.lock_outline,
                  color: Color(0xFFE91E63),
                ),
                title: const Text('Güvenli, manuel WhatsApp gönderimi'),
                subtitle: Text(
                  widget.cloudEnabled
                      ? 'Meta’da onaylanmış şablon kullanılır. Şablon değişkenleri sırayla: müşteri, tarih, saat, işlem.'
                      : 'Gönderim için Firebase Functions ve Meta şablon ayarları tamamlanmalı.',
                ),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: upcoming.isEmpty
                  ? const Center(child: Text('Yaklaşan randevu bulunmuyor'))
                  : ListView.separated(
                      itemCount: upcoming.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final appointment = upcoming[index];
                        final customer = widget.customerById(
                          appointment.customerId,
                        );
                        return Card(
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            leading: const CircleAvatar(
                              backgroundColor: Color(0xFFFCE4EC),
                              child: Icon(Icons.chat, color: Color(0xFFE91E63)),
                            ),
                            title: Text(customer?.name ?? 'Bilinmeyen müşteri'),
                            subtitle: Text(
                              '${appointment.date.day}.${appointment.date.month}.${appointment.date.year} • ${appointment.time}\n${appointment.service}\n${customer?.phone ?? ''}',
                            ),
                            isThreeLine: true,
                            trailing: FilledButton(
                              onPressed:
                                  _sending ||
                                      !widget.cloudEnabled ||
                                      customer == null
                                  ? null
                                  : () => _send(appointment),
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
  const TwentyFourHourTimePickerDialog({super.key, required this.initialTime});

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

  DateTime? _appointmentStart(Appointment appointment) {
    final parts = appointment.time.split(':');
    if (parts.length != 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null || hour > 23 || minute > 59) {
      return null;
    }
    return DateTime(
      appointment.date.year,
      appointment.date.month,
      appointment.date.day,
      hour,
      minute,
    );
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
                labelText: 'Ad soyad',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Telefon',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: () async {
                  final contact = await _pickDeviceContact(context);
                  if (contact == null) return;
                  name.text = contact.displayName ?? '';
                  if (contact.phones.isNotEmpty) {
                    phone.text = contact.phones.first.number;
                  } else if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Seçilen kişinin telefon numarası yok.'),
                      ),
                    );
                  }
                },
                icon: const Icon(Icons.contacts_outlined),
                label: const Text('Rehberden seç'),
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
              Text(
                'Randevu Oluştur',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
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
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        trailing: TextButton(
                          onPressed: _pickDate,
                          child: const Text('Seç'),
                        ),
                      ),
                      const Divider(),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.schedule),
                        title: const Text('Randevu saati'),
                        subtitle: Text(
                          timeText,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        trailing: TextButton(
                          onPressed: _pickTime,
                          child: const Text('Seç'),
                        ),
                      ),
                      const Divider(),
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Müşteri',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                          TextButton.icon(
                            onPressed: _addCustomerQuick,
                            icon: const Icon(Icons.person_add_alt),
                            label: const Text('Yeni müşteri'),
                          ),
                        ],
                      ),
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
                              child: Text(
                                '${customer.name} • ${customer.phone}',
                              ),
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
                                  'Müşteri ve yapılacak işlem zorunlu',
                                ),
                              ),
                            );
                            return;
                          }
                          final proposedStart = DateTime(
                            date.year,
                            date.month,
                            date.day,
                            time.hour,
                            time.minute,
                          );
                          final existingStarts = widget.appointments
                              .map(_appointmentStart)
                              .whereType<DateTime>();
                          if (!hasMinimumAppointmentGap(
                            proposedStart,
                            existingStarts,
                          )) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Randevular arasında en az 2 saat boşluk olmalı.',
                                ),
                              ),
                            );
                            return;
                          }
                          widget.onSave(
                            Appointment(
                              id: DateTime.now().microsecondsSinceEpoch
                                  .toString(),
                              date: date,
                              time: timeText,
                              customerId: customerId!,
                              service: service.text.trim(),
                            ),
                          );
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
