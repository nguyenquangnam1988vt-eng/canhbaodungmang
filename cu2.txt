import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:http/http.dart' as http;
import 'package:background_fetch/background_fetch.dart';
import 'package:workmanager/workmanager.dart';
import 'dart:async';
import 'package:workmanager/workmanager.dart' as wm;

// ==================================================
// BACKGROUND TASK HANDLERS
// ==================================================

@pragma('vm:entry-point')
void backgroundFetchHeadlessTask(HeadlessTask task) async {
  String taskId = task.taskId;
  print("[BackgroundFetch] Headless task: $taskId");
  
  await initNotifications();
  await _performBackgroundNetworkCheck();
  
  BackgroundFetch.finish(taskId);
}

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    print("[WorkManager] Task executed: $task");
    await initNotifications();
    await _performBackgroundNetworkCheck();
    return Future.value(true);
  });
}

Future<void> _performBackgroundNetworkCheck() async {
  try {
    final connectivity = Connectivity();
    var result = await connectivity.checkConnectivity();
    
    String status = _getConnectionString(result);
    
    await showNotification(
      '📱 Mạng (Chạy nền)',
      'Kết nối: $status - ${DateTime.now().toString().substring(11, 16)}'
    );
    
    // Test network trong background
    final response = await http.get(Uri.parse('https://www.apple.com'))
      .timeout(Duration(seconds: 10));
      
    if (response.statusCode == 200) {
      await showNotification(
        '🌐 Kiểm tra nền',
        'Mạng hoạt động - Status: ${response.statusCode}'
      );
    }
  } catch (e) {
    print('Background network check failed: $e');
  }
}

String _getConnectionString(ConnectivityResult result) {
  switch (result) {
    case ConnectivityResult.wifi: return 'WiFi';
    case ConnectivityResult.mobile: return 'Mobile Data';
    case ConnectivityResult.ethernet: return 'Ethernet';
    default: return 'Mất kết nối';
  }
}

// ==================================================
// NOTIFICATION SETUP
// ==================================================

final FlutterLocalNotificationsPlugin notifications = FlutterLocalNotificationsPlugin();

Future<void> initNotifications() async {
  const AndroidInitializationSettings androidSettings = 
      AndroidInitializationSettings('@mipmap/ic_launcher');
  
  const DarwinInitializationSettings iosSettings =
      DarwinInitializationSettings(
    requestAlertPermission: true,
    requestBadgePermission: true,
    requestSoundPermission: true,
  );
  
  const InitializationSettings initSettings = InitializationSettings(
    android: androidSettings,
    iOS: iosSettings,
  );
  
  await notifications.initialize(initSettings);
}

Future<void> showNotification(String title, String body) async {
  const AndroidNotificationDetails androidPlatformChannelSpecifics =
      AndroidNotificationDetails(
    'network_channel',
    'Network Monitoring',
    channelDescription: 'Notifications for network activity',
    importance: Importance.high,
    priority: Priority.high,
    enableVibration: true,
  );
  
  const DarwinNotificationDetails iosPlatformChannelSpecifics =
      DarwinNotificationDetails(
    presentAlert: true,
    presentBadge: true,
    presentSound: true,
  );
  
  const NotificationDetails platformChannelSpecifics = NotificationDetails(
    android: androidPlatformChannelSpecifics,
    iOS: iosPlatformChannelSpecifics,
  );
  
  await notifications.show(
    DateTime.now().millisecondsSinceEpoch.remainder(100000),
    title,
    body,
    platformChannelSpecifics,
  );
}

// ==================================================
// MAIN APP
// ==================================================

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  await initNotifications();
  await Permission.notification.request();
  
  // KHỞI TẠO BACKGROUND SERVICES
  await _initBackgroundServices();
  
  runApp(MyApp());
}

