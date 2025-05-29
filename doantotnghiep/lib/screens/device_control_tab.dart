import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DeviceControlTab extends StatefulWidget {
  const DeviceControlTab({super.key});

  @override
  _DeviceControlTabState createState() => _DeviceControlTabState();
}

class _DeviceControlTabState extends State<DeviceControlTab> {
  final supabase = Supabase.instance.client;
  bool lampOn = false;
  bool doorOpen = false;
  int fanSpeed = 0;
  bool powerOn = false;
  double powerConsumption = 0.0;
  double temperature = 0.0;

  @override
  void initState() {
    super.initState();
    _loadDeviceState();
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
      }
    });
  }

  void _subscribeToRealtime() {
    supabase
        .channel('devices')
        .on(
      RealtimeListenTypes.postgresChanges,
      ChannelFilter(event: 'UPDATE', schema: 'public', table: 'devices'),
          (payload, [ref]) {
        final deviceName = payload['new']['device_name'] as String;
        final state = payload['new']['state'] as String;
        setState(() {
          if (deviceName == 'lamp') lampOn = state == 'ON';
          if (deviceName == 'fan') fanSpeed = int.parse(state);
          if (deviceName == 'power') powerOn = state == 'ON';
          if (deviceName == 'door') doorOpen = state == 'OPEN';
          if (deviceName == 'power_consumption') powerConsumption = double.parse(state);
          if (deviceName == 'temperature') temperature = double.parse(state);
        });
      },
    )
        .subscribe();
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
          'timestamp': DateTime.now().toIso8601String(),
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Lỗi: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
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
              subtitle: 'Tốc độ: $fanSpeed',
              child: Slider(
                value: fanSpeed.toDouble(),
                min: 0,
                max: 255,
                divisions: 255,
                activeColor: Colors.teal,
                inactiveColor: Colors.grey[300],
                label: fanSpeed.toString(),
                onChanged: (value) {
                  setState(() => fanSpeed = value.toInt());
                  _sendCommand("fan", fanSpeed.toString());
                },
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