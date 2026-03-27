import 'dart:io';
import 'package:app_settings/app_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  final Map<String, File?> _iconCache = {};
  final List<Map<String, dynamic>> _allApps = [];
  bool _isLoading = true;
  bool _hasNotificationAccess = false;
  bool _hasAppNotificationsEnabled = false;
  bool _hasLocationAlwaysEnabled = false;

  final TextEditingController _webhookUrlController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _checkPermissions();
    _loadInstalledApps();
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

  Future<void> _preloadIcons() async {
    final packages = _allApps.take(20).map((app) => app['packageName'] as String).toList();
    final missing = packages.where((pkg) => !_iconCache.containsKey(pkg)).toList();
    if (missing.isEmpty) return;

    const platform = MethodChannel('com.example.expense_tracker/settings');
    final Map<dynamic, dynamic>? result = await platform.invokeMethod('getAppIcons', {
      'packageNames': missing,
    });

    if (result != null) {
      result.forEach((pkg, paths) {
        if (paths != null) {
          _iconCache[pkg as String] = paths as File?;
        }
      });
      setState(() {});
    }
  }

  Future<void> _loadInstalledApps() async {
    final platform = MethodChannel('com.example.expense_tracker/settings');
    final List<dynamic> cachedApps = await platform.invokeMethod('getCachedApps');
    if (cachedApps.isNotEmpty) {
      setState(() {
        _allApps.clear();
        for (var app in cachedApps) {
          final packageName = app['packageName'];
          final appName = app['appName'];
          _allApps.add({
            'packageName': packageName,
            'appName': appName,
          });
          _appNames[packageName] = appName;
        }
        _isLoading = false;
      });
    }

    try{
      final platform = MethodChannel('com.example.expense_tracker/settings');
      final List<dynamic> apps = await platform.invokeMethod('getInstalledApps');

      setState(() {
        _allApps.clear();
        _appNames.clear();
        for (var app in apps) {
          final packageName = app['packageName'];
          final appName = app['appName'];
          _allApps.add({
            'packageName': packageName,
            'appName': appName,
          });
          _appNames[packageName] = appName;
        }
        _preloadIcons();
        _isLoading = false;
      });
    } on PlatformException {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _checkPermissions() async {
    final bool notificationPermission = await _isNotificationListenerAccessEnabled();
    final bool appNotificationsEnabled = await _isAppNotificationEnabled();
    final bool locationEnabled = await _isLocationAlwaysEnabled();

    setState(() {
      _hasNotificationAccess = notificationPermission;
      _hasAppNotificationsEnabled = appNotificationsEnabled;
      _hasLocationAlwaysEnabled = locationEnabled;
    });

    if (_hasNotificationAccess && _serviceEnabled) {
      await _rebindListener();
    }

    await _sendSettingsToAndroid();
  }

  Future<void> _rebindListener() async {
    const platform = MethodChannel('com.example.expense_tracker/settings');
    await platform.invokeMethod('rebindListener');
  }

  Future<File?> _loadAppIcon(String packageName) async {
    if (_iconCache.containsKey(packageName)){
      final cached =  _iconCache[packageName];
      if (cached is File) return cached;
    }

    const platform = MethodChannel('com.example.expense_tracker/settings');
    try {
      final String? icon = await platform.invokeMethod('getAppIcon', {'packageName': packageName});
      if (icon != null) {
        final file = File(icon);
        _iconCache[packageName] = file;
        return file;
      }
    } on PlatformException {
      return null;
    }
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
  }

  Future<void> _sendSettingsToAndroid() async {
    final platform = MethodChannel('com.example.expense_tracker/settings');
    try {
      await platform.invokeMethod('updateSettings', {
        'service_enabled': _serviceEnabled,
        'webhook_url': _webhookUrl,
        'selected_apps': _selectedApps,
      });
    } on PlatformException {
      null;
    }
  }

  Future<bool> _isAppNotificationEnabled() async {
    const platform = MethodChannel('com.example.expense_tracker/settings');
    final result = await platform.invokeMethod<bool>('isAppNotificationEnabled') ?? true;
    return result;
  }

  Future<bool> _isNotificationListenerAccessEnabled() async {
    final platform = MethodChannel('com.example.expense_tracker/settings');
    final result = await platform.invokeMethod<bool>('isNotificationListenerAccessEnabled') ?? false;
    return result;
  }

  Future<bool> _isLocationAlwaysEnabled() async {
    const platform = MethodChannel('com.example.expense_tracker/settings');
    final result = await platform.invokeMethod<bool>('isLocationAlwaysEnabled') ?? true;
    return result;
  }

  Future<void> _requestAppNotifications() async {
    final status = await Permission.notification.status;
    if (!status.isGranted) {
      final result = await Permission.notification.request();
      if (!result.isGranted && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Notification permission is required to show the enabled pop-up.')),
        );
      }
    }
  }

  Future<void> _requestLocationAlwaysPermission() async {
    PermissionStatus status = await Permission.locationWhenInUse.request();
    if (!status.isGranted) {
      if (status.isPermanentlyDenied) {
        AppSettings.openAppSettings();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(
                'Location permission is required for precise tracking.')),
          );
        }
      }
      return;
    }

    status = await Permission.locationAlways.request();
    if (!status.isGranted) {
      if (status.isPermanentlyDenied) {
        AppSettings.openAppSettings();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(
                'For background location, please allow "All the time" in settings.')),
          );
        }
      }
      return;
    }
  }
  
  Future<void> _requestPermissions() async {
    if (!_hasAppNotificationsEnabled) {
      await _requestAppNotifications();
      await _checkPermissions();
    }

    if (!_hasNotificationAccess) {
      const platform = MethodChannel('com.example.expense_tracker/settings');
      await platform.invokeMethod('requestNotificationListenerAccess');
      await _checkPermissions();
    }

    if (!_hasLocationAlwaysEnabled) {
      await _requestLocationAlwaysPermission();
      await _checkPermissions();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
      ),
      body: _isLoading
        ? Center(child: CircularProgressIndicator())
        : ListView(
          padding: EdgeInsets.all(16),
          children: [
            if (!_hasAppNotificationsEnabled || !_hasLocationAlwaysEnabled)
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

                      Text(
                        'To use the listener you must allow app notifications. \nLocation is recommended for precise tracking.',
                        style: TextStyle(color: Colors.orange[800]),
                      ),
                      SizedBox(height: 12),

                      ElevatedButton(
                        onPressed: () async {
                          if(!_hasAppNotificationsEnabled) await _requestAppNotifications();
                          if(!_hasLocationAlwaysEnabled) await _requestLocationAlwaysPermission();

                          await _checkPermissions();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange,
                        ),
                        child: Text('Allow Permissions'),
                      ),
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
                    onChanged: (value) async {
                      setState(() {
                        _serviceEnabled = value;
                      });

                      if (value && (!_hasNotificationAccess || !_hasLocationAlwaysEnabled || !_hasAppNotificationsEnabled)) {
                        await _requestPermissions();
                      }

                      await _saveSettings();
                      await _checkPermissions();
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
                        onChanged: (value) async{
                          _webhookUrl = value;
                          await _saveSettings();
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

                      SizedBox(
                        height: 300,
                        child: ListView.builder(
                          itemCount: _allApps.length,
                          itemBuilder: (context, index) {
                            final app = _allApps[index];
                            final packageName = app['packageName'];
                            final appName = app['appName'];

                            if (_searchController.text.isNotEmpty &&
                                !appName.toLowerCase().contains(_searchController.text.toLowerCase()) && 
                                !packageName.toLowerCase().contains(_searchController.text.toLowerCase())) {
                                  
                              return SizedBox.shrink();
                            }

                            return ListTile(
                              leading: FutureBuilder<File?> (
                                future: _loadAppIcon(packageName),
                                builder: (context, snapshot) {
                                  if (snapshot.connectionState == ConnectionState.done && snapshot.hasData) {
                                    return CircleAvatar(
                                      backgroundImage: FileImage(snapshot.data!),
                                      radius: 20
                                    );
                                  } else {
                                    return CircleAvatar(
                                      radius: 20,
                                      child: Icon(Icons.android)
                                    );
                                  }
                                },
                              ),
                              title: Text(appName),
                              trailing: Checkbox(
                                value: _selectedApps[packageName] ?? false,
                                onChanged: (value) async {
                                  setState(() {
                                    _selectedApps[packageName] = value ?? false;
                                  });
                                  await _saveSettings();
                                },
                              ),
                              onTap: () async {
                                setState(() {
                                  _selectedApps[packageName] = !(_selectedApps[packageName] ?? false);
                                });
                                await _saveSettings();
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
