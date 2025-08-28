import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:app_settings/app_settings.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        // This is the theme of your application.
        //
        // TRY THIS: Try running your application with "flutter run". You'll see
        // the application has a purple toolbar. Then, without quitting the app,
        // try changing the seedColor in the colorScheme below to Colors.green
        // and then invoke "hot reload" (save your changes or press the "hot
        // reload" button in a Flutter-supported IDE, or press "r" if you used
        // the command line to start the app).
        //
        // Notice that the counter didn't reset back to zero; the application
        // state is not lost during the reload. To reset the state, use hot
        // restart instead.
        //
        // This works for code too, not just values: Most code changes can be
        // tested with just a hot reload.
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
      ),
      home: const SettingsPage(title: 'Expense Tracker'),
    );
  }
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.title});

  final String title;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _serviceEnabled = false;
  String _webhookUrl = '';
  final Map<String, bool> _selectedApps = {};
  final Map<String, String> _appNames = {};
  final Map<String, String> _appIcons = {};
  final List<Map<String, dynamic>> _allApps = [];
  bool _isLoading = true;
  bool _hasNotificationAccess = false;
  bool _hasOverlayPermission = false;

  final TextEditingController _webhookUrlController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _loadInstalledApps();
    _checkPermissions();
  }

  Future<bool> _isNotificationListenerAccessEnabled() async {
    final platform = MethodChannel('com.example.expense_tracker/settings');
    final result = await platform.invokeMethod<bool>('isNotificationListenerAccessEnabled') ?? false;
    return result;
  }

  Future<void> _checkPermissions() async {
    final bool overlayPermission = await Permission.systemAlertWindow.isGranted;
    final bool notificationPermission = await _isNotificationListenerAccessEnabled();

    setState(() {
      _hasOverlayPermission = overlayPermission;
      _hasNotificationAccess = notificationPermission;
    });
  }

  Future<void> _loadInstalledApps() async {
    try{
      final platform = MethodChannel('com.example.expense_tracker/settings');
      final List<dynamic> apps = await platform.invokeMethod('getInstalledApps');

      setState(() {
        _allApps.clear();
        for (var app in apps) {
          _allApps.add({
            'packageName': app['packageName'],
            'appName': app['appName'],
            'appIcon': app['appIcon']
          });
          _appNames[app['packageName']] = app['appName'];
          _appIcons[app['packageName']] = app['appIcon'];
        }
        _isLoading = false;
      });
    } on PlatformException catch (e) {
      print("Error loading installed apps: ${e.message}");
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();

    setState(() {
      _serviceEnabled = prefs.getBool('service_enabled') ?? false;
      _webhookUrl = prefs.getString('webhook_url') ?? '';
      _webhookUrlController.text = _webhookUrl;

      final savedApps = prefs.getStringList('selected_apps') ?? [];
      for (String app in savedApps) {
        _selectedApps[app] = true;
      }
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('service_enabled', _serviceEnabled);
    await prefs.setString('webhook_url', _webhookUrl);
    
    final selectedAppList = _selectedApps.entries
        .where((entry) => entry.value)
        .map((entry) => entry.key)
        .toList();
    await prefs.setStringList('selected_apps', selectedAppList);

    await _sendSettingsToAndroid();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Settings saved successfully')),
    );
  }

  Future<void> _sendSettingsToAndroid() async {
    final platform = MethodChannel('com.example.expense_tracker/settings');
    try {
      await platform.invokeMethod('updateSettings', {
        'service_enabled': _serviceEnabled,
        'webhook_url': _webhookUrl,
        'selected_apps': _selectedApps,
      });
    } on PlatformException catch (e) {
      print("Failed to send settings to Android: ${e.message}");
    }
  }

  Future<void> _requestPermissions() async {
    if (await Permission.systemAlertWindow.request().isDenied) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Overlay permission is required for popups.')),
      );
    }

    if (!_hasNotificationAccess) {
      const platform = MethodChannel('com.example.expense_tracker/settings');
      await platform.invokeMethod('requestNotificationListenerAccess');
    }

    await _checkPermissions();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            icon: Icon(Icons.save),
            onPressed: _saveSettings,
          ),
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: () {
              _loadInstalledApps();
              _checkPermissions();
            },
          ),
        ],
      ),
      body: _isLoading
        ? Center(child: CircularProgressIndicator())
        : ListView(
          padding: EdgeInsets.all(16),
          children: [
            if (!_hasNotificationAccess || !_hasOverlayPermission)
              Card(
                color: Colors.orange[100],
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.warning, color: Colors.orange),
                          SizedBox(width: 8),
                          Text(
                            'Permission Required',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: Colors.orange[800],
                            )
                          )
                        ],
                      ),

                      SizedBox(height: 8),

                      if (!_hasNotificationAccess)
                        Text(
                          'Notification access is required to listen for incoming notifications.',
                          style: TextStyle(color: Colors.orange[800]),
                        ),
                        SizedBox(height: 8),
                      if (!_hasOverlayPermission)
                        Text(
                          'Overlay permission is required to show interactive popups.',
                          style: TextStyle(color: Colors.orange[800]),
                        ),
                        SizedBox(height: 8),
                      ElevatedButton(
                        onPressed: _requestPermissions,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange,
                        ),
                        child: Text('Grant Permissions'),
                      )
                    ]
                  )
                )
              ),

              SizedBox(height: 16),

              Card(
                child: ListTile(
                  title: Text('Enable Notification Listener'),
                  subtitle: !_hasNotificationAccess && _serviceEnabled
                    ? Text('Notification access required', style: TextStyle(color: Colors.red))
                    : null,
                  trailing: Switch(
                    value: _serviceEnabled,
                    onChanged: (value) {
                      setState(() {
                        _serviceEnabled = value;
                      });
                      if (value && (!_hasOverlayPermission || !_hasNotificationAccess)) _requestPermissions();
                    },
                  )
                )
              ),

              SizedBox(height: 16),

              Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Webhook URL',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      SizedBox(height: 8),
                      TextField(
                        controller: _webhookUrlController,
                        decoration: InputDecoration(
                          hintText: 'Enter Webhook URL',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (value) {
                          _webhookUrl = value;
                        },
                      )
                    ],
                  )
                )
              ),

              SizedBox(height: 16),

              Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Select Apps to Monitor',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      SizedBox(height: 8),

                      TextField(
                        controller: _searchController,
                        decoration: InputDecoration(
                          hintText: 'Search apps...',
                          prefixIcon: Icon(Icons.search),
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (value) {
                          setState(() {});
                        },
                      ),

                      SizedBox(height: 8),
                      
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          TextButton(
                            onPressed: () {
                              setState(() {
                                for (var app in _allApps) {
                                  _selectedApps[app['packageName']] = true;
                                }
                              });
                            },
                            child: Text('Select All'),
                          ),
                          TextButton(
                            onPressed: () {
                              setState(() {
                                for (var app in _allApps) {
                                  _selectedApps[app['packageName']] = false;
                                }
                              });
                            },
                            child: Text('Deselect All'),
                          ),
                        ],
                      ),

                      SizedBox(height: 8),

                      Container(
                        height: 300,
                        child: ListView.builder(
                          itemCount: _allApps.length,
                          itemBuilder: (context, index) {
                            final app = _allApps[index];
                            final packageName = app['packageName'];
                            final appName = app['appName'];
                            final appIcon = app['appIcon'];

                            if (_searchController.text.isNotEmpty &&
                                !appName.toLowerCase().contains(_searchController.text.toLowerCase()) && 
                                !packageName.toLowerCase().contains(_searchController.text.toLowerCase())) {
                                  
                              return SizedBox.shrink();
                            }

                            return ListTile(
                              leading: appIcon != null && appIcon.isNotEmpty
                                ? CircleAvatar(
                                  backgroundImage: MemoryImage(base64.decode(appIcon)),
                                  radius: 20
                                )
                                : CircleAvatar(
                                  child: Icon(Icons.android),
                                  radius: 20
                                ),
                              title: Text(appName),
                              trailing: Checkbox(
                                value: _selectedApps[packageName] ?? false,
                                onChanged: (value) {
                                  setState(() {
                                    _selectedApps[packageName] = value ?? false;
                                  });
                                },
                              ),
                              onTap: () {
                                setState(() {
                                  _selectedApps[packageName] = !(_selectedApps[packageName] ?? false);
                                });
                              }
                            );
                          },
                        )
                      ),

                      SizedBox(height: 16),

                      Card(
                        child: Padding(
                          padding: EdgeInsets.all(16),
                          child: Row(
                            children: [
                              Icon(
                                Icons.apps,
                                color: Colors.blue,
                              ),
                              SizedBox(width: 8),
                              Text('Apps Selected: ${_selectedApps.values.where((v) => v).length}')
                            ]
                          )
                        )
                      )
                    ]
                  )
                ), 
              )
          ]

        )
    );
  }
}
