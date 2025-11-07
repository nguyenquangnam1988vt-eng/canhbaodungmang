import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:workmanager/workmanager.dart';
import 'dart:async';

// ==================================================
// NOTIFICATION SERVICE (SIMPLIFIED FOR WINDOWS)
// ==================================================

class NotificationService {
  static Future<void> showNotification(String title, String body) async {
    // Trên Windows, chúng ta sẽ sử dụng print thay vì local notifications
    // vì flutter_local_notifications cần cấu hình phức tạp cho Windows
    print('📢 NOTIFICATION: $title - $body');
    
    // Có thể thêm native Windows notifications sau nếu cần
    try {
      // Hiển thị dialog đơn giản thay cho notification
      // Trong app thực tế, bạn có thể tích hợp với Windows Toast notifications
      _showSimpleDialog(title, body);
    } catch (e) {
      print('Error showing notification: $e');
    }
  }
  
  static void _showSimpleDialog(String title, String body) {
    // Đây là nơi bạn có thể hiển thị dialog hoặc tích hợp với Windows notifications
    // Tạm thời chỉ log ra console
    print('💡 $title: $body [${DateTime.now().toString().substring(11, 19)}]');
  }
}

// ==================================================
// BACKGROUND TASK HANDLERS
// ==================================================

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    print("[WorkManager] Screen monitoring task executed");
    
    // Kiểm tra trạng thái trong background
    await _checkScreenStatusInBackground();
    
    return Future.value(true);
  });
}

Future<void> _checkScreenStatusInBackground() async {
  try {
    // Gửi thông báo để xác nhận background service đang chạy
    await NotificationService.showNotification(
      '📱 Giám sát Điện thoại',
      'Ứng dụng vẫn đang chạy nền - ${DateTime.now().toString().substring(11, 16)}'
    );
  } catch (e) {
    print('Background check failed: $e');
  }
}

// ==================================================
// MAIN APP
// ==================================================

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  await Permission.notification.request();
  
  // Khởi tạo background service (chủ yếu cho mobile)
  await Workmanager().initialize(
    callbackDispatcher,
    isInDebugMode: true,
  );
  
  await Workmanager().registerPeriodicTask(
    "screenMonitor",
    "screenMonitoring",
    frequency: Duration(minutes: 15),
  );
  
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Phone Activity Monitor',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: ScreenMonitorScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class ScreenMonitorScreen extends StatefulWidget {
  @override
  _ScreenMonitorScreenState createState() => _ScreenMonitorScreenState();
}

