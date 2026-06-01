import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await AuthSession.load();
    runApp(const AutoServiceApp());
  } catch (e, stack) {
    runApp(StartupErrorApp(message: '$e'));
    debugPrintStack(stackTrace: stack);
  }
}

/// Показывается, если приложение не смогло стартовать.
class StartupErrorApp extends StatelessWidget {
  const StartupErrorApp({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Ошибка запуска',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Text(message, style: const TextStyle(fontSize: 14)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// На Web — узкая «телефонная» колонка по центру экрана.
class MobileWebShell extends StatelessWidget {
  const MobileWebShell({super.key, required this.child});

  final Widget child;

  static const double phoneWidth = 420;

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb) return child;

    return ColoredBox(
      color: const Color(0xFF111827),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Center(
            child: SizedBox(
              width: phoneWidth,
              height: constraints.maxHeight,
              child: Material(
                clipBehavior: Clip.antiAlias,
                child: child,
              ),
            ),
          );
        },
      ),
    );
  }
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

  Map<String, String> get _authHeaders {
    final headers = <String, String>{'Content-Type': 'application/json'};
    final token = AuthSession.token;
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  Future<List<Map<String, dynamic>>> getServices() async {
    final response = await http.get(Uri.parse('$_baseUrl/services'));
    _ensureOk(response);
    return _toList(response);
  }

  Future<List<Map<String, dynamic>>> getCars() async {
    final response = await http.get(
      Uri.parse('$_baseUrl/cars'),
      headers: _authHeaders,
    );
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
      headers: _authHeaders,
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
      headers: _authHeaders,
      body: jsonEncode({'brand': brand, 'number': number, 'note': note}),
    );
    _ensureOk(response);
    return _toMap(response);
  }

  Future<void> deleteCar(int id) async {
    final response = await http.delete(
      Uri.parse('$_baseUrl/cars/$id'),
      headers: _authHeaders,
    );
    _ensureOk(response);
  }

  Future<List<Map<String, dynamic>>> getBookings() async {
    final response = await http.get(
      Uri.parse('$_baseUrl/bookings'),
      headers: _authHeaders,
    );
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
      headers: _authHeaders,
      body: jsonEncode({
        'car_id': carId,
        'service_ids': serviceIds,
        'complaint': complaint,
      }),
    );
    _ensureOk(response, expectedStatusCode: 200, alternateStatusCode: 201);
    return _toMap(response);
  }

  Future<Map<String, dynamic>> register({
    required String email,
    required String password,
  }) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'password': password}),
    );
    _ensureOk(response, expectedStatusCode: 201, alternateStatusCode: 200);
    return _toMap(response);
  }

  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'password': password}),
    );
    _ensureOk(response, expectedStatusCode: 200);
    return _toMap(response);
  }

  Future<Map<String, dynamic>> updateBookingStatus({
    required int bookingId,
    required String status,
  }) async {
    final response = await http.patch(
      Uri.parse('$_baseUrl/bookings/$bookingId/status'),
      headers: _authHeaders,
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
      throw Exception(_parseError(response));
    }
  }

  String _parseError(http.Response response) {
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final detail = body['detail'];
      if (detail is String) return detail;
      if (detail is List && detail.isNotEmpty) {
        final first = detail.first;
        if (first is Map && first['msg'] != null) {
          return first['msg'].toString();
        }
        return first.toString();
      }
    } catch (_) {}
    return 'Ошибка сервера (${response.statusCode})';
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

class AuthSession {
  static int? userId;
  static String? email;
  static String? role;
  static String? token;

  static bool get isLoggedIn =>
      email != null && role != null && token != null && token!.isNotEmpty;
  static bool get isMechanic => role == 'mechanic';
  static bool get isClient => role == 'client';

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    userId = prefs.getInt('user_id');
    email = prefs.getString('email');
    role = prefs.getString('role');
    token = prefs.getString('access_token');
  }

  static Future<void> saveFromApi(Map<String, dynamic> user) async {
    userId = user['id'] as int;
    email = user['email'] as String;
    role = user['role'] as String;
    token = user['access_token'] as String?;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('user_id', userId!);
    await prefs.setString('email', email!);
    await prefs.setString('role', role!);
    if (token != null) {
      await prefs.setString('access_token', token!);
    }
  }

  static Future<void> clear() async {
    userId = null;
    email = null;
    role = null;
    token = null;
    DataProvider.garage = [];
    DataProvider.bookings = [];
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('user_id');
    await prefs.remove('email');
    await prefs.remove('role');
    await prefs.remove('access_token');
  }
}

