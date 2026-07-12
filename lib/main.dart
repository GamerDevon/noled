import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:installed_apps/installed_apps.dart';
import 'package:installed_apps/app_info.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:permission_handler/permission_handler.dart';

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
  final ValueNotifier<String?> backgroundTriggerNotifier = ValueNotifier<String?>(null);

  @override
  void initState() {
    super.initState();
    platform.setMethodCallHandler((call) async {
      if (call.method == "showNotificationOverlay") {
        final String? packageName = call.arguments as String?;
        if (packageName != null) {
          backgroundTriggerNotifier.value = packageName;
        }
      }
    });
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
      home: AppSettingsScreen(triggerNotifier: backgroundTriggerNotifier),
    );
  }
}

class AppSettingsScreen extends StatefulWidget {
  final ValueNotifier<String?> triggerNotifier;
  const AppSettingsScreen({required this.triggerNotifier});

  @override
  _AppSettingsScreenState createState() => _AppSettingsScreenState();
}

class _AppSettingsScreenState extends State<AppSettingsScreen> {
  List<AppInfo> installedApps = [];
  final Set<String> enabledApps = {}; 
  Color batteryColor = Colors.green; 
  bool isLoading = true;
  
  // Stavy oprávnění
  bool isOverlayGranted = true;
  bool isNotificationGranted = true;
  bool isBatteryOptIgnored = true;

  static const MethodChannel _permissionChannel = MethodChannel('com.noled.app/overlay');

  final List<Color> colorPresets = [
    Colors.red, Colors.green, Colors.blue, Colors.yellow, Colors.purple, Colors.cyan,
  ];

  @override
  void initState() {
    super.initState();
    _loadAppsAndSettings();
    _checkAllPermissions();
    widget.triggerNotifier.addListener(_handleBackgroundTrigger);
  }

  @override
  void dispose() {
    widget.triggerNotifier.removeListener(_handleBackgroundTrigger);
    super.dispose();
  }

  // Kontrola všech oprávnění najednou
  Future<void> _checkAllPermissions() async {
    final notificationStatus = await Permission.notification.status;
    final batteryStatus = await Permission.ignoreBatteryOptimizations.status;
    
    bool overlayCheck = false;
    try {
      overlayCheck = await _permissionChannel.invokeMethod('checkOverlayPermission') ?? false;
    } catch (_) {}

    setState(() {
      isNotificationGranted = notificationStatus.isGranted;
      isBatteryOptIgnored = batteryStatus.isGranted;
      isOverlayGranted = overlayCheck;
    });
  }

  // Vyžádání standardních oprávnění (Oprávnění aplikace)
  Future<void> _requestStandardPermissions() async {
    await Permission.notification.request();
    await Permission.ignoreBatteryOptimizations.request();
    _checkAllPermissions();
  }

  // Otevření nativního "Kreslení přes aplikace / Vyskakovací okna"
  Future<void> _openOverlaySettings() async {
    try {
      await _permissionChannel.invokeMethod('requestOverlayPermission');
    } catch (_) {}
    Future.delayed(const Duration(seconds: 2), () => _checkAllPermissions());
  }

  // Otevření hlubokého nastavení (App Info) pro Xiaomi "Ostatní oprávnění"
  Future<void> _openDeepAppSettings() async {
    await openAppSettings();
    Future.delayed(const Duration(seconds: 2), () => _checkAllPermissions());
  }

  void _handleBackgroundTrigger() async {
    final package = widget.triggerNotifier.value;
    if (package == null) return;
    widget.triggerNotifier.value = null;

    Uint8List? matchedIcon;
    for (var app in installedApps) {
      if (app.packageName == package) {
        matchedIcon = app.icon;
        break;
      }
    }

    final prefs = await SharedPreferences.getInstance();
    final savedBatteryColorValue = prefs.getInt('battery_color_pref') ?? Colors.green.value;

    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => NoLedOverlay(
            appIcon: matchedIcon,
            bColor: Color(savedBatteryColorValue),
          ),
        ),
      );
    }
  }

  Future<void> _loadAppsAndSettings() async {
    final prefs = await SharedPreferences.getInstance();
    List<AppInfo> apps = await InstalledApps.getInstalledApps(true, true);
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
    bool everythingGranted = isOverlayGranted && isNotificationGranted && isBatteryOptIgnored;

    return Scaffold(
      appBar: AppBar(title: const Text("NoLED")),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                // KOMPLETNÍ PANEL SPRÁVY OPRÁVNĚNÍ
                Card(
                  color: everythingGranted ? Colors.green.shade900.withOpacity(0.4) : Colors.deepOrange.shade900.withOpacity(0.6),
                  margin: const EdgeInsets.all(10),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Icon(
                              everythingGranted ? Icons.check_circle : Icons.warning,
                              color: everythingGranted ? Colors.green : Colors.amber,
                            ),
                            const SizedBox(width: 10),
                            Text(
                              everythingGranted ? "Všechna oprávnění jsou udělena!" : "Vyžadováno nastavení oprávnění",
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        
                        // Stav 1: Oprávnění aplikace (Upozornění a Baterie)
                        _buildPermissionStatusRow("Oprávnění aplikace (Notifikace & Baterie)", isNotificationGranted && isBatteryOptIgnored),
                        // Stav 2: Vyskakovací okna / Kreslení přes aplikace
                        _buildPermissionStatusRow("Zobrazit přes ostatní aplikace (Overlay)", isOverlayGranted),
                        
                        const SizedBox(height: 14),
                        if (!everythingGranted) ...[
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.black87),
                            icon: const Icon(Icons.security, size: 18),
                            label: const Text("1. Povolit Oprávnění aplikace"),
                            onPressed: _requestStandardPermissions,
                          ),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.black87),
                            icon: const Icon(Icons.layers, size: 18),
                            label: const Text("2. Povolit Vyskakovací okna (Overlay)"),
                            onPressed: _openOverlaySettings,
                          ),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF263238)), // Opraveno pozadí
                            icon: const Icon(Icons.settings_applications, size: 18),
                            label: const Text("3. Otevřít detaily (pro 'Ostatní oprávnění')"),
                            onPressed: _openDeepAppSettings,
                          ),
                          const Padding(
                            padding: EdgeInsets.only(top: 8.0),
                            child: Text(
                              "* Na telefonech Xiaomi/Redmi klepněte na tlačítko 3, zvolte 'Ostatní oprávnění' a ručně povolte 'Zobrazit vyskakovací okna při běhu na pozadí'.",
                              style: TextStyle(fontSize: 11, color: Colors.white70, fontStyle: FontStyle.italic), // Opraveno italic
                            ),
                          ),
                        ]
                      ],
                    ),
                  ),
                ),
                
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

  Widget _buildPermissionStatusRow(String label, bool isGranted) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        children: [
          Icon(isGranted ? Icons.check : Icons.close, color: isGranted ? Colors.green : Colors.red, size: 16),
          const SizedBox(width: 6),
          Expanded(child: Text(label, style: const TextStyle(fontSize: 13, color: Colors.white70))), // Opraveno white90 -> white70
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
