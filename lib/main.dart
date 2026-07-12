import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:device_apps/device_apps.dart';
import 'package:battery_plus/battery_plus.dart'; // Core power tracker

void main() => runApp(NoLedApp());

class NoLedApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.black,
        appBarTheme: const AppBarTheme(backgroundColor: Colors.black87),
      ),
      home: AppSettingsScreen(),
    );
  }
}

class AppSettingsScreen extends StatefulWidget {
  @override
  _AppSettingsScreenState createState() => _AppSettingsScreenState();
}

class _AppSettingsScreenState extends State<AppSettingsScreen> {
  List<ApplicationWithIcon> installedApps = [];
  final Set<String> enabledApps = {}; 
  Color batteryColor = Colors.green; // Default battery color
  bool isLoading = true;

  final List<Color> colorPresets = [
    Colors.red,
    Colors.green,
    Colors.blue,
    Colors.yellow,
    Colors.purple,
    Colors.cyan,
  ];

  @override
  void initState() {
    super.initState();
    _loadAppsAndSettings();
  }

  Future<void> _loadAppsAndSettings() async {
    final prefs = await SharedPreferences.getInstance();
    
    List<Application> apps = await DeviceApps.getInstalledApplications(
      includeSystemApps: false, 
      onlyAppsWithLaunchIntent: true, 
      includeAppIcon: true, 
    );

    List<ApplicationWithIcon> appsWithIcons = apps.whereType<ApplicationWithIcon>().toList();
    appsWithIcons.sort((a, b) => a.appName.toLowerCase().compareTo(b.appName.toLowerCase()));

    // Load saved battery color choice
    final savedBatteryColorValue = prefs.getInt('battery_color_pref');
    
    setState(() {
      if (savedBatteryColorValue != null) {
        batteryColor = Color(savedBatteryColorValue);
      }
      installedApps = appsWithIcons;
      for (var app in installedApps) {
        final isEnabled = prefs.getBool(app.packageName) ?? false;
        if (isEnabled) {
          enabledApps.add(app.packageName);
        }
      }
      isLoading = false;
    });
  }

  Future<void> _toggleApp(String package, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      if (value) {
        enabledApps.add(package);
        prefs.setBool(package, true);
      } else {
        enabledApps.remove(package);
        prefs.setBool(package, false);
      }
    });
  }

  Future<void> _saveBatteryColor(Color color) async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      batteryColor = color;
    });
    await prefs.setInt('battery_color_pref', color.value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("NoLED")),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                // BATTERY CONFIGURATION CARD IN CZECH
                Card(
                  color: Colors.grey.shade900,
                  margin: const EdgeInsets.all(10),
                  child: ExpansionTile(
                    leading: Icon(Icons.battery_charging_full, color: batteryColor, size: 30),
                    title: const Text("Barva baterie při nabíjení", style: TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: const Text("Vyberte barvu pro zobrazení stavu procent"),
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: colorPresets.map((presetColor) {
                            final isSelected = batteryColor == presetColor;
                            return GestureDetector(
                              onTap: () => _saveBatteryColor(presetColor),
                              child: CircleAvatar(
                                backgroundColor: presetColor,
                                radius: 18,
                                child: isSelected 
                                    ? const Icon(Icons.check, color: Colors.black, size: 18) 
                                    : null,
                              ),
                            );
                          }).toList(),
                        ),
                      )
                    ],
                  ),
                ),
                const Divider(color: Colors.grey),
                // INSTALLED APPS LIST
                ...installedApps.map((app) {
                  final package = app.packageName;
                  final isEnabled = enabledApps.contains(package);

                  return Card(
                    color: Colors.grey.shade900,
                    margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    child: ListTile(
                      leading: Image.memory(app.icon, width: 40, height: 40), 
                      title: Text(app.appName, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text(package, style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
                      trailing: Switch(
                        value: isEnabled,
                        activeColor: Colors.cyan,
                        onChanged: (bool value) {
                          _toggleApp(package, value);
                          if (value) {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => NoLedOverlay(appIcon: app.icon, bColor: batteryColor),
                              ),
                            );
                          }
                        },
                      ),
                    ),
                  );
                }).toList(),
              ],
            ),
    );
  }
}

// ULTRA COMPACT AMOLED SYSTEM WAKE ENGINE WITH POWER SENSOR
class NoLedOverlay extends StatefulWidget {
  final dynamic appIcon; 
  final Color bColor;
  const NoLedOverlay({required this.appIcon, required this.bColor});

  @override
  _NoLedOverlayState createState() => _NoLedOverlayState();
}

class _NoLedOverlayState extends State<NoLedOverlay> {
  double posX = 150;
  double posY = 300;
  String batteryPercentage = "";
  bool isCharging = false;
  
  Timer? _moveTimer;
  Timer? _destructionTimer;
  final Random _random = Random();
  final Battery _batteryEngine = Battery();

  @override
  void initState() {
    super.initState();
    _checkBatteryStatus();

    // The 5-Second Burn-in Protection Loop
    _moveTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      _moveIconRandomly();
      _checkBatteryStatus(); // Refreshes battery digits mid-flight
    });

    // The 1-Hour Automated Termination Countdown
    _destructionTimer = Timer(const Duration(hours: 1), () {
      _exitOverlay();
    });
  }

  Future<void> _checkBatteryStatus() async {
    final level = await _batteryEngine.batteryLevel;
    final state = await _batteryEngine.batteryState;
    if (mounted) {
      setState(() {
        batteryPercentage = "$level%";
        isCharging = (state == BatteryState.charging);
      });
    }
  }

  void _moveIconRandomly() {
    if (!mounted) return;
    final double screenWidth = MediaQuery.of(context).size.width;
    final double screenHeight = MediaQuery.of(context).size.height;

    // Boundary math ensuring text and icon stay visible inside his screen corners
    final double maxW = screenWidth - 100;
    final double maxH = screenHeight - 180;

    setState(() {
      posX = _random.nextDouble() * maxW;
      posY = _random.nextDouble() * maxH;
    });
  }

  void _exitOverlay() {
    if (mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
    _moveTimer?.cancel();
    _destructionTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black, 
      body: GestureDetector(
        onTap: _exitOverlay, 
        child: Stack(
          children: [
            Positioned(
              left: posX,
              top: posY,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 350), 
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Image.memory(widget.appIcon, width: 55, height: 55),
                    // Only triggers charging metric display if plugged in
                    if (isCharging && batteryPercentage.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        batteryPercentage,
                        style: TextStyle(
                          color: widget.bColor,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ]
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