/// Цвета приложения.
class AppColors {
  static const text = Color(0xFFF8FAFC);
  static const textMuted = Color(0xFFCBD5E1);
  static const hint = Color(0xFF94A3B8);
  static const fieldFill = Color(0xFF334155);
  static const accent = Color(0xFFFF9800);
  static const background = Color(0xFF0F172A);
  static const surface = Color(0xFF1E293B);
  // Экран входа — светлая тема (надёжно на Web)
  static const authBg = Color(0xFFF1F5F9);
  static const authText = Color(0xFF0F172A);
  static const authMuted = Color(0xFF475569);
  static const authFieldBg = Color(0xFFFFFFFF);
  static const authBorder = Color(0xFFCBD5E1);
}

/// Системный шрифт (без загрузки из интернета — иначе на Web текст не виден).
TextStyle appFont({
  double size = 16,
  Color color = AppColors.text,
  FontWeight weight = FontWeight.normal,
}) {
  return TextStyle(
    fontSize: size,
    color: color,
    fontWeight: weight,
    fontFamily: kIsWeb ? 'Segoe UI' : null,
    fontFamilyFallback: const ['Arial', 'Helvetica', 'sans-serif'],
  );
}

TextStyle authFont({
  double size = 16,
  Color color = AppColors.authText,
  FontWeight weight = FontWeight.normal,
}) {
  return TextStyle(
    fontSize: size,
    color: color,
    fontWeight: weight,
    fontFamily: kIsWeb ? 'Segoe UI' : null,
    fontFamilyFallback: const ['Arial', 'Helvetica', 'sans-serif'],
  );
}

ThemeData buildAppTheme() {
  final base = ThemeData(
    useMaterial3: false,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: AppColors.background,
    primaryColor: AppColors.accent,
    fontFamily: kIsWeb ? 'Segoe UI' : null,
    colorScheme: const ColorScheme.dark(
      primary: AppColors.accent,
      onPrimary: Color(0xFF000000),
      surface: AppColors.surface,
      onSurface: AppColors.text,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.surface,
      elevation: 0,
      foregroundColor: AppColors.text,
      titleTextStyle: appFont(size: 16, color: AppColors.accent, weight: FontWeight.bold),
    ),
    textTheme: ThemeData.dark().textTheme.apply(
      bodyColor: AppColors.text,
      displayColor: AppColors.text,
      fontFamily: kIsWeb ? 'Segoe UI' : null,
      fontFamilyFallback: const ['Arial', 'Helvetica', 'sans-serif'],
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.fieldFill,
      labelStyle: appFont(size: 16, color: AppColors.hint),
      hintStyle: appFont(size: 16, color: AppColors.hint),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFF64748B)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.accent, width: 2),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.accent,
        foregroundColor: Colors.black,
      ),
    ),
  );
  return base;
}

