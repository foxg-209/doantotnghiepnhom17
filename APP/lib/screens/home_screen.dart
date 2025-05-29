import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class HomeScreen extends StatefulWidget {
  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final supabase = Supabase.instance.client;
  int _currentIndex = 0;

  // Trạng thái thiết bị
  bool lampOn = false;
  bool doorOpen = false;
  int fanSpeed = 0;
  bool powerOn = false;
  double powerConsumption = 0.0;
  double temperature = 0.0;
  double humidity = 0.0;
  double voltage = 0.0;
  double current = 0.0;
  Map<String, dynamic>? userProfile;

  // Trạng thái kịch bản quạt
  double? temperatureThreshold;
  bool fanShouldBeOn = false;
  String temperatureCondition = 'greater';
  bool isFanScenarioActive = false;
  DateTime? timerStart;
  DateTime? timerEnd;
  List<String> selectedDays = [];
  final List<String> allDays = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
  final TextEditingController _tempThresholdController = TextEditingController();

  // Trạng thái kịch bản đèn
  bool lampShouldBeOn = false;
  bool isLampScenarioActive = false;
  DateTime? lampTimerStart;
  DateTime? lampTimerEnd;
  List<String> lampSelectedDays = [];

  // Định nghĩa các chế độ quạt
  final List<Map<String, dynamic>> fanModes = [
    {'label': 'Tắt', 'value': 0, 'icon': Icons.power_off, 'color': Colors.grey},
    {'label': 'Vừa', 'value': 128, 'icon': Icons.air, 'color': Colors.blueAccent},
    {'label': 'Mạnh', 'value': 255, 'icon': Icons.storm, 'color': Colors.teal},
  ];
  int selectedFanModeIndex = 0;

  @override
  void initState() {
    super.initState();
    _loadDeviceState();
    _loadUserProfile();
    _loadScenario();
    _subscribeToRealtime();
  }

  Future<void> _loadDeviceState() async {
    final response = await supabase.from('devices').select();
    setState(() {
      for (var device in response) {
        if (device['device_name'] == 'lamp') lampOn = device['state'] == 'ON';
        if (device['device_name'] == 'fan') fanSpeed = int.parse(device['state'] ?? '0');
        if (device['device_name'] == 'power') powerOn = device['state'] == 'ON';
        if (device['device_name'] == 'door') doorOpen = device['state'] == 'OPEN';
        if (device['device_name'] == 'power_consumption') powerConsumption = double.parse(device['state'] ?? '0.0');
        if (device['device_name'] == 'temperature') temperature = double.parse(device['state'] ?? '0.0');
        if (device['device_name'] == 'humidity') humidity = double.parse(device['state'] ?? '0.0');
        if (device['device_name'] == 'voltage') voltage = double.parse(device['state'] ?? '0.0');
        if (device['device_name'] == 'current') current = double.parse(device['state'] ?? '0.0');
      }
    });
  }

  Future<void> _loadUserProfile() async {
    final user = supabase.auth.currentUser;
    if (user != null) {
      final response = await supabase
          .from('user_profiles')
          .select()
          .eq('id', user.id)
          .maybeSingle();
      setState(() {
        userProfile = response;
      });
    }
  }

  Future<void> _loadScenario() async {
    try {
      // Tải kịch bản cho quạt
      final fanResponse = await supabase
          .from('scenarios')
          .select()
          .eq('device_name', 'fan')
          .maybeSingle();
      if (fanResponse != null) {
        setState(() {
          temperatureThreshold = fanResponse['temperature_threshold']?.toDouble();
          fanShouldBeOn = fanResponse['device_state'] == '128';
          temperatureCondition = fanResponse['temperature_condition'] ?? 'greater';
          isFanScenarioActive = fanResponse['is_active'] ?? false;
          timerStart = fanResponse['timer_start'] != null
              ? DateTime.parse(fanResponse['timer_start']).toLocal()
              : null;
          timerEnd = fanResponse['timer_end'] != null
              ? DateTime.parse(fanResponse['timer_end']).toLocal()
              : null;
          selectedDays = fanResponse['days_of_week'] != null
              ? (fanResponse['days_of_week'] as String).split(',')
              : [];
        });
      }

      // Tải kịch bản cho đèn
      final lampResponse = await supabase
          .from('scenarios')
          .select()
          .eq('device_name', 'lamp')
          .maybeSingle();
      if (lampResponse != null) {
        setState(() {
          lampShouldBeOn = lampResponse['device_state'] == 'ON';
          isLampScenarioActive = lampResponse['is_active'] ?? false;
          lampTimerStart = lampResponse['timer_start'] != null
              ? DateTime.parse(lampResponse['timer_start']).toLocal()
              : null;
          lampTimerEnd = lampResponse['timer_end'] != null
              ? DateTime.parse(lampResponse['timer_end']).toLocal()
              : null;
          lampSelectedDays = lampResponse['days_of_week'] != null
              ? (fanResponse['days_of_week'] as String).split(',')
              : [];
        });
      }
    } catch (e) {
      print('Lỗi khi tải kịch bản: $e');
    }
  }

  void _subscribeToRealtime() {
    supabase
        .channel('devices')
        .on(
      RealtimeListenTypes.postgresChanges,
      ChannelFilter(event: 'UPDATE', schema: 'public', table: 'devices'),
          (payload, [ref]) {
        if (payload['new'] != null) {
          final deviceName = payload['new']['device_name'] as String;
          final state = payload['new']['state'] as String;
          setState(() {
            if (deviceName == 'lamp') lampOn = state == 'ON';
            if (deviceName == 'fan') {
              fanSpeed = int.tryParse(state) ?? 0;
              selectedFanModeIndex = fanModes.indexWhere((mode) => mode['value'] == fanSpeed);
              if (selectedFanModeIndex == -1) selectedFanModeIndex = 0;
            }
            if (deviceName == 'power') powerOn = state == 'ON';
            if (deviceName == 'door') doorOpen = state == 'OPEN';
            if (deviceName == 'power_consumption') powerConsumption = double.tryParse(state) ?? 0.0;
            if (deviceName == 'temperature') {
              temperature = double.tryParse(state) ?? 0.0;
              _checkTemperatureScenario();
            }
            if (deviceName == 'humidity') humidity = double.tryParse(state) ?? 0.0;
            if (deviceName == 'voltage') voltage = double.tryParse(state) ?? 0.0;
            if (deviceName == 'current') current = double.tryParse(state) ?? 0.0;
          });
        }
      },
    )
        .subscribe();
  }

  void _checkTemperatureScenario() {
    if (isFanScenarioActive && temperatureThreshold != null) {
      bool conditionMet = false;
      if (temperatureCondition == 'greater') {
        conditionMet = temperature > temperatureThreshold!;
      } else if (temperatureCondition == 'equal') {
        conditionMet = (temperature - temperatureThreshold!).abs() < 0.1;
      } else if (temperatureCondition == 'less') {
        conditionMet = temperature < temperatureThreshold!;
      }

      bool isWithinTimer = false;
      final now = DateTime.now();
      final currentDay = ['SUN', 'MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT'][now.weekday % 7];
      if (timerStart != null && timerEnd != null && selectedDays.contains(currentDay)) {
        final startTime = DateTime(now.year, now.month, now.day, timerStart!.hour, timerStart!.minute);
        final endTime = DateTime(now.year, now.month, now.day, timerEnd!.hour, timerEnd!.minute);
        isWithinTimer = now.isAfter(startTime) && now.isBefore(endTime);
      }

      if (conditionMet && (isWithinTimer || (timerStart == null && timerEnd == null))) {
        if (fanShouldBeOn && fanSpeed == 0) {
          _sendCommand('fan', '128');
          setState(() {
            fanSpeed = 128;
            selectedFanModeIndex = 1;
          });
        } else if (!fanShouldBeOn && fanSpeed != 0) {
          _sendCommand('fan', '0');
          setState(() {
            fanSpeed = 0;
            selectedFanModeIndex = 0;
          });
        }
      }
    }
  }

  Future<void> _sendCommand(String device, String state) async {
    try {
      await supabase.from('devices').upsert(
        {'device_name': device, 'state': state},
        onConflict: 'device_name',
      );

      final user = supabase.auth.currentUser;
      if (user != null) {
        await supabase.from('history').insert({
          'device_id': device,
          'action': state,
          'user_id': user.id,
          'timestamp': DateTime.now().toUtc().toIso8601String(),
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Lỗi: $e')),
      );
    }
  }

  Future<void> _saveFanScenario() async {
    final thresholdText = _tempThresholdController.text.trim();
    if (thresholdText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng nhập ngưỡng nhiệt độ!')),
      );
      return;
    }
    final threshold = double.tryParse(thresholdText);
    if (threshold == null || threshold < 0 || threshold > 100) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nhiệt độ không hợp lệ! Vui lòng nhập từ 0 đến 100 °C.')),
      );
      return;
    }

    final data = {
      'device_name': 'fan',
      'temperature_threshold': threshold,
      'device_state': fanShouldBeOn ? '128' : '0',
      'temperature_condition': temperatureCondition,
      'is_active': isFanScenarioActive,
      'timer_start': timerStart?.toUtc().toIso8601String(),
      'timer_end': timerEnd?.toUtc().toIso8601String(),
      'days_of_week': selectedDays.isNotEmpty ? selectedDays.join(',') : null,
    };

    try {
      await supabase.from('scenarios').upsert(data, onConflict: 'device_name');
      _tempThresholdController.clear();
      final conditionText = temperatureCondition == 'greater' ? '>' : temperatureCondition == 'equal' ? '=' : '<';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Đã thiết lập kịch bản: Quạt sẽ ${fanShouldBeOn ? 'bật' : 'tắt'} khi nhiệt độ $conditionText $threshold °C.',
          ),
        ),
      );
      _checkTemperatureScenario();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Lỗi khi lưu kịch bản: $e')),
      );
    }
  }

  Future<void> _saveLampScenario() async {
    if (lampTimerStart == null || lampTimerEnd == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng chọn thời gian bắt đầu và kết thúc!')),
      );
      return;
    }

    final data = {
      'device_name': 'lamp',
      'device_state': lampShouldBeOn ? 'ON' : 'OFF',
      'is_active': isLampScenarioActive,
      'timer_start': lampTimerStart?.toUtc().toIso8601String(),
      'timer_end': lampTimerEnd?.toUtc().toIso8601String(),
      'days_of_week': lampSelectedDays.isNotEmpty ? lampSelectedDays.join(',') : null,
    };

    try {
      await supabase.from('scenarios').upsert(data, onConflict: 'device_name');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Đã thiết lập kịch bản: Đèn sẽ ${lampShouldBeOn ? 'bật' : 'tắt'} từ ${lampTimerStart!.toString().substring(11, 16)} đến ${lampTimerEnd!.toString().substring(11, 16)}.',
          ),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Lỗi khi lưu kịch bản: $e')),
      );
    }
  }

  Future<void> _selectTime(BuildContext context, bool isStart, {bool isLamp = false}) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (picked != null) {
      final now = DateTime.now();
      final selectedDateTime = DateTime(
        now.year,
        now.month,
        now.day,
        picked.hour,
        picked.minute,
      );
      setState(() {
        if (isLamp) {
          if (isStart) {
            lampTimerStart = selectedDateTime;
          } else {
            lampTimerEnd = selectedDateTime;
          }
        } else {
          if (isStart) {
            timerStart = selectedDateTime;
          } else {
            timerEnd = selectedDateTime;
          }
        }
      });
    }
  }

  Future<void> _logout() async {
    await supabase.auth.signOut();
    Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
  }

  Future<void> _changePassword() async {
    final TextEditingController newPasswordController = TextEditingController();
    final TextEditingController confirmPasswordController = TextEditingController();

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Đổi mật khẩu'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: newPasswordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Mật khẩu mới',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: confirmPasswordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Xác nhận mật khẩu',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            onPressed: () async {
              final newPassword = newPasswordController.text.trim();
              final confirmPassword = confirmPasswordController.text.trim();

              if (newPassword.isEmpty || confirmPassword.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Vui lòng nhập đầy đủ thông tin!')),
                );
                return;
              }

              if (newPassword != confirmPassword) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Mật khẩu không khớp!')),
                );
                return;
              }

              try {
                await supabase.auth.updateUser(
                  UserAttributes(password: newPassword),
                );
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Đổi mật khẩu thành công!')),
                );
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Lỗi: $e')),
                );
              }
            },
            child: const Text('Xác nhận'),
          ),
        ],
      ),
    );
  }

  Future<void> _changeName() async {
    final TextEditingController nameController = TextEditingController(text: userProfile?['full_name']);

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Đổi tên'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(
            labelText: 'Họ và tên mới',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            onPressed: () async {
              final newName = nameController.text.trim();
              if (newName.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Vui lòng nhập tên!')),
                );
                return;
              }

              try {
                await supabase
                    .from('user_profiles')
                    .update({'full_name': newName})
                    .eq('id', supabase.auth.currentUser!.id);
                await _loadUserProfile();
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Đổi tên thành công!')),
                );
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Lỗi: $e')),
                );
              }
            },
            child: const Text('Xác nhận'),
          ),
        ],
      ),
    );
  }

  Future<void> _changeDateOfBirth() async {
    DateTime? selectedDate = userProfile != null
        ? DateTime.parse(userProfile!['date_of_birth'])
        : DateTime.now();

    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: selectedDate,
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: ThemeData.light().copyWith(
            colorScheme: const ColorScheme.light(
              primary: Colors.teal,
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Colors.black,
            ),
            dialogBackgroundColor: Colors.white,
          ),
          child: child!,
        );
      },
    );

    if (picked != null && picked != selectedDate) {
      try {
        await supabase
            .from('user_profiles')
            .update({'date_of_birth': picked.toIso8601String()})
            .eq('id', supabase.auth.currentUser!.id);
        await _loadUserProfile();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đổi ngày sinh thành công!')),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Smart Home Control',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        backgroundColor: Colors.teal[800],
        elevation: 4,
        centerTitle: true,
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: [
          _buildDeviceControlTab(),
          _buildSmartScenarioTab(),
          _buildSupportTab(),
          _buildProfileTab(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        type: BottomNavigationBarType.fixed,
        selectedItemColor: Colors.teal,
        unselectedItemColor: Colors.grey,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.devices),
            label: 'Thiết bị',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.schedule),
            label: 'Kịch bản',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.support),
            label: 'Hỗ trợ',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person),
            label: 'Cá nhân',
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceControlTab() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.teal.shade50, Colors.white],
        ),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Điều khiển thiết bị',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.teal,
              ),
            ),
            const SizedBox(height: 16),
            _buildDeviceCard(
              icon: Icons.lightbulb_outline,
              title: 'Đèn',
              subtitle: lampOn ? 'Bật' : 'Tắt',
              trailing: Switch(
                value: lampOn,
                activeColor: Colors.teal,
                onChanged: (value) {
                  setState(() => lampOn = value);
                  _sendCommand("lamp", value ? "ON" : "OFF");
                },
              ),
            ),
            _buildDeviceCard(
              icon: Icons.air,
              title: 'Quạt',
              subtitle: 'Chế độ: ${fanModes[selectedFanModeIndex]['label']}',
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: fanModes.asMap().entries.map((entry) {
                  int index = entry.key;
                  Map<String, dynamic> mode = entry.value;
                  bool isSelected = selectedFanModeIndex == index;
                  return ElevatedButton(
                    onPressed: () {
                      setState(() {
                        selectedFanModeIndex = index;
                        fanSpeed = mode['value'];
                      });
                      _sendCommand("fan", fanSpeed.toString());
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isSelected ? mode['color'] : Colors.grey[200],
                      foregroundColor: isSelected ? Colors.white : Colors.black87,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
                          color: isSelected ? mode['color'] : Colors.grey,
                          width: 2,
                        ),
                      ),
                      elevation: isSelected ? 8 : 2,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(mode['icon'], size: 20),
                        const SizedBox(width: 8),
                        Text(
                          mode['label'],
                          style: const TextStyle(fontSize: 16),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
            _buildDeviceCard(
              icon: Icons.door_front_door_outlined,
              title: 'Cửa',
              subtitle: doorOpen ? 'Mở' : 'Đóng',
              trailing: ElevatedButton(
                onPressed: () {
                  setState(() => doorOpen = !doorOpen);
                  _sendCommand("door", doorOpen ? "OPEN" : "CLOSE");
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: doorOpen ? Colors.redAccent : Colors.teal,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  doorOpen ? 'Đóng cửa' : 'Mở cửa',
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            ),
            _buildDeviceCard(
              icon: Icons.power,
              title: 'Ổ điện',
              subtitle: powerOn ? 'Bật' : 'Tắt',
              trailing: Switch(
                value: powerOn,
                activeColor: Colors.teal,
                onChanged: (value) {
                  setState(() => powerOn = value);
                  _sendCommand("power", value ? "ON" : "OFF");
                },
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Thông tin môi trường',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.teal,
              ),
            ),
            const SizedBox(height: 16),
            _buildInfoCard(
              icon: Icons.electric_bolt,
              title: 'Điện tiêu thụ',
              value: '$powerConsumption kWh',
              color: Colors.orange,
            ),
            _buildInfoCard(
              icon: Icons.thermostat,
              title: 'Nhiệt độ',
              value: '$temperature °C',
              color: Colors.red,
            ),
            _buildInfoCard(
              icon: Icons.water_drop,
              title: 'Độ ẩm',
              value: '$humidity %',
              color: Colors.blue,
            ),
            _buildInfoCard(
              icon: Icons.bolt,
              title: 'Điện áp',
              value: '$voltage V',
              color: Colors.purple,
            ),
            _buildInfoCard(
              icon: Icons.electrical_services,
              title: 'Dòng điện',
              value: '$current A',
              color: Colors.green,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSmartScenarioTab() {
    return Container(
      width: MediaQuery.of(context).size.width,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.teal.shade50, Colors.white],
        ),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 16.0),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: MediaQuery.of(context).size.height -
                MediaQuery.of(context).padding.top -
                kToolbarHeight -
                kBottomNavigationBarHeight,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16.0),
                  child: Text(
                    'Kịch bản thông minh',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.teal,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  elevation: 4,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  margin: const EdgeInsets.only(bottom: 16, left: 16, right: 16),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Hẹn giờ bật/tắt đèn',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Text(
                              'Trạng thái đèn: ',
                              style: TextStyle(fontSize: 16),
                            ),
                            DropdownButton<bool>(
                              value: lampShouldBeOn,
                              items: const [
                                DropdownMenuItem(
                                  value: true,
                                  child: Text('Bật'),
                                ),
                                DropdownMenuItem(
                                  value: false,
                                  child: Text('Tắt'),
                                ),
                              ],
                              onChanged: (value) {
                                setState(() {
                                  lampShouldBeOn = value!;
                                });
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Hẹn giờ:',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        ListTile(
                          title: Text(
                            'Thời gian bắt đầu: ${lampTimerStart != null ? lampTimerStart!.toString().substring(11, 16) : 'Chưa chọn'}',
                          ),
                          onTap: () => _selectTime(context, true, isLamp: true),
                        ),
                        ListTile(
                          title: Text(
                            'Thời gian kết thúc: ${lampTimerEnd != null ? lampTimerEnd!.toString().substring(11, 16) : 'Chưa chọn'}',
                          ),
                          onTap: () => _selectTime(context, false, isLamp: true),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Ngày áp dụng:',
                          style: TextStyle(fontSize: 16),
                        ),
                        Wrap(
                          spacing: 8.0,
                          children: allDays.map((day) {
                            return FilterChip(
                              label: Text(day),
                              selected: lampSelectedDays.contains(day),
                              onSelected: (selected) {
                                setState(() {
                                  if (selected) {
                                    lampSelectedDays.add(day);
                                  } else {
                                    lampSelectedDays.remove(day);
                                  }
                                });
                              },
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            ElevatedButton(
                              onPressed: () {
                                setState(() {
                                  isLampScenarioActive = true;
                                });
                                _saveLampScenario();
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.teal,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              child: const Text('Lưu kịch bản'),
                            ),
                            if (isLampScenarioActive)
                              ElevatedButton(
                                onPressed: () async {
                                  setState(() {
                                    isLampScenarioActive = false;
                                    lampTimerStart = null;
                                    lampTimerEnd = null;
                                    lampSelectedDays = [];
                                  });
                                  try {
                                    await supabase.from('scenarios').upsert(
                                      {
                                        'device_name': 'lamp',
                                        'device_state': 'OFF',
                                        'is_active': false,
                                        'timer_start': null,
                                        'timer_end': null,
                                        'days_of_week': null,
                                      },
                                      onConflict: 'device_name',
                                    );
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Đã hủy kịch bản đèn.')),
                                    );
                                  } catch (e) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('Lỗi khi hủy kịch bản: $e')),
                                    );
                                  }
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.redAccent,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                child: const Text('Hủy kịch bản'),
                              ),
                          ],
                        ),
                        if (isLampScenarioActive) ...[
                          const SizedBox(height: 8),
                          Text(
                            'Kịch bản hiện tại: Đèn sẽ ${lampShouldBeOn ? 'bật' : 'tắt'} từ ${lampTimerStart?.toString().substring(11, 16)} đến ${lampTimerEnd?.toString().substring(11, 16)}.',
                            style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                Card(
                  elevation: 4,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  margin: const EdgeInsets.only(bottom: 16, left: 16, right: 16),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Bật/Tắt quạt theo nhiệt độ',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Nhiệt độ hiện tại: $temperature °C',
                          style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _tempThresholdController,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: 'Nhập ngưỡng nhiệt độ (°C)',
                            border: OutlineInputBorder(),
                            hintText: 'Ví dụ: 30',
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Text(
                              'Điều kiện: ',
                              style: TextStyle(fontSize: 16),
                            ),
                            DropdownButton<String>(
                              value: temperatureCondition,
                              items: const [
                                DropdownMenuItem(
                                  value: 'greater',
                                  child: Text('Lớn hơn'),
                                ),
                                DropdownMenuItem(
                                  value: 'equal',
                                  child: Text('Bằng'),
                                ),
                                DropdownMenuItem(
                                  value: 'less',
                                  child: Text('Nhỏ hơn'),
                                ),
                              ],
                              onChanged: (value) {
                                setState(() {
                                  temperatureCondition = value!;
                                });
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Text(
                              'Trạng thái quạt: ',
                              style: TextStyle(fontSize: 16),
                            ),
                            DropdownButton<bool>(
                              value: fanShouldBeOn,
                              items: const [
                                DropdownMenuItem(
                                  value: true,
                                  child: Text('Bật'),
                                ),
                                DropdownMenuItem(
                                  value: false,
                                  child: Text('Tắt'),
                                ),
                              ],
                              onChanged: (value) {
                                setState(() {
                                  fanShouldBeOn = value!;
                                });
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Hẹn giờ:',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        ListTile(
                          title: Text(
                            'Thời gian bắt đầu: ${timerStart != null ? timerStart!.toString().substring(11, 16) : 'Chưa chọn'}',
                          ),
                          onTap: () => _selectTime(context, true),
                        ),
                        ListTile(
                          title: Text(
                            'Thời gian kết thúc: ${timerEnd != null ? timerEnd!.toString().substring(11, 16) : 'Chưa chọn'}',
                          ),
                          onTap: () => _selectTime(context, false),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Ngày áp dụng:',
                          style: TextStyle(fontSize: 16),
                        ),
                        Wrap(
                          spacing: 8.0,
                          children: allDays.map((day) {
                            return FilterChip(
                              label: Text(day),
                              selected: selectedDays.contains(day),
                              onSelected: (selected) {
                                setState(() {
                                  if (selected) {
                                    selectedDays.add(day);
                                  } else {
                                    selectedDays.remove(day);
                                  }
                                });
                              },
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            ElevatedButton(
                              onPressed: () {
                                setState(() {
                                  isFanScenarioActive = true;
                                });
                                _saveFanScenario();
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.teal,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              child: const Text('Lưu kịch bản'),
                            ),
                            if (isFanScenarioActive)
                              ElevatedButton(
                                onPressed: () async {
                                  setState(() {
                                    isFanScenarioActive = false;
                                    temperatureThreshold = null;
                                    temperatureCondition = 'greater';
                                    timerStart = null;
                                    timerEnd = null;
                                    selectedDays = [];
                                  });
                                  try {
                                    await supabase.from('scenarios').upsert(
                                      {
                                        'device_name': 'fan',
                                        'temperature_threshold': null,
                                        'device_state': '0',
                                        'temperature_condition': 'greater',
                                        'is_active': false,
                                        'timer_start': null,
                                        'timer_end': null,
                                        'days_of_week': null,
                                      },
                                      onConflict: 'device_name',
                                    );
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Đã hủy kịch bản nhiệt độ.')),
                                    );
                                  } catch (e) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('Lỗi khi hủy kịch bản: $e')),
                                    );
                                  }
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.redAccent,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                child: const Text('Hủy kịch bản'),
                              ),
                          ],
                        ),
                        if (isFanScenarioActive) ...[
                          const SizedBox(height: 8),
                          Text(
                            'Kịch bản hiện tại: Quạt sẽ ${fanShouldBeOn ? 'bật' : 'tắt'} khi nhiệt độ ${temperatureCondition == 'greater' ? '>' : temperatureCondition == 'equal' ? '=' : '<'} $temperatureThreshold °C${timerStart != null ? ' từ ${timerStart!.toString().substring(11, 16)} đến ${timerEnd!.toString().substring(11, 16)}' : ''}.',
                            style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSupportTab() {
    return Container(
      width: MediaQuery.of(context).size.width,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.teal.shade50, Colors.white],
        ),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 16.0),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: MediaQuery.of(context).size.height -
                MediaQuery.of(context).padding.top -
                kToolbarHeight -
                kBottomNavigationBarHeight,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16.0),
                  child: Text(
                    'Hỗ trợ',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.teal,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  elevation: 4,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  margin: const EdgeInsets.only(bottom: 16, left: 16, right: 16),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Hướng dẫn sử dụng',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '1. Sử dụng tab "Thiết bị" để điều khiển các thiết bị trong nhà.\n'
                              '2. Sử dụng tab "Kịch bản" để thiết lập các kịch bản thông minh.\n'
                              '3. Liên hệ hỗ trợ nếu gặp vấn đề.',
                          style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  ),
                ),
                Card(
                  elevation: 4,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  margin: const EdgeInsets.only(bottom: 16, left: 16, right: 16),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Liên hệ hỗ trợ',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Email: support@smarthome.com\n'
                              'Hotline: 0123 456 789',
                          style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProfileTab() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.teal.shade50, Colors.white],
        ),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Thông tin cá nhân',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.teal,
              ),
            ),
            const SizedBox(height: 16),
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              margin: const EdgeInsets.only(bottom: 16),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: userProfile == null
                    ? const Center(child: CircularProgressIndicator())
                    : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.person, size: 30, color: Colors.teal[800]),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Text(
                            'Họ và tên: ${userProfile!['full_name']}',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(Icons.wc, size: 30, color: Colors.teal[800]),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Text(
                            'Giới tính: ${userProfile!['gender']}',
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.grey[600],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(Icons.calendar_today, size: 30, color: Colors.teal[800]),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Text(
                            'Ngày sinh: ${DateTime.parse(userProfile!['date_of_birth']).day}/${DateTime.parse(userProfile!['date_of_birth']).month}/${DateTime.parse(userProfile!['date_of_birth']).year}',
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.grey[600],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Đổi thông tin',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.teal,
              ),
            ),
            const SizedBox(height: 16),
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              margin: const EdgeInsets.only(bottom: 16),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.lock, color: Colors.teal),
                      title: const Text('Đổi mật khẩu'),
                      onTap: _changePassword,
                    ),
                    const Divider(),
                    ListTile(
                      leading: const Icon(Icons.person, color: Colors.teal),
                      title: const Text('Đổi tên'),
                      onTap: _changeName,
                    ),
                    const Divider(),
                    ListTile(
                      leading: const Icon(Icons.calendar_today, color: Colors.teal),
                      title: const Text('Đổi ngày sinh'),
                      onTap: _changeDateOfBirth,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: ElevatedButton(
                onPressed: _logout,
                child: const Text('Đăng xuất', style: TextStyle(fontSize: 16)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 60),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeviceCard({
    required IconData icon,
    required String title,
    required String subtitle,
    Widget? trailing,
    Widget? child,
  }) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              children: [
                Icon(icon, size: 30, color: Colors.teal[800]),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                if (trailing != null) trailing,
              ],
            ),
            if (child != null) ...[
              const SizedBox(height: 16),
              child,
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard({
    required IconData icon,
    required String title,
    required String value,
    required Color color,
  }) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            Icon(icon, size: 30, color: color),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}