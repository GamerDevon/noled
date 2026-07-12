import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:installed_apps/installed_apps.dart';
import 'package:installed_apps/app_info.dart';
import 'package:battery_plus/battery_plus.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(NoLedApp());
}

class NoLedApp extends StatefulWidget {
  @override
  State<NoLedApp> createState() => _NoLedAppState();
}

class _NoLedAppState extends State<NoLedApp> {
  static const platform = MethodChannel('com.noled.app/overlay');
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    // Native service triggers this when a matching notification arrives
    platform.setMethodCallHandler((call) async {
      if (call.method == "showNotificationOverlay") {
        final String? packageName = call.arguments as String?;
        _triggerOverlay(packageName);
      }
    });
  }

  Future<void> _triggerOverlay(String? packageName) async {
    Uint8List? iconBytes;
    if (packageName != null) {
      try {
        iconBytes = await InstalledApps.getAppIcon(packageName);
      } catch (_) {}
    }

    final prefs = await SharedPreferences.getInstance();
    final savedBatteryColorValue = prefs.getInt('battery_color_pref') ?? Colors.green.value;

    navigatorKey.currentState?.push(
      MaterialPageRoute(
        builder: (context) => NoLedOverlay(
          appIcon: iconBytes,
          bColor: Color(savedBatteryColorValue),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
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
  List<AppInfo> installedApps = [];
  final Set<String> enabledApps = {}; 
  Color batteryColor = Colors.green; 
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
    
    List<AppInfo> apps = await InstalledApps.getInstalledApps(
      excludeSystemApps: true,
      withIcon: true,
    );

    apps.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    final savedBatteryColorValue = prefs.getInt('battery_color_pref');
    
    setState(() {
      if (savedBatteryColorValue != null) {
        batteryColor = Color(savedBatteryColorValue);
      }
      installedApps = apps;
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
                ...installedApps.map((app) {
                  final package = app.packageName;
                  final isEnabled = enabledApps.contains(package);

                  return Card(
                    color: Colors.grey.shade900,
                    margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    child: ListTile(
                      leading: app.icon != null 
                          ? Image.memory(app.icon!, width: 40, height: 40)
                          : const Icon(Icons.android, size: 40), 
                      title: Text(app.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text(package, style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
                      trailing: Switch(
                        value: isEnabled,
                        activeColor: Colors.cyan,
                        onChanged: (bool value) {
                          _toggleApp(package, value);
                          if (value) {
                            // Allows testing the overlay layout immediately when switched on
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

class NoLedOverlay extends StatefulWidget {
  final Uint8List? appIcon; 
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
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _checkBatteryStatus();

    _moveTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      _moveIconRandomly();
      _checkBatteryStatus(); 
    });

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

    final double maxW = screenWidth > 100 ? screenWidth - 100 : 100;
    final double maxH = screenHeight > 180 ? screenHeight - 180 : 180;

    setState(() {
      posX = _random.nextDouble() * maxW;
      posY = _random.nextDouble() * maxH;
    });
  }

  void _exitOverlay() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
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
                    widget.appIcon != null 
                        ? Image.memory(widget.appIcon!, width: 55, height: 55)
                        : const Icon(Icons.android, size: 55, color: Colors.cyan),
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
