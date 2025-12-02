import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import 'package:workmanager/workmanager.dart';
import 'package:location_tracker/Screens/login.dart';

class Config {
  static const String apiBaseUrl = 'http://172.20.10.2:8001';
}

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    try {
      final storage = FlutterSecureStorage();
      final sharingEnabled = await storage.read(key: 'sharing_enabled') ?? 'true';
      print("🔄 Background task triggered - taskName: $taskName, sharing_enabled: $sharingEnabled");
      if (sharingEnabled == 'true') {
        await _DashboardPageState._sendLocationBackground();
      } else {
        print("🚫 Background task skipped - location sharing disabled");
      }
      return Future.value(true);
    } catch (e, stack) {
      print("🔥 Background task error: $e");
      print("🔥 Background task stack: $stack");
      return Future.value(false);
    }
  });
}

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final _storage = const FlutterSecureStorage();
  Timer? _locationTimer;
  String? _lastStatus;
  bool _isSending = false;
  bool _sharingEnabled = true;

  @override
  void initState() {
    super.initState();
    _loadSharingEnabled();
    _registerBackgroundTask();
  }

  Future<void> _loadSharingEnabled() async {
    try {
      final enabled = await _storage.read(key: 'sharing_enabled') ?? 'true';
      setState(() => _sharingEnabled = enabled == 'true');
      if (_sharingEnabled) {
        _startLocationUpdates();
      }
    } catch (e, stack) {
      print("🔥 Error loading sharing_enabled: $e");
      print("🔥 Stack: $stack");
      setState(() => _lastStatus = "❌ Error loading settings");
    }
  }

  Future<void> _toggleSharing(bool value) async {
    try {
      setState(() => _sharingEnabled = value);
      await _storage.write(
          key: 'sharing_enabled', value: value ? 'true' : 'false');
      if (value) {
        _startLocationUpdates();
        setState(() => _lastStatus = "✅ Location sharing enabled");
      } else {
        _locationTimer?.cancel();
        setState(() => _lastStatus = "🚫 Location sharing disabled");
      }
    } catch (e, stack) {
      print("🔥 Error toggling sharing: $e");
      print("🔥 Stack: $stack");
      setState(() => _lastStatus = "❌ Error updating settings");
    }
  }

  void _registerBackgroundTask() {
    Workmanager().registerPeriodicTask(
      "location_update_task",
      "sendLocationBackground",
      frequency: const Duration(minutes: 1),
      constraints: Constraints(
        networkType: NetworkType.connected,
        requiresBatteryNotLow: true,
      ),
      initialDelay: const Duration(seconds: 10),
    );
    print("📅 Background task registered");
  }

  void _startLocationUpdates() {
    if (!_sharingEnabled) return;
    _sendLocation();
    _locationTimer?.cancel();
    _locationTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      _sendLocation();
    });
    print("🔄 Foreground timer started (1-minute interval)");
  }

  Future<void> _sendLocation() async {
    if (!_sharingEnabled) return;
    setState(() => _isSending = true);
    try {
      print("🔄 Sending foreground location...");

      final String? token = await getToken();
      final username = await _storage.read(
          key: "username"); // Use username instead of full_name

      print("🔑 Token: $token");
      print("👤 Username: $username");

      if (token == null || token.isEmpty || username == null ||
          username.isEmpty) {
        setState(() => _lastStatus = "❌ Missing login credentials");
        print("❌ Missing credentials - Token: $token, Username: $username");
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text("Session expired. Please log in again."),
            action: SnackBarAction(
              label: "Log In",
              onPressed: () => _logout(),
            ),
          ),
        );
        return;
      }

      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() => _lastStatus = "❌ Location services are disabled");
        print("❌ Location services disabled");
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() => _lastStatus = "❌ Location permissions denied");
          print("❌ Location permissions denied");
          return;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        setState(() =>
        _lastStatus =
        "❌ Location permissions permanently denied. Enable in settings.");
        print("❌ Location permissions permanently denied");
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                "Please enable location permissions in app settings."),
            action: SnackBarAction(
              label: "Settings",
              onPressed: Geolocator.openAppSettings,
            ),
          ),
        );
        return;
      }

      final Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      print("✅ Got foreground location => Lat: ${position
          .latitude}, Lng: ${position.longitude}, Accuracy: ${position
          .accuracy}");

      String accuracyString;
      if (position.accuracy <= 10.0) {
        accuracyString = "high";
      } else if (position.accuracy <= 100.0) {
        accuracyString = "low";
      } else {
        accuracyString = "unavailable";
      }

      final response = await http.post(
        Uri.parse("${Config
            .apiBaseUrl}/api/method/location_tracker.custom_pyfile.api.log_location"),
        headers: {
          "Content-Type": "application/json",
          "Authorization": token,
        },
        body: jsonEncode({
          "user": username,
          "latitude": position.latitude,
          "longitude": position.longitude,
          "accuracy": accuracyString,
          "gps_status": 1,
          "sharing_status": "on",
          "source": "gps",
        }),
      );

      print("🌐 Foreground API Response Code: ${response.statusCode}");
      print("🌐 Foreground API Response Body: ${response.body}");

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() =>
        _lastStatus = "✅ Sent at ${DateTime.now()} - ${data['message']}");
      } else if (response.statusCode == 401) {
        setState(() =>
        _lastStatus = "❌ Invalid credentials, please log in again");
        print("❌ 401 Unauthorized - Check token validity");
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text("Session expired. Please log in again."),
            action: SnackBarAction(
              label: "Log In",
              onPressed: () => _logout(),
            ),
          ),
        );
      } else {
        final errorData = jsonDecode(response.body);
        setState(() =>
        _lastStatus = "❌ Failed: ${errorData['message'] ?? 'Unknown error'}");
        print("❌ API Error: ${errorData['message'] ?? 'Unknown error'}");
      }
    } catch (e, stack) {
      setState(() => _lastStatus = "🔥 Error: $e");
      print("🔥 Foreground Exception: $e");
      print("🔥 Foreground StackTrace: $stack");
    } finally {
      setState(() => _isSending = false);
    }
  }

  static Future<void> _sendLocationBackground() async {
    try {
      print("🔄 Sending background location...");

      final storage = FlutterSecureStorage();
      final String? token = await getToken();
      final username = await storage.read(
          key: "username"); // Use username instead of full_name

      print("🔑 Background Token: $token");
      print("👤 Background Username: $username");

      if (token == null || token.isEmpty || username == null ||
          username.isEmpty) {
        print(
            "❌ Missing credentials in background - Token: $token, Username: $username");
        return;
      }

      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        print("❌ Location services disabled in background");
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        print("❌ Location permissions denied in background: $permission");
        if (permission == LocationPermission.deniedForever) {
          Workmanager().cancelAll();
          print(
              "🚫 Cancelled background tasks due to permanently denied permissions");
        }
        return;
      }

      final Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      print("✅ Got background location => Lat: ${position
          .latitude}, Lng: ${position.longitude}, Accuracy: ${position
          .accuracy}");

      String accuracyString;
      if (position.accuracy <= 10.0) {
        accuracyString = "high";
      } else if (position.accuracy <= 100.0) {
        accuracyString = "low";
      } else {
        accuracyString = "unavailable";
      }

      final response = await http.post(
        Uri.parse("${Config
            .apiBaseUrl}/api/method/location_tracker.custom_pyfile.api.log_location"),
        headers: {
          "Content-Type": "application/json",
          "Authorization": token,
        },
        body: jsonEncode({
          "user": username,
          "latitude": position.latitude,
          "longitude": position.longitude,
          "accuracy": accuracyString,
          "gps_status": 1,
          "sharing_status": "on",
          "source": "gps",
        }),
      );

      print("🌐 Background API Response Code: ${response.statusCode}");
      print("🌐 Background API Response Body: ${response.body}");
    } catch (e, stack) {
      print("🔥 Background Error: $e");
      print("🔥 Background StackTrace: $stack");
    }
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) =>
          AlertDialog(
            title: const Text("Logout"),
            content: const Text("Are you sure you want to logout?"),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text("Cancel"),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text("Logout"),
              ),
            ],
          ),
    );

    if (confirm == true) {
      try {
        await _storage.deleteAll();
        _locationTimer?.cancel();
        Workmanager().cancelAll();
        print("🧹 Cleared storage and cancelled background tasks");
        if (mounted) {
          Navigator.pushReplacementNamed(context, "/login");
        }
      } catch (e, stack) {
        print("🔥 Logout Error: $e");
        print("🔥 Stack: $stack");
        setState(() => _lastStatus = "❌ Error during logout");
      }
    }
  }

  @override
  void dispose() {
    _locationTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text(
          "Dashboard",
          style: TextStyle(
            color: Colors.white, // white title
          ),
        ),
        centerTitle: true, // 👈 centers the title
        backgroundColor: Colors.deepPurple, // darker background for contrast
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white), // make icon white
            onPressed: _logout,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Heading
              const Text(
                "Employee Location Tracker",
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                "Location updates every 1 minute",
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.blueGrey,
                ),
              ),

              const SizedBox(height: 30),

              // Card for switch
              Card(
                elevation: 3,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      vertical: 20, horizontal: 25),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        "Location Sharing",
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w500),
                      ),
                      Switch(
                        value: _sharingEnabled,
                        activeColor: Colors.deepPurple,
                        onChanged: _toggleSharing,
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // Status text
              Text(
                _lastStatus ?? "Waiting to send first location...",
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, color: Colors.blueGrey),
              ),

              const SizedBox(height: 25),

              // Send Now button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    backgroundColor: Colors.deepPurple,
                  ),
                  onPressed: _isSending || !_sharingEnabled
                      ? null
                      : _sendLocation,
                  child: _isSending
                      ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.white,
                    ),
                  )
                      : const Text(
                    "Send Location Now",
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.white, // 👈 makes the text white
                    ),
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