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
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

// Global log collector stream for the UI debug card
final StreamController<String> debugLogStream = StreamController<String>.broadcast();
void logDebugMessage(String message) {
  final timestamp = DateTime.now().toString().substring(11, 19);
  debugLogStream.add("[$timestamp] $message");
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  const AndroidInitializationSettings initializationSettingsAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');
  const InitializationSettings initializationSettings = InitializationSettings(android: initializationSettingsAndroid);
  
  await flutterLocalNotificationsPlugin.initialize(initializationSettings);

  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'com.noled.noled/alerts', 
    'NoLED Core Alerts',
    description: 'Bypasses system restrictions to initialize overlay parameters.',
    importance: Importance.max,
    playSound: false,
    enableVibration: false,
  );

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);

  logDebugMessage("Engine initialized successfully.");
  runApp(NoLedApp());
}

class NoLedApp extends StatefulWidget {
  @override
  State<NoLedApp> createState() => _NoLedAppState();
}

class _NoLedAppState extends State<NoLedApp> {
  static const platform = MethodChannel('com.noled.noled/overlay');
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  final ValueNotifier<String?> backgroundTriggerNotifier = ValueNotifier<String?>(null);

  @override
  void initState() {
    super.initState();
    platform.setMethodCallHandler((call) async {
      logDebugMessage("Received Native Method Call: ${call.method}");
      if (call.method == "showNotificationOverlay") {
        final String? packageName = call.arguments as String?;
        logDebugMessage("Trigger package payload parsed: $packageName");
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
  
  // Persistent log strings container
  List<String> liveLogsList = ["Logs initialized... Ready for events."];

  static const MethodChannel _permissionChannel = MethodChannel('com.noled.noled/overlay');
  final List<Color> colorPresets = [
    Colors.red, Colors.green, Colors.blue, Colors.yellow, Colors.purple, Colors.cyan,
  ];

  @override
  void initState() {
    super.initState();
    _loadAppsAndSettings();
    _requestAllSystemPermissions();
    widget.triggerNotifier.addListener(_handleBackgroundTrigger);
    
    // Listen to global logging actions and update UI state
    debugLogStream.stream.listen((logLine) {
      if (mounted) {
        setState(() {
          liveLogsList.add(logLine);
        });
      }
    });
  }

  @override
  void dispose() {
    widget.triggerNotifier.removeListener(_handleBackgroundTrigger);
    super.dispose();
  }

  Future<void> _requestAllSystemPermissions() async {
    logDebugMessage("Requesting native runtime permissions...");
    await [
      Permission.notification,
      Permission.sms,
      Permission.ignoreBatteryOptimizations,
    ].request();

    try {
      final bool? isOverlayGranted = await _permissionChannel.invokeMethod('checkOverlayPermission');
      logDebugMessage("System Overlay state check: $isOverlayGranted");
      await _permissionChannel.invokeMethod('requestOverlayPermission');
    } catch (e) {
      logDebugMessage("Error configuring system windows: $e");
    }
  }

  Future<void> _openXiaomiPermissions() async {
    logDebugMessage("Attempting redirect to POCO application options panel...");
    try {
      await _permissionChannel.invokeMethod('openOtherPermissions');
    } catch (e) {
      logDebugMessage("Failed opening direct POCO settings editor: $e");
    }
  }

  void _handleBackgroundTrigger() async {
    final package = widget.triggerNotifier.value;
    if (package == null) return;
    widget.triggerNotifier.value = null;

    logDebugMessage("Displaying screen overlay UI for package: $package");
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
            debugPackageName: package,
          ),
        ),
      );
    }
  }

  Future<void> _loadAppsAndSettings() async {
    final prefs = await SharedPreferences.getInstance();
    logDebugMessage("Loading installed applications list...");
    
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
    logDebugMessage("Found ${apps.length} valid package channels.");
  }

  Future<void> _toggleApp(String package, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    logDebugMessage("Toggling configuration for $package -> $value");
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

  void _triggerLocalInAppTest(String selectedPackageName) {
    logDebugMessage("Manual testing button clicked for: $selectedPackageName");
    widget.triggerNotifier.value = selectedPackageName;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("NoLED Settings"),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_suggest, color: Colors.cyan),
            onPressed: _openXiaomiPermissions,
            tooltip: "Open POCO Ostatní Oprávnění",
          ),
          IconButton(
            icon: const Icon(Icons.security),
            onPressed: _requestAllSystemPermissions,
            tooltip: "Request Standard Permissions",
          )
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                // PERSISTENT DEBUG LOG CONSOLE (Stays open until Red X clears it)
                if (liveLogsList.isNotEmpty)
                  Card(
                    color: Colors.grey.shade950,
                    margin: const EdgeInsets.all(10),
                    shape: RoundedRectangleBorder(
                      side: const BorderSide(color: Colors.amber, width: 1.5),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Row(
                                children: [
                                  Icon(Icons.bug_report, color: Colors.amber, size: 20),
                                  SizedBox(width: 6),
                                  Text("Live Debug Console logs", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.amber)),
                                ],
                              ),
                              IconButton(
                                constraints: const BoxConstraints(),
                                padding: EdgeInsets.zero,
                                icon: const Icon(Icons.cancel, color: Colors.red, size: 26),
                                onPressed: () {
                                  setState(() {
                                    liveLogsList.clear();
                                  });
                                },
                              )
                            ],
                          ),
                          const Divider(color: Colors.amber),
                          Container(
                            constraints: const BoxConstraints(maxHeight: 180),
                            child: SingleChildScrollView(
                              reverse: true, // Auto-scrolls down to newest logs
                              child: Text(
                                liveLogsList.join("\n"),
                                style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: Colors.greenAccent),
                              ),
                            ),
                          ),
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
                      onTap: () => _triggerLocalInAppTest(package),
                      leading: app.icon != null 
                          ? Image.memory(app.icon!, width: 40, height: 40, errorBuilder: (c, e, s) => const Icon(Icons.android, size: 40))
                          : const Icon(Icons.android, size: 40), 
                      title: Text(app.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text("Klepnutím spustíte testovací overlay\n$package", style: TextStyle(color: Colors.grey.shade500, fontSize: 11)),
                      trailing: Switch(
                        value: isEnabled,
                        activeColor: Colors.cyan,
                        onChanged: (bool value) {
                          _toggleApp(package, value);
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
  final String debugPackageName;
  
  const NoLedOverlay({
    required this.appIcon, 
    required this.bColor,
    required this.debugPackageName,
  });

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

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _moveIconRandomly();
      _moveTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
        _moveIconRandomly();
        _checkBatteryStatus(); 
      });
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

    final double maxW = screenWidth > 100 ? screenWidth - 100 : 200;
    final double maxH = screenHeight > 180 ? screenHeight - 180 : 400;

    setState(() {
      posX = _random.nextDouble() * maxW;
      posY = _random.nextDouble() * maxH;
    });
  }

  void _exitOverlay() {
    logDebugMessage("Overlay closed by screen tap interaction.");
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
              top: 40,
              left: 20,
              right: 20,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white12,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  "DEBUG: Triggered by ${widget.debugPackageName}\n(Tap anywhere to close overlay)",
                  style: const TextStyle(color: Colors.amber, fontSize: 12, fontFamily: 'monospace'),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            Positioned(
              left: posX,
              top: posY,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 350), 
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    widget.appIcon != null 
                        ? Image.memory(
                            widget.appIcon!, 
                            width: 55, 
                            height: 55,
                            errorBuilder: (c, e, s) => const Icon(Icons.android, size: 55, color: Colors.cyan),
                          )
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
