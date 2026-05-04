import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

void main() {
  runApp(const AutoServiceApp());
}

class ApiClient {
  ApiClient._();

  static final ApiClient instance = ApiClient._();

  String get _baseUrl {
    if (kIsWeb) return 'http://localhost:8000';
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'http://10.0.2.2:8000';
      default:
        return 'http://localhost:8000';
    }
  }

  Future<List<Map<String, dynamic>>> getServices() async {
    final response = await http.get(Uri.parse('$_baseUrl/services'));
    _ensureOk(response);
    return _toList(response);
  }

  Future<List<Map<String, dynamic>>> getCars() async {
    final response = await http.get(Uri.parse('$_baseUrl/cars'));
    _ensureOk(response);
    return _toList(response);
  }

  Future<Map<String, dynamic>> createCar({
    required String brand,
    required String number,
    String note = '',
  }) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/cars'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'brand': brand, 'number': number, 'note': note}),
    );
    _ensureOk(response, expectedStatusCode: 200, alternateStatusCode: 201);
    return _toMap(response);
  }

  Future<Map<String, dynamic>> updateCar({
    required int id,
    required String brand,
    required String number,
    String note = '',
  }) async {
    final response = await http.put(
      Uri.parse('$_baseUrl/cars/$id'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'brand': brand, 'number': number, 'note': note}),
    );
    _ensureOk(response);
    return _toMap(response);
  }

  Future<void> deleteCar(int id) async {
    final response = await http.delete(Uri.parse('$_baseUrl/cars/$id'));
    _ensureOk(response);
  }

  Future<List<Map<String, dynamic>>> getBookings() async {
    final response = await http.get(Uri.parse('$_baseUrl/bookings'));
    _ensureOk(response);
    return _toList(response);
  }

  Future<Map<String, dynamic>> createBooking({
    required int carId,
    required List<int> serviceIds,
    required String complaint,
  }) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/bookings'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'car_id': carId,
        'service_ids': serviceIds,
        'complaint': complaint,
      }),
    );
    _ensureOk(response, expectedStatusCode: 200, alternateStatusCode: 201);
    return _toMap(response);
  }

  Future<Map<String, dynamic>> updateBookingStatus({
    required int bookingId,
    required String status,
  }) async {
    final response = await http.patch(
      Uri.parse('$_baseUrl/bookings/$bookingId/status'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'status': status}),
    );
    _ensureOk(response);
    return _toMap(response);
  }

  void _ensureOk(
    http.Response response, {
    int expectedStatusCode = 200,
    int? alternateStatusCode,
  }) {
    final ok = response.statusCode == expectedStatusCode ||
        (alternateStatusCode != null && response.statusCode == alternateStatusCode);
    if (!ok) {
      throw Exception('API error ${response.statusCode}: ${response.body}');
    }
  }

  List<Map<String, dynamic>> _toList(http.Response response) {
    final decoded = jsonDecode(response.body) as List<dynamic>;
    return decoded.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Map<String, dynamic> _toMap(http.Response response) {
    return Map<String, dynamic>.from(jsonDecode(response.body) as Map);
  }
}

class DataProvider {
  static List<Map<String, dynamic>> garage = [];
  static List<Map<String, dynamic>> bookings = [];
  static List<Map<String, dynamic>> services = [];
}

bool isMechanicMode = false;

class AutoServiceApp extends StatelessWidget {
  const AutoServiceApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0F172A),
        primaryColor: Colors.orangeAccent,
        appBarTheme: const AppBarTheme(backgroundColor: Color(0xFF1E293B), elevation: 0),
        useMaterial3: true,
      ),
      home: const MainLayout(),
    );
  }
}

  class MainLayout extends StatefulWidget {
    const MainLayout({super.key});
    @override State<MainLayout> createState() => _MainLayoutState();
  }

