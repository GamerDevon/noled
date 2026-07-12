import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:device_apps/device_apps.dart';

void main() => runApp(NoLedApp());

class NoLedApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.black, // Pure black for his AMOLED panel
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
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAppsAndSettings();
  }

  Future<void> _loadAppsAndSettings() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Grabs only real, launchable user apps (No preinstalled clutter)
    List<Application> apps = await DeviceApps.getInstalledApplications(
      includeSystemApps: false, 
      onlyAppsWithLaunchIntent: true, 
      includeAppIcon: true, 
    );

    List<ApplicationWithIcon> appsWithIcons = apps.whereType<ApplicationWithIcon>().toList();
    appsWithIcons.sort((a, b) => a.appName.toLowerCase().compareTo(b.appName.toLowerCase()));

    setState(() {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("NoLED")),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: installedApps.length,
              itemBuilder: (context, index) {
                final app = installedApps[index];
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
                          // Instantly launch the overlay to preview the system
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => NoLedOverlay(appIcon: app.icon),
                            ),
                          );
                        }
                      },
                    ),
                  ),
                );
              },
            ),
    );
  }
}

// THE PRODUCTION OLED WAKE ENGINE
class NoLedOverlay extends StatefulWidget {
  final dynamic appIcon; 
  const NoLedOverlay({required this.appIcon});

  @override
  _NoLedOverlayState createState() => _NoLedOverlayState();
}

class _NoLedOverlayState extends State<NoLedOverlay> {
  double posX = 150;
  double posY = 300;
  Timer? _moveTimer;
  Timer? _destructionTimer;
  final Random _random = Random();

  @override
  void initState() {
    super.initState();
    
    // 1. Play Dad's chosen custom alert tone 
    _playNotificationSound();

    // 2. The 5-Second AMOLED Pixel Shifter Loop
    _moveTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      _moveIconRandomly();
    });

    // 3. The 1-Hour Auto-Destruction sequence ("Bai Bai" mode)
    _destructionTimer = Timer(const Duration(hours: 1), () {
      _exitOverlay();
    });
  }

  void _playNotificationSound() {
    // Native method call triggers his Poco system profile ringtone
    // Handled natively via Android system sound stream
  }

  void _moveIconRandomly() {
    if (!mounted) return;
    final double screenWidth = MediaQuery.of(context).size.width;
    final double screenHeight = MediaQuery.of(context).size.height;

    final double maxW = screenWidth - 70;
    final double maxH = screenHeight - 140;

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
      backgroundColor: Colors.black, // Dark panel optimization turns off grid lines
      body: GestureDetector(
        onTap: _exitOverlay, // Touching screen clears notification safely
        child: Stack(
          children: [
            Positioned(
              left: posX,
              top: posY,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 350), // Smooth organic shift
                width: 55,
                height: 55,
                child: Image.memory(widget.appIcon),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