/// Светлая тема только для экрана авторизации (Flutter Web).
ThemeData buildAuthTheme() {
  final inputBorder = OutlineInputBorder(
    borderRadius: BorderRadius.circular(8),
    borderSide: const BorderSide(color: AppColors.authBorder, width: 1.5),
  );

  return ThemeData(
    useMaterial3: false,
    brightness: Brightness.light,
    scaffoldBackgroundColor: AppColors.authBg,
    primaryColor: AppColors.accent,
    fontFamily: kIsWeb ? 'Segoe UI' : null,
    colorScheme: const ColorScheme.light(
      primary: AppColors.accent,
      onPrimary: Color(0xFF000000),
      surface: AppColors.authFieldBg,
      onSurface: AppColors.authText,
    ),
    textTheme: ThemeData.light().textTheme.apply(
      bodyColor: AppColors.authText,
      displayColor: AppColors.authText,
      fontFamily: kIsWeb ? 'Segoe UI' : null,
      fontFamilyFallback: const ['Arial', 'Helvetica', 'sans-serif'],
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.authFieldBg,
      floatingLabelBehavior: FloatingLabelBehavior.never,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      hintStyle: authFont(size: 16, color: AppColors.authMuted),
      enabledBorder: inputBorder,
      focusedBorder: inputBorder.copyWith(
        borderSide: const BorderSide(color: AppColors.accent, width: 2),
      ),
      errorBorder: inputBorder.copyWith(
        borderSide: const BorderSide(color: Colors.red),
      ),
    ),
    textSelectionTheme: const TextSelectionThemeData(
      cursorColor: AppColors.accent,
      selectionColor: Color(0x44FF9800),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.accent,
        foregroundColor: Colors.black,
        textStyle: authFont(size: 16, weight: FontWeight.bold, color: Colors.black),
      ),
    ),
  );
}

class AutoServiceApp extends StatelessWidget {
  const AutoServiceApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      builder: (context, child) {
        return MobileWebShell(child: child ?? const SizedBox.shrink());
      },
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  @override
  Widget build(BuildContext context) {
    if (AuthSession.isLoggedIn) {
      return MainLayout(onLogout: _handleLogout);
    }
    return AuthScreen(onAuthenticated: () => setState(() {}));
  }

  Future<void> _handleLogout() async {
    await AuthSession.clear();
    if (mounted) setState(() {});
  }
}