Future<void> _initBackgroundServices() async {
  // Background Fetch (iOS)
  await BackgroundFetch.configure(
    BackgroundFetchConfig(
      minimumFetchInterval: 1, // 1 phút
      stopOnTerminate: false,
      enableHeadless: true,
      requiresBatteryNotLow: false,
      requiresCharging: false,
      requiresStorageNotLow: false,
      requiresDeviceIdle: false,
    ),
    (String taskId) async {
      print("[BackgroundFetch] Task executed: $taskId");
      await _performBackgroundNetworkCheck();
      BackgroundFetch.finish(taskId);
    },
  );

  // WorkManager (Android)
  await Workmanager().initialize(
    callbackDispatcher,
    isInDebugMode: true,
  );
  
  await Workmanager().registerPeriodicTask(
    "networkMonitor",
    "networkMonitoring",
    frequency: Duration(minutes: 1),
    constraints: wm.Constraints(
      networkType: wm.NetworkType.connected,
    ),
  );
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Network Monitor Background',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: NetworkMonitorScreen(),
    );
  }
}

class NetworkMonitorScreen extends StatefulWidget {
  @override
  _NetworkMonitorScreenState createState() => _NetworkMonitorScreenState();
}

class _NetworkMonitorScreenState extends State<NetworkMonitorScreen> 
    with WidgetsBindingObserver {
  
  final Connectivity _connectivity = Connectivity();
  final List<NetworkEvent> _networkEvents = [];
  
  String _connectionStatus = 'Đang kiểm tra...';
  String _networkActivity = 'Chưa có hoạt động';
  int _dataCounter = 0;
  bool _isMonitoring = false;
  Timer? _monitoringTimer;
  DateTime? _lastActivityTime;
  bool _isAppInForeground = true;
  
  final List<String> _testUrls = [
    'https://www.google.com',
    'https://www.apple.com',
    'https://jsonplaceholder.typicode.com/posts/1',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initNetworkListener();
    _startBackgroundMonitoring();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _monitoringTimer?.cancel();
    _stopBackgroundMonitoring();
    super.dispose();
  }

  // ==================================================
  // APP LIFECYCLE HANDLER
  // ==================================================

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    switch (state) {
      case AppLifecycleState.paused:
        print('App chuyển sang nền');
        _isAppInForeground = false;
        _onAppBackground();
        break;
      case AppLifecycleState.resumed:
        print('App chuyển sang foreground');
        _isAppInForeground = true;
        _onAppForeground();
        break;
      default:
        break;
    }
  }

  void _onAppBackground() {
    // Dừng foreground timer để tiết kiệm pin
    _monitoringTimer?.cancel();
    
    // Gửi thông báo app đang chạy nền
    showNotification(
      '🔍 Network Monitor',
      'App đang chạy nền. Vẫn giám sát mạng...'
    );
  }

  void _onAppForeground() {
    // Khởi động lại foreground monitoring
    if (_isMonitoring) {
      _startMonitoring();
    }
  }

  // ==================================================
  // BACKGROUND MONITORING CONTROL
  // ==================================================

  void _startBackgroundMonitoring() {
    // Bắt đầu background services
    BackgroundFetch.start().then((int status) {
      print('[BackgroundFetch] start success: $status');
      _addNetworkEvent('Bắt đầu giám sát nền');
    }).catchError((e) {
      print('[BackgroundFetch] start failure: $e');
    });
  }

  void _stopBackgroundMonitoring() {
    // Dừng background services
    BackgroundFetch.stop().then((int status) {
      print('[BackgroundFetch] stop success: $status');
      _addNetworkEvent('Dừng giám sát nền');
    });
  }

  // ==================================================
  // NETWORK MONITORING
  // ==================================================

  void _initNetworkListener() async {
    var initialResult = await _connectivity.checkConnectivity();
    _updateConnectionStatus(initialResult);
    
    _connectivity.onConnectivityChanged.listen((ConnectivityResult result) {
      _updateConnectionStatus(result);
    });
  }

  void _updateConnectionStatus(ConnectivityResult result) {
    String status = '';
    
    if (result == ConnectivityResult.wifi) {
      status = '📶 Đang kết nối WiFi';
    } else if (result == ConnectivityResult.mobile) {
      status = '📱 Đang kết nối Mobile Data';
    } else if (result == ConnectivityResult.ethernet) {
      status = '🔌 Đang kết nối Ethernet';
    } else {
      status = '❌ Mất kết nối Internet';
    }
    
    setState(() {
      _connectionStatus = status;
    });
    
    _addNetworkEvent('Thay đổi kết nối: $status');
    showNotification('Thay đổi kết nối', status);
  }

  void _startMonitoring() {
    setState(() {
      _isMonitoring = true;
      _dataCounter = 0;
      _networkActivity = 'Bắt đầu giám sát...';
    });
    
    _monitoringTimer = Timer.periodic(Duration(seconds: 10), (timer) {
      _simulateNetworkActivity();
    });
    
    _addNetworkEvent('Bắt đầu giám sát mạng');
    showNotification('Giám sát mạng', 'Đã bắt đầu theo dõi hoạt động mạng');
  }

  void _stopMonitoring() {
    _monitoringTimer?.cancel();
    setState(() {
      _isMonitoring = false;
      _networkActivity = 'Đã dừng giám sát';
    });
    
    _addNetworkEvent('Dừng giám sát mạng');
    showNotification('Giám sát mạng', 'Đã dừng theo dõi hoạt động mạng');
  }

  Future<void> _simulateNetworkActivity() async {
    try {
      for (String url in _testUrls) {
        final startTime = DateTime.now();
        final response = await http.get(Uri.parse(url)).timeout(Duration(seconds: 10));
        final endTime = DateTime.now();
        final duration = endTime.difference(startTime);
        
        if (response.statusCode == 200) {
          setState(() {
            _dataCounter++;
            _lastActivityTime = DateTime.now();
            _networkActivity = '🔄 Đang lướt mạng - Lần: $_dataCounter\n'
                              'Thời gian: ${duration.inMilliseconds}ms';
          });
          
          _addNetworkEvent('Phát hiện hoạt động mạng - Status: ${response.statusCode}');
          
          if (_dataCounter % 3 == 0) {
            showNotification(
              'Hoạt động mạng', 
              'Đã phát hiện $_dataCounter lần truy cập'
            );
          }
        }
      }
    } catch (e) {
      _addNetworkEvent('Lỗi kiểm tra mạng: $e');
    }
  }

  void _testSingleRequest() async {
    try {
      setState(() {
        _networkActivity = '🔄 Đang kiểm tra kết nối...';
      });
      
      final response = await http.get(Uri.parse('https://www.apple.com'));
      
      setState(() {
        _dataCounter++;
        _networkActivity = '✅ Kết nối thành công\n'
                          'Status: ${response.statusCode}\n'
                          'Thời gian: ${DateTime.now().toString().substring(11, 19)}';
      });
      
      _addNetworkEvent('Test request thành công: ${response.statusCode}');
      showNotification('Test mạng', 'Kết nối thành công - Status: ${response.statusCode}');
      
    } catch (e) {
      setState(() {
        _networkActivity = '❌ Lỗi kết nối: $e';
      });
      _addNetworkEvent('Test request thất bại: $e');
    }
  }

  void _addNetworkEvent(String description) {
    final event = NetworkEvent(
      description: description,
      timestamp: DateTime.now(),
    );
    
    setState(() {
      _networkEvents.insert(0, event);
      if (_networkEvents.length > 50) {
        _networkEvents.removeLast();
      }
    });
  }

  void _clearHistory() {
    setState(() {
      _networkEvents.clear();
    });
  }

  String _getConnectionStatusText() {
    if (_connectionStatus.contains('Mobile')) {
      return 'Kết nối Mobile Data';
    } else if (_connectionStatus.contains('WiFi')) {
      return 'Kết nối WiFi';
    } else if (_connectionStatus.contains('Ethernet')) {
      return 'Kết nối Ethernet';
    } else {
      return 'Không có kết nối';
    }
  }

  // ==================================================
  // UI BUILD
  // ==================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Network Monitor Background'),
        backgroundColor: Colors.blue,
        actions: [
          IconButton(
            icon: Icon(Icons.delete),
            onPressed: _clearHistory,
            tooltip: 'Xóa lịch sử',
          ),
          IconButton(
            icon: Icon(_isAppInForeground ? Icons.visibility : Icons.visibility_off),
            onPressed: () {},
            tooltip: _isAppInForeground ? 'Đang chạy foreground' : 'Đang chạy background',
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildStatusCard(),
            SizedBox(height: 20),
            _buildActivityCard(),
            SizedBox(height: 20),
            _buildControlButtons(),
            SizedBox(height: 20),
            Expanded(child: _buildEventHistory()),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard() {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Icon(
                  Icons.network_check,
                  size: 48,
                  color: _connectionStatus.contains('Mất kết nối') ? Colors.red : Colors.green,
                ),
                Column(
                  children: [
                    Icon(
                      _isAppInForeground ? Icons.visibility : Icons.visibility_off,
                      color: _isAppInForeground ? Colors.green : Colors.orange,
                    ),
                    Text(
                      _isAppInForeground ? 'Foreground' : 'Background',
                      style: TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ],
            ),
            SizedBox(height: 10),
            Text(
              'Trạng thái kết nối',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 5),
            Text(
              _connectionStatus,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: _connectionStatus.contains('Mất kết nối') ? Colors.red : Colors.green,
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 10),
            Text(
              'Số lần truy cập: $_dataCounter',
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
            if (_lastActivityTime != null)
              Text(
                'Lần cuối: ${_lastActivityTime!.toString().substring(11, 19)}',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildActivityCard() {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Hoạt động mạng',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                SizedBox(width: 10),
                _isMonitoring 
                  ? Icon(Icons.circle, color: Colors.green, size: 12)
                  : Icon(Icons.circle, color: Colors.red, size: 12),
              ],
            ),
            SizedBox(height: 10),
            Text(
              _networkActivity,
              style: TextStyle(
                fontSize: 14,
                color: _networkActivity.contains('Lỗi') ? Colors.red : Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControlButtons() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        ElevatedButton.icon(
          onPressed: _testSingleRequest,
          icon: Icon(Icons.wifi_find),
          label: Text('Test Mạng'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue,
            foregroundColor: Colors.white,
          ),
        ),
        ElevatedButton.icon(
          onPressed: _isMonitoring ? _stopMonitoring : _startMonitoring,
          icon: Icon(_isMonitoring ? Icons.stop : Icons.play_arrow),
          label: Text(_isMonitoring ? 'Dừng' : 'Bắt đầu'),
          style: ElevatedButton.styleFrom(
            backgroundColor: _isMonitoring ? Colors.red : Colors.green,
            foregroundColor: Colors.white,
          ),
        ),
      ],
    );
  }

  Widget _buildEventHistory() {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Text(
              'Lịch sử hoạt động (${_networkEvents.length})',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 10),
            Expanded(
              child: _networkEvents.isEmpty
                  ? Center(
                      child: Text(
                        'Chưa có hoạt động nào',
                        style: TextStyle(color: Colors.grey),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _networkEvents.length,
                      itemBuilder: (context, index) {
                        final event = _networkEvents[index];
                        return ListTile(
                          leading: Icon(Icons.history, size: 20),
                          title: Text(
                            event.description,
                            style: TextStyle(fontSize: 12),
                          ),
                          subtitle: Text(
                            '${event.timestamp.hour}:${event.timestamp.minute.toString().padLeft(2, '0')}:${event.timestamp.second.toString().padLeft(2, '0')}',
                            style: TextStyle(fontSize: 10),
                          ),
                          dense: true,
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class NetworkEvent {
  final String description;
  final DateTime timestamp;

  NetworkEvent({
    required this.description,
    required this.timestamp,
  });
}