class _MainLayoutState extends State<MainLayout> {
  int _selectedIndex = 0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _refreshFromApi();
  }

  Future<void> _refreshFromApi() async {
    try {
      final services = await ApiClient.instance.getServices();
      final cars = await ApiClient.instance.getCars();
      final bookings = await ApiClient.instance.getBookings();
      if (!mounted) return;
      setState(() {
        DataProvider.services = services;
        DataProvider.garage = cars;
        DataProvider.bookings = bookings;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось подключиться к API: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final screens = isMechanicMode
        ? [MechanicOrdersScreen(onUpdate: _refreshFromApi)]
        : [
            const ServiceListScreen(),
            BookingScreen(onBooked: _refreshFromApi),
            HistoryScreen(onUpdate: _refreshFromApi),
            GarageScreen(onUpdate: _refreshFromApi),
          ];

    return Scaffold(
      appBar: AppBar(
        title: Text(
          isMechanicMode ? 'ПАНЕЛЬ МЕХАНИКА' : 'АВТОСЕРВИС ТРИО',
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            color: Colors.orangeAccent,
            letterSpacing: 1.2,
          ),
        ),
        actions: [
          IconButton(
            onPressed: _refreshFromApi,
            icon: const Icon(Icons.refresh),
            tooltip: 'Обновить из базы',
          ),
          Switch(
            value: isMechanicMode,
            activeColor: Colors.orangeAccent,
            onChanged: (val) => setState(() {
              isMechanicMode = val;
              _selectedIndex = 0;
            }),
          ),
          const Padding(
            padding: EdgeInsets.only(right: 12),
            child: Icon(Icons.engineering, size: 20),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : screens[_selectedIndex < screens.length ? _selectedIndex : 0],
      bottomNavigationBar: isMechanicMode
          ? null
          : BottomNavigationBar(
              currentIndex: _selectedIndex,
              type: BottomNavigationBarType.fixed,
              backgroundColor: const Color(0xFF1E293B),
              selectedItemColor: Colors.orangeAccent,
              onTap: (i) => setState(() => _selectedIndex = i),
              items: const [
                BottomNavigationBarItem(icon: Icon(Icons.layers), label: 'Услуги'),
                BottomNavigationBarItem(icon: Icon(Icons.add_task), label: 'Запись'),
                BottomNavigationBarItem(icon: Icon(Icons.history), label: 'История'),
                BottomNavigationBarItem(icon: Icon(Icons.directions_car), label: 'Гараж'),
              ],
            ),
    );
  }
}

  // --- 1. СПИСОК УСЛУГ ---
  class ServiceListScreen extends StatelessWidget {
    const ServiceListScreen({super.key});
    @override
    Widget build(BuildContext context) {
      return ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: DataProvider.services.length,
        itemBuilder: (context, i) {
          final s = DataProvider.services[i];
          return Card(
            margin: const EdgeInsets.only(bottom: 10),
            color: Colors.white.withOpacity(0.03),
            child: ListTile(
              leading: const Icon(Icons.miscellaneous_services, color: Colors.orangeAccent),
              title: Text(s['name'], style: const TextStyle(fontSize: 14)),
              trailing: Text("${s['price']} ₽", style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
          );
        },
      );
    }
  }

  // --- 2. ЭКРАН ЗАПИСИ ---
  class BookingScreen extends StatefulWidget {
    final Future<void> Function() onBooked;
    const BookingScreen({super.key, required this.onBooked});
    @override State<BookingScreen> createState() => _BookingScreenState();
  }

  class _BookingScreenState extends State<BookingScreen> {
    final Map<String, bool> _selected = {};
    final _complaintController = TextEditingController();
    int? _selectedCarId;

    @override void initState() {
      super.initState();
      for (var s in DataProvider.services) { _selected[s['name']] = false; }
      if (DataProvider.garage.isNotEmpty) {
        _selectedCarId = DataProvider.garage[0]['id'] as int;
      }
    }

    Future<void> _sendRequest() async {
      final carId = _selectedCarId ??
          (DataProvider.garage.isNotEmpty ? DataProvider.garage[0]['id'] as int : null);
      if (carId == null) return;
      final chosenServices =
          DataProvider.services.where((s) => _selected[s['name']] ?? false).toList();
      if (chosenServices.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Выберите хотя бы одну услугу")));
        return;
      }
      try {
        await ApiClient.instance.createBooking(
          carId: carId,
          serviceIds: chosenServices.map((s) => s['id'] as int).toList(),
          complaint: _complaintController.text,
        );
        await widget.onBooked();
        _complaintController.clear();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Заявка сохранена в базе')),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка записи: $e')),
        );
      }
    }

    @override
    Widget build(BuildContext context) {
      final selectedCarId = (_selectedCarId != null &&
              DataProvider.garage.any((c) => c['id'] == _selectedCarId))
          ? _selectedCarId
          : (DataProvider.garage.isNotEmpty ? DataProvider.garage[0]['id'] as int : null);

      return SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text("Выберите автомобиль", style: TextStyle(color: Colors.grey, fontSize: 12)),
          DropdownButton<int>(
            value: selectedCarId,
            isExpanded: true,
            items: DataProvider.garage
                .map((c) => DropdownMenuItem<int>(
                      value: c['id'] as int,
                      child: Text("${c['brand']} (${c['number']})"),
                    ))
                .toList(),
            onChanged: (v) => setState(() => _selectedCarId = v),
          ),
          const SizedBox(height: 15),
          const Text("Выберите необходимые услуги", style: TextStyle(color: Colors.grey, fontSize: 12)),
          ...DataProvider.services.map((s) => CheckboxListTile(
            title: Text(s['name'], style: const TextStyle(fontSize: 13)),
            subtitle: Text("${s['price']} ₽", style: const TextStyle(color: Colors.orangeAccent)),
            value: _selected[s['name']],
            onChanged: (v) => setState(() => _selected[s['name']] = v!),
            activeColor: Colors.orangeAccent, dense: true,
          )),
          const SizedBox(height: 10),
          TextField(
            controller: _complaintController,
            decoration: const InputDecoration(hintText: "На что жалуетесь? (симптомы)", border: OutlineInputBorder()),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _sendRequest,
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orangeAccent, minimumSize: const Size(double.infinity, 50)),
            child: const Text("ОТПРАВИТЬ ЗАЯВКУ", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          )
        ]),
      );
    }
  }

  // --- 3. ИСТОРИЯ ---
  class HistoryScreen extends StatelessWidget {
    final Future<void> Function() onUpdate;
    const HistoryScreen({super.key, required this.onUpdate});
    @override
    Widget build(BuildContext context) {
      return ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: DataProvider.bookings.length,
        itemBuilder: (context, i) {
          final b = DataProvider.bookings[DataProvider.bookings.length - 1 - i];
          return Card(
            child: ListTile(
              title: Text("${b['car']} | ${b['num']}"),
              subtitle: Text("${b['services']}\n${b['date']}"),
              trailing: Text(b['status'], style: const TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.bold)),
            ),
          );
        },
      );
    }
  }

  // --- 4. ГАРАЖ ---
  class GarageScreen extends StatefulWidget {
    final Future<void> Function() onUpdate;
    const GarageScreen({super.key, required this.onUpdate});
    @override State<GarageScreen> createState() => _GarageScreenState();
  }

  class _GarageScreenState extends State<GarageScreen> {
    void _editCar(int i) {
      final car = DataProvider.garage[i];
      final bController = TextEditingController(text: car['brand'] as String);
      final nController = TextEditingController(text: car['number'] as String);
      final noteController = TextEditingController(text: car['note'] as String? ?? '');
      
      showDialog(context: context, builder: (c) => AlertDialog(
        title: const Text("Данные автомобиля", style: TextStyle(color: Colors.orangeAccent)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Align(alignment: Alignment.centerLeft, child: Text("Марка и модель", style: TextStyle(fontSize: 12, color: Colors.grey))),
          TextField(controller: bController, decoration: const InputDecoration(hintText: "Напр: Toyota Camry")),
          const SizedBox(height: 15),
          const Align(alignment: Alignment.centerLeft, child: Text("Государственный номер", style: TextStyle(fontSize: 12, color: Colors.grey))),
          TextField(
            controller: nController,
            textCapitalization: TextCapitalization.characters,
            inputFormatters: [UpperCaseTextFormatter()],
            decoration: const InputDecoration(hintText: "X 000 XX"),
          ),
          const SizedBox(height: 15),
          const Align(alignment: Alignment.centerLeft, child: Text("Заметка", style: TextStyle(fontSize: 12, color: Colors.grey))),
          TextField(controller: noteController),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text("ОТМЕНА")),
          ElevatedButton(
            onPressed: () async {
              await ApiClient.instance.updateCar(
                id: car['id'] as int,
                brand: bController.text,
                number: nController.text,
                note: noteController.text,
              );
              await widget.onUpdate();
              if (!context.mounted) return;
              Navigator.pop(c);
            },
            child: const Text("СОХРАНИТЬ"),
          ),
        ],
      ));
    }

    void _confirmDelete(int i) {
      showDialog(context: context, builder: (c) => AlertDialog(
        title: const Text("Удалить автомобиль?"),
        content: Text("Вы действительно хотите удалить ${DataProvider.garage[i]['brand']} из гаража?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text("ОТМЕНА")),
          TextButton(
            onPressed: () async {
              await ApiClient.instance.deleteCar(DataProvider.garage[i]['id'] as int);
              await widget.onUpdate();
              if (!context.mounted) return;
              Navigator.pop(c);
            },
            child: const Text("УДАЛИТЬ", style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ));
    }

    void _showNote(int i) {
      final noteController = TextEditingController(text: DataProvider.garage[i]['note'] as String? ?? '');
      showDialog(context: context, builder: (c) => AlertDialog(
        title: const Text("Блокнот автомобиля"),
        content: TextField(
          controller: noteController,
          maxLines: 5,
          decoration: const InputDecoration(border: OutlineInputBorder(), hintText: "Заметки по ТО, запчастям..."),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              final car = DataProvider.garage[i];
              await ApiClient.instance.updateCar(
                id: car['id'] as int,
                brand: car['brand'] as String,
                number: car['number'] as String,
                note: noteController.text,
              );
              await widget.onUpdate();
              if (!context.mounted) return;
              Navigator.pop(c);
            },
            child: const Text("СОХРАНИТЬ"),
          )
        ],
      ));
    }

    @override
    Widget build(BuildContext context) {
      return Column(children: [
        Expanded(child: ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: DataProvider.garage.length,
          itemBuilder: (context, i) => Card(
            child: ListTile(
              leading: const Icon(Icons.directions_car, color: Colors.orangeAccent),
              title: Text(DataProvider.garage[i]['brand'], style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text("${DataProvider.garage[i]['number']}\nТраты: ${DataProvider.garage[i]['total_spent']} ₽"),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(icon: const Icon(Icons.menu_book, color: Colors.blueAccent), onPressed: () => _showNote(i)),
                IconButton(icon: const Icon(Icons.edit, size: 18), onPressed: () => _editCar(i)),
                IconButton(icon: const Icon(Icons.delete, color: Colors.redAccent, size: 18), onPressed: () => _confirmDelete(i)),
              ]),
            ),
          ),
        )),
        Padding(padding: const EdgeInsets.all(20), child: ElevatedButton.icon(
          icon: const Icon(Icons.add, color: Colors.black),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.orangeAccent, minimumSize: const Size(double.infinity, 50)),
          onPressed: () async {
            try {
              await ApiClient.instance.createCar(
                brand: 'Новое авто',
                number: 'X 000 XX',
              );
              await widget.onUpdate();
              if (!mounted) return;
              _editCar(DataProvider.garage.length - 1);
            } catch (e) {
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Ошибка добавления авто: $e')),
              );
            }
          },
          label: const Text("ДОБАВИТЬ В ГАРАЖ", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold))
        ))
      ]);
    }
  }

  class UpperCaseTextFormatter extends TextInputFormatter {
    @override
    TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
      return newValue.copyWith(text: newValue.text.toUpperCase());
    }
  }

  // --- 5. ЭКРАН МЕХАНИКА ---
  class MechanicOrdersScreen extends StatefulWidget {
    final Future<void> Function() onUpdate;
    const MechanicOrdersScreen({super.key, required this.onUpdate});
    @override State<MechanicOrdersScreen> createState() => _MechanicOrdersScreenState();
  }

  class _MechanicOrdersScreenState extends State<MechanicOrdersScreen> {
    @override
    Widget build(BuildContext context) {
      return DataProvider.bookings.isEmpty 
        ? const Center(child: Text("Нет новых заявок"))
        : ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: DataProvider.bookings.length,
            itemBuilder: (context, i) {
              final b = DataProvider.bookings[i];
              return Card(
                color: const Color(0xFF1E2235),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text("${b['car']} (${b['num']})", style: const TextStyle(fontWeight: FontWeight.bold)),
                    Text("Работы: ${b['services']}", style: const TextStyle(color: Colors.orangeAccent, fontSize: 13)),
                    if(b['complaint'].isNotEmpty) Container(
                      padding: const EdgeInsets.all(8), margin: const EdgeInsets.symmetric(vertical: 8),
                      color: Colors.black26, width: double.infinity,
                      child: Text("Симптомы: ${b['complaint']}", style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic)),
                    ),
                    const Divider(),
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      Text("Статус: ${b['status']}"),
                      if(b['status'] != 'Готово') ElevatedButton(
                        onPressed: () async {
                          final newStatus = b['status'] == 'Ожидание' ? 'В работе' : 'Готово';
                          await ApiClient.instance.updateBookingStatus(
                            bookingId: b['id'] as int,
                            status: newStatus,
                          );
                          await widget.onUpdate();
                        },
                        child: Text(b['status'] == 'Ожидание' ? "ПРИНЯТЬ" : "ЗАВЕРШИТЬ"),
                      ) else const Icon(Icons.check_circle, color: Colors.green)
                    ])
                  ]),
                ),
              );
            },
          );
    }
  }