enum AuthMode { client, mechanic }

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, required this.onAuthenticated});

  final VoidCallback onAuthenticated;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  AuthMode _mode = AuthMode.client;
  bool _isRegister = false;
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _isSubmitting = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);
    try {
      final email = _emailController.text.trim().toLowerCase();
      final password = _passwordController.text;
      final Map<String, dynamic> user;

      if (_mode == AuthMode.client && _isRegister) {
        user = await ApiClient.instance.register(email: email, password: password);
      } else {
        user = await ApiClient.instance.login(email: email, password: password);
        final role = user['role'] as String? ?? 'client';
        if (_mode == AuthMode.mechanic && role != 'mechanic') {
          throw Exception('Этот аккаунт не является механиком');
        }
        if (_mode == AuthMode.client && role == 'mechanic') {
          throw Exception('Войдите через раздел «Механик»');
        }
      }

      await AuthSession.saveFromApi(user);
      if (!mounted) return;
      widget.onAuthenticated();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Widget _fieldLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(text, style: authFont(size: 14, weight: FontWeight.w600)),
    );
  }

  InputDecoration _fieldDecoration({
    required String hint,
    Widget? suffix,
  }) {
    return InputDecoration(
      hintText: hint,
      suffixIcon: suffix,
    );
  }

  Widget _roleCard({
    required AuthMode mode,
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    final selected = _mode == mode;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() {
          _mode = mode;
          _isRegister = false;
        }),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFFFFE0B2) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? AppColors.accent : AppColors.authBorder,
              width: selected ? 2.5 : 1,
            ),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                color: selected ? AppColors.accent : AppColors.authMuted,
                size: 36,
              ),
              const SizedBox(height: 8),
              Text(
                title,
                style: authFont(
                  size: 16,
                  weight: FontWeight.bold,
                  color: selected ? AppColors.accent : AppColors.authText,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: authFont(size: 11, color: AppColors.authMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _modeTab({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: selected ? AppColors.accent : Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? AppColors.accent : AppColors.authBorder,
              width: 1.5,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: authFont(
              size: 15,
              weight: FontWeight.w600,
              color: selected ? Colors.black : AppColors.authText,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isClient = _mode == AuthMode.client;
    final showConfirm = isClient && _isRegister;
    final actionLabel = isClient
        ? (_isRegister ? 'Зарегистрироваться' : 'Войти')
        : 'Войти как механик';

    final fieldStyle = authFont(size: 18, color: AppColors.authText, weight: FontWeight.w500);

    return Theme(
      data: buildAuthTheme(),
      child: Scaffold(
        backgroundColor: AppColors.authBg,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'АВТОСЕРВИС ТРИО',
                        textAlign: TextAlign.center,
                        style: authFont(size: 26, weight: FontWeight.bold, color: AppColors.accent),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        isClient ? 'Вход для клиентов' : 'Вход для механиков',
                        textAlign: TextAlign.center,
                        style: authFont(size: 16, color: AppColors.authMuted),
                      ),
                      const SizedBox(height: 28),
                      Row(
                        children: [
                          _roleCard(
                            mode: AuthMode.client,
                            icon: Icons.person,
                            title: 'Клиент',
                            subtitle: 'Регистрация и запись',
                          ),
                          const SizedBox(width: 12),
                          _roleCard(
                            mode: AuthMode.mechanic,
                            icon: Icons.engineering,
                            title: 'Механик',
                            subtitle: 'Панель заявок',
                          ),
                        ],
                      ),
                      if (isClient) ...[
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            _modeTab(
                              label: 'Вход',
                              selected: !_isRegister,
                              onTap: () => setState(() => _isRegister = false),
                            ),
                            const SizedBox(width: 8),
                            _modeTab(
                              label: 'Регистрация',
                              selected: _isRegister,
                              onTap: () => setState(() => _isRegister = true),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 24),
                      _fieldLabel('Email'),
                      TextFormField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        autocorrect: false,
                        style: fieldStyle,
                        cursorColor: AppColors.accent,
                        decoration: _fieldDecoration(hint: 'example@mail.ru'),
                        validator: (value) {
                          final text = value?.trim() ?? '';
                          if (text.isEmpty) return 'Введите email';
                          if (!text.contains('@') || !text.contains('.')) {
                            return 'Некорректный email';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      _fieldLabel('Пароль'),
                      TextFormField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        style: fieldStyle,
                        cursorColor: AppColors.accent,
                        decoration: _fieldDecoration(
                          hint: isClient && _isRegister ? 'Не короче 6 символов' : 'Введите пароль',
                          suffix: IconButton(
                            onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                            icon: Icon(
                              _obscurePassword ? Icons.visibility : Icons.visibility_off,
                              color: AppColors.authMuted,
                            ),
                          ),
                        ),
                        validator: (value) {
                          if ((value ?? '').isEmpty) return 'Введите пароль';
                          if (isClient && _isRegister && (value ?? '').length < 6) {
                            return 'Пароль не короче 6 символов';
                          }
                          return null;
                        },
                      ),
                      if (showConfirm) ...[
                        const SizedBox(height: 16),
                        _fieldLabel('Повторите пароль'),
                        TextFormField(
                          controller: _confirmController,
                          obscureText: _obscurePassword,
                          style: fieldStyle,
                          cursorColor: AppColors.accent,
                          decoration: _fieldDecoration(hint: 'Ещё раз пароль'),
                          validator: (value) {
                            if (value != _passwordController.text) {
                              return 'Пароли не совпадают';
                            }
                            return null;
                          },
                        ),
                      ],
                      if (!isClient) ...[
                        const SizedBox(height: 12),
                        Text(
                          'Тестовый вход: mechanic@trio.ru / mechanic123',
                          textAlign: TextAlign.center,
                          style: authFont(size: 12, color: AppColors.authMuted),
                        ),
                      ],
                      const SizedBox(height: 28),
                      SizedBox(
                        height: 52,
                        child: ElevatedButton(
                          onPressed: _isSubmitting ? null : _submit,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.accent,
                            foregroundColor: Colors.black,
                            disabledBackgroundColor: const Color(0x99FF9800),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: _isSubmitting
                              ? const SizedBox(
                                  height: 24,
                                  width: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: Colors.black,
                                  ),
                                )
                              : Text(
                                  actionLabel,
                                  style: authFont(
                                    size: 17,
                                    weight: FontWeight.bold,
                                    color: Colors.black,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key, required this.onLogout, required this.onRefresh});

  final Future<void> Function() onLogout;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final bookingsCount = DataProvider.bookings.length;
    final carsCount = DataProvider.garage.length;
    final totalSpent = DataProvider.garage.fold<int>(
      0,
      (sum, car) => sum + (car['total_spent'] as int? ?? 0),
    );

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Card(
          color: const Color(0xFF1E293B),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.account_circle, color: Colors.orangeAccent, size: 48),
                    SizedBox(width: 12),
                    Text(
                      'Личный кабинет',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text('Email: ${AuthSession.email ?? ''}', style: const TextStyle(fontSize: 15)),
                const SizedBox(height: 6),
                const Text('Роль: Клиент', style: TextStyle(color: Colors.white54)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        _statTile(Icons.directions_car, 'Автомобилей в гараже', '$carsCount'),
        _statTile(Icons.history, 'Заявок в истории', '$bookingsCount'),
        _statTile(Icons.payments, 'Сумма обслуживания', '$totalSpent ₽'),
        const SizedBox(height: 24),
        OutlinedButton.icon(
          onPressed: () async {
            await onRefresh();
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Данные обновлены')),
            );
          },
          icon: const Icon(Icons.refresh),
          label: const Text('Обновить данные'),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.orangeAccent,
            side: const BorderSide(color: Colors.orangeAccent),
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
        const SizedBox(height: 12),
        ElevatedButton.icon(
          onPressed: () async {
            await onLogout();
          },
          icon: const Icon(Icons.logout, color: Colors.black),
          label: const Text('Выйти из аккаунта', style: TextStyle(color: Colors.black)),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.redAccent,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
      ],
    );
  }

  Widget _statTile(IconData icon, String label, String value) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: Colors.white.withOpacity(0.03),
      child: ListTile(
        leading: Icon(icon, color: Colors.orangeAccent),
        title: Text(label, style: const TextStyle(fontSize: 14)),
        trailing: Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
      ),
    );
  }
}

class MainLayout extends StatefulWidget {
  const MainLayout({super.key, required this.onLogout});

  final Future<void> Function() onLogout;

  @override
  State<MainLayout> createState() => _MainLayoutState();
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
      if (AuthSession.isMechanic) {
        final bookings = await ApiClient.instance.getBookings();
        if (!mounted) return;
        setState(() {
          DataProvider.bookings = bookings;
          DataProvider.garage = [];
          DataProvider.services = [];
          _isLoading = false;
        });
      } else {
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
      }
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
    final isMechanic = AuthSession.isMechanic;
    final screens = isMechanic
        ? [MechanicOrdersScreen(onUpdate: _refreshFromApi)]
        : [
            const ServiceListScreen(),
            BookingScreen(onBooked: _refreshFromApi),
            HistoryScreen(onUpdate: _refreshFromApi),
            GarageScreen(onUpdate: _refreshFromApi),
            ProfileScreen(onLogout: widget.onLogout, onRefresh: _refreshFromApi),
          ];

    return Scaffold(
      appBar: AppBar(
        title: Text(
          isMechanic ? 'ПАНЕЛЬ МЕХАНИКА' : 'АВТОСЕРВИС ТРИО',
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
          if (isMechanic)
            IconButton(
              onPressed: widget.onLogout,
              icon: const Icon(Icons.logout),
              tooltip: 'Выйти',
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : screens[_selectedIndex < screens.length ? _selectedIndex : 0],
      bottomNavigationBar: isMechanic
          ? null
          : BottomNavigationBar(
              currentIndex: _selectedIndex,
              type: BottomNavigationBarType.fixed,
              backgroundColor: const Color(0xFF1E293B),
              selectedItemColor: Colors.orangeAccent,
              unselectedItemColor: Colors.white54,
              onTap: (i) => setState(() => _selectedIndex = i),
              items: const [
                BottomNavigationBarItem(icon: Icon(Icons.layers), label: 'Услуги'),
                BottomNavigationBarItem(icon: Icon(Icons.add_task), label: 'Запись'),
                BottomNavigationBarItem(icon: Icon(Icons.history), label: 'История'),
                BottomNavigationBarItem(icon: Icon(Icons.directions_car), label: 'Гараж'),
                BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Профиль'),
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
                    Text(
                      "Клиент: ${b['client_email'] ?? '—'}",
                      style: const TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      "Подано: ${b['date'] ?? ''}",
                      style: const TextStyle(fontSize: 12, color: Colors.white54),
                    ),
                    const SizedBox(height: 6),
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