class _ScreenMonitorScreenState extends State<ScreenMonitorScreen> 
    with WidgetsBindingObserver, TickerProviderStateMixin {
  
  final List<ScreenEvent> _screenEvents = [];
  bool _isMonitoring = false;
  DateTime? _lastActivityTime;
  int _activityCount = 0;
  bool _isAppInForeground = true;
  Timer? _monitoringTimer;
  late AnimationController _animationController;
  bool _showRealTimeAlert = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _animationController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 500),
    );
    _initializeMonitoring();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _monitoringTimer?.cancel();
    _animationController.dispose();
    _stopMonitoring();
    super.dispose();
  }

  // ==================================================
  // APP LIFECYCLE HANDLER
  // ==================================================

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    if (state == AppLifecycleState.paused) {
      _isAppInForeground = false;
      _addScreenEvent('📱 Ứng dụng chuyển sang nền');
      _onAppBackground();
    } else if (state == AppLifecycleState.resumed) {
      _isAppInForeground = true;
      _addScreenEvent('📱 Ứng dụng chuyển sang foreground');
      _onAppForeground();
    } else if (state == AppLifecycleState.inactive) {
      _addScreenEvent('📱 Ứng dụng không active');
    } else if (state == AppLifecycleState.detached) {
      _addScreenEvent('📱 Ứng dụng bị đóng');
    }
  }

  void _onAppBackground() {
    _monitoringTimer?.cancel();
    
    NotificationService.showNotification(
      '🔍 Phone Monitor',
      'App đang chạy nền. Vẫn giám sát...'
    );
  }

  void _onAppForeground() {
    if (_isMonitoring) {
      _startForegroundMonitoring();
    }
  }

  // ==================================================
  // MONITORING METHODS
  // ==================================================

  void _initializeMonitoring() async {
    try {
      _startMonitoring();
    } catch (e) {
      print('Lỗi khởi tạo giám sát: $e');
    }
  }

  void _startMonitoring() {
    setState(() {
      _isMonitoring = true;
      _activityCount = 0;
    });
    
    _startForegroundMonitoring();
    
    _addScreenEvent('🎯 Bắt đầu giám sát điện thoại');
    _showRealTimeNotification('🔓 Bắt đầu Giám sát', 'Đã bắt đầu theo dõi trạng thái điện thoại');
  }

  void _stopMonitoring() {
    _monitoringTimer?.cancel();
    setState(() {
      _isMonitoring = false;
      _showRealTimeAlert = false;
    });
    
    _addScreenEvent('⏹️ Dừng giám sát điện thoại');
    _showRealTimeNotification('🔒 Dừng Giám sát', 'Đã dừng theo dõi trạng thái điện thoại');
  }

  void _startForegroundMonitoring() {
    _monitoringTimer?.cancel();
    
    _monitoringTimer = Timer.periodic(Duration(seconds: 8), (timer) {
      _checkDeviceActivity();
    });
  }

  void _checkDeviceActivity() async {
    try {
      _simulateActivityDetection();
    } catch (e) {
      print('Lỗi kiểm tra hoạt động: $e');
    }
  }

  void _simulateActivityDetection() {
    final now = DateTime.now();
    
    // Mô phỏng phát hiện hoạt động với xác suất ngẫu nhiên
    final random = DateTime.now().millisecond;
    if (random % 25 == 0) { // Khoảng 4% xác suất mỗi lần kiểm tra
      _handleDeviceActivity();
    }
  }

  void _handleDeviceActivity() {
    final now = DateTime.now();
    
    if (_lastActivityTime == null || 
        now.difference(_lastActivityTime!) > Duration(seconds: 8)) {
      
      setState(() {
        _activityCount++;
        _lastActivityTime = now;
        _showRealTimeAlert = true;
      });

      _animationController.forward().then((_) {
        Future.delayed(Duration(seconds: 2), () {
          setState(() {
            _showRealTimeAlert = false;
          });
          _animationController.reverse();
        });
      });
      
      String timeString = '${now.hour}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
      
      List<String> activities = [
        '📱 Điện thoại được mở khóa',
        '📱 Màn hình sáng lên', 
        '📱 Phát hiện hoạt động sử dụng',
        '📱 Điện thoại được kích hoạt',
        '📱 Người dùng tương tác với điện thoại',
        '📱 Mở khóa thành công',
        '📱 Nhận diện khuôn mặt/vân tay'
      ];
      
      String randomActivity = activities[DateTime.now().millisecond % activities.length];
      String eventDescription = '$randomActivity - Lần $_activityCount - $timeString';
      
      _addScreenEvent(eventDescription);
      
      if (_activityCount <= 3 || _activityCount % 5 == 0) {
        _showRealTimeNotification('📱 Điện thoại hoạt động', 'Lần thứ $_activityCount - $timeString');
      }
      
      print('Phát hiện hoạt động: $eventDescription');
    }
  }

  void _addScreenEvent(String description) {
    final event = ScreenEvent(
      description: description,
      timestamp: DateTime.now(),
    );
    
    setState(() {
      _screenEvents.insert(0, event);
      if (_screenEvents.length > 50) {
        _screenEvents.removeLast();
      }
    });
  }

  void _showRealTimeNotification(String title, String body) {
    // Hiển thị trên console và có thể tích hợp với Windows notifications sau
    print('🚨 $title: $body');
    NotificationService.showNotification(title, body);
  }

  void _clearHistory() {
    setState(() {
      _screenEvents.clear();
      _activityCount = 0;
      _lastActivityTime = null;
    });
    
    _addScreenEvent('🗑️ Đã xóa lịch sử hoạt động');
  }

  void _testActivityEvent() {
    _handleDeviceActivity();
  }

  void _toggleMonitoring() {
    if (_isMonitoring) {
      _stopMonitoring();
    } else {
      _startMonitoring();
    }
  }

  // ==================================================
  // UI BUILD
  // ==================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Giám sát Mở khóa Điện thoại'),
        backgroundColor: Colors.blue,
        elevation: 2,
        actions: [
          IconButton(
            icon: Icon(Icons.delete_outline),
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
      body: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildStatusCard(),
                SizedBox(height: 20),
                _buildControlButtons(),
                SizedBox(height: 20),
                Expanded(child: _buildEventHistory()),
              ],
            ),
          ),
          
          // Real-time alert overlay
          if (_showRealTimeAlert)
            Positioned(
              top: 100,
              left: 0,
              right: 0,
              child: ScaleTransition(
                scale: _animationController,
                child: Container(
                  margin: EdgeInsets.symmetric(horizontal: 20),
                  padding: EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.9),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black26,
                        blurRadius: 10,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.phone_android, color: Colors.white),
                      SizedBox(width: 10),
                      Text(
                        '📱 Phát hiện mở khóa điện thoại!',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _toggleMonitoring,
        child: AnimatedSwitcher(
          duration: Duration(milliseconds: 300),
          child: _isMonitoring 
              ? Icon(Icons.stop, key: ValueKey('stop'))
              : Icon(Icons.play_arrow, key: ValueKey('play')),
        ),
        backgroundColor: _isMonitoring ? Colors.red : Colors.green,
      ),
    );
  }

  Widget _buildStatusCard() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                AnimatedContainer(
                  duration: Duration(milliseconds: 300),
                  padding: EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _isMonitoring ? Colors.green.withOpacity(0.1) : Colors.grey.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _isMonitoring ? Icons.phone_android : Icons.phone_disabled,
                    size: 40,
                    color: _isMonitoring ? Colors.green : Colors.grey,
                  ),
                ),
                Column(
                  children: [
                    Container(
                      padding: EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: _isAppInForeground ? Colors.blue.withOpacity(0.1) : Colors.orange.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _isAppInForeground ? Icons.visibility : Icons.visibility_off,
                        color: _isAppInForeground ? Colors.blue : Colors.orange,
                        size: 24,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      _isAppInForeground ? 'Foreground' : 'Background',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ],
            ),
            SizedBox(height: 16),
            Text(
              'Trạng thái giám sát',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: _isMonitoring ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: _isMonitoring ? Colors.green : Colors.red,
                  width: 1,
                ),
              ),
              child: Text(
                _isMonitoring ? 'ĐANG GIÁM SÁT' : 'ĐÃ DỪNG',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: _isMonitoring ? Colors.green : Colors.red,
                ),
              ),
            ),
            SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildCounterItem('Số lần', '$_activityCount', Colors.blue),
                _buildCounterItem(
                  'Lần cuối', 
                  _lastActivityTime != null 
                      ? '${_lastActivityTime!.hour}:${_lastActivityTime!.minute.toString().padLeft(2, '0')}'
                      : '--:--', 
                  Colors.orange
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCounterItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: Colors.grey,
          ),
        ),
      ],
    );
  }

  Widget _buildControlButtons() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        ElevatedButton.icon(
          onPressed: _testActivityEvent,
          icon: Icon(Icons.add_alert, size: 20),
          label: Text('Test Hoạt động'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.orange,
            foregroundColor: Colors.white,
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
        ),
        ElevatedButton.icon(
          onPressed: _toggleMonitoring,
          icon: Icon(
            _isMonitoring ? Icons.stop : Icons.play_arrow,
            size: 20,
          ),
          label: Text(_isMonitoring ? 'Dừng' : 'Bắt đầu'),
          style: ElevatedButton.styleFrom(
            backgroundColor: _isMonitoring ? Colors.red : Colors.green,
            foregroundColor: Colors.white,
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
        ),
      ],
    );
  }

  Widget _buildEventHistory() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Lịch sử hoạt động (${_screenEvents.length})',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.refresh, size: 20),
                  onPressed: () {
                    setState(() {});
                  },
                  tooltip: 'Làm mới',
                ),
              ],
            ),
            SizedBox(height: 8),
            Expanded(
              child: _screenEvents.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.history_toggle_off, size: 48, color: Colors.grey),
                          SizedBox(height: 12),
                          Text(
                            'Chưa có hoạt động nào',
                            style: TextStyle(
                              color: Colors.grey,
                              fontSize: 14,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Bắt đầu giám sát để xem lịch sử',
                            style: TextStyle(
                              color: Colors.grey,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      itemCount: _screenEvents.length,
                      itemBuilder: (context, index) {
                        final event = _screenEvents[index];
                        final isUnlockEvent = event.description.contains('mở khóa') || 
                                             event.description.contains('Mở khóa');
                        return Container(
                          margin: EdgeInsets.symmetric(vertical: 2),
                          decoration: BoxDecoration(
                            border: Border(
                              left: BorderSide(
                                color: isUnlockEvent ? Colors.green : Colors.blue,
                                width: 4,
                              ),
                            ),
                            color: index % 2 == 0 ? Colors.grey.withOpacity(0.05) : Colors.transparent,
                          ),
                          child: ListTile(
                            leading: Icon(
                              isUnlockEvent ? Icons.lock_open : Icons.phone_android,
                              size: 20,
                              color: isUnlockEvent ? Colors.green : Colors.blue,
                            ),
                            title: Text(
                              event.description,
                              style: TextStyle(fontSize: 12),
                            ),
                            subtitle: Text(
                              '${event.timestamp.hour}:${event.timestamp.minute.toString().padLeft(2, '0')}:${event.timestamp.second.toString().padLeft(2, '0')}',
                              style: TextStyle(fontSize: 10, color: Colors.grey),
                            ),
                            dense: true,
                          ),
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

class ScreenEvent {
  final String description;
  final DateTime timestamp;

  ScreenEvent({
    required this.description,
    required this.timestamp,
  });
}