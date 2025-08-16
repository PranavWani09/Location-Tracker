import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class Config {
  static const String apiBaseUrl = 'https://test.erpkey.in';
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _storage = const FlutterSecureStorage();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    _checkLoginSession();
  }

  Future<void> _checkLoginSession() async {
    try {
      final String? apiKey = await _storage.read(key: 'api_key');
      final String? apiSecret = await _storage.read(key: 'api_secret');
      print(
          "🔍 Checking login session - api_key: $apiKey, api_secret: $apiSecret");
      if (apiKey != null && apiKey.isNotEmpty && apiSecret != null &&
          apiSecret.isNotEmpty) {
        _navigateToHome();
      }
    } catch (e, stack) {
      print("🔥 Error checking login session: $e");
      print("🔥 Stack: $stack");
    }
  }

  Future<void> _login() async {
    final String username = _usernameController.text.trim();
    final String password = _passwordController.text.trim();

    if (username.isEmpty || password.isEmpty) {
      _showError('Username and password are required');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final response = await http.post(
        Uri.parse('${Config
            .apiBaseUrl}/api/method/location_tracker.custom_pyfile.login_master.login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'usr': username, 'pwd': password}),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        print("🌐 Login Response Body: $data");
        final String? apiSecret = data['key_details']?['api_secret']
            ?.toString();
        final String? apiKey = data['key_details']?['api_key']?.toString();
        final String? fullName = data['full_name']?.toString();

        print(
            "🔑 Extracted - api_key: $apiKey, api_secret: $apiSecret, full_name: $fullName");

        if (apiSecret != null && apiKey != null) {
          await _storage.deleteAll();
          await _storage.write(key: 'api_secret', value: apiSecret);
          await _storage.write(key: 'api_key', value: apiKey);
          await _storage.write(key: 'username', value: username);
          await _storage.write(key: 'sharing_enabled', value: 'true');
          if (fullName != null) {
            await _storage.write(key: 'full_name', value: fullName);
          }

          print(
              "💾 Stored in secure storage - api_key: $apiKey, api_secret: $apiSecret, username: $username, full_name: $fullName, sharing_enabled: true");

          _navigateToHome();
        } else {
          _showError('Missing credentials in response');
          print("❌ Missing key_details in response");
        }
      } else {
        print("❌ Login Failed - Status: ${response.statusCode}, Body: ${response
            .body}");
        _showError('Invalid credentials or server error');
      }
    } catch (e, stack) {
      print("🔥 Login Error: $e");
      print("🔥 Stack: $stack");
      _showError('Check your connection or try again');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _navigateToHome() {
    Navigator.pushReplacementNamed(context, '/home');
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF1E3C72), Color(0xFF2A5298)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 25.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Title & subtitle
                  const Text(
                    "Welcome Back!",
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    "Login to continue",
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.white70,
                    ),
                  ),

                  const SizedBox(height: 40),

                  // Login Card
                  Container(
                    padding: const EdgeInsets.all(25),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.15),
                          blurRadius: 15,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        TextField(
                          controller: _usernameController,
                          decoration: InputDecoration(
                            labelText: 'Username',
                            prefixIcon: const Icon(
                                Icons.person, color: Colors.deepPurple),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        TextField(
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          decoration: InputDecoration(
                            labelText: 'Password',
                            prefixIcon: const Icon(
                                Icons.lock, color: Colors.deepPurple),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePassword ? Icons.visibility : Icons
                                    .visibility_off,
                                color: Colors.deepPurple,
                              ),
                              onPressed: () {
                                setState(() {
                                  _obscurePassword = !_obscurePassword;
                                });
                              },
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                        const SizedBox(height: 30),

                        // Login Button
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _login,
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 15),
                              backgroundColor: Colors.deepPurple,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: _isLoading
                                ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2),
                            )
                                : const Text(
                              'Login',
                              style: TextStyle(fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 40),

                  // Footer
                  const Text(
                    'Powered by Sanpra Software Solution',
                    style: TextStyle(color: Colors.white70,
                        fontSize: 14,
                        fontWeight: FontWeight.w500),
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


  Future<String?> getToken() async {
  try {
    final FlutterSecureStorage storage = FlutterSecureStorage();
    final String? apiSecret = await storage.read(key: "api_secret");
    final String? apiKey = await storage.read(key: "api_key");
    if (apiKey == null || apiKey.isEmpty || apiSecret == null || apiSecret.isEmpty) {
      print("❌ getToken: Missing or empty API key/secret");
      return null;
    }
    return 'token $apiKey:$apiSecret';
  } catch (e, stack) {
    print("🔥 getToken Error: $e");
    print("🔥 Stack: $stack");
    return null;
  }
}