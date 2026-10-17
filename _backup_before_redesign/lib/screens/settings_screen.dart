import 'package:flutter/material.dart';
import '../config/api_config.dart';
import '../services/linuxone_api_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _hostController = TextEditingController();
  final _apiService = LinuxOneApiService();
  bool _mockMode = true;
  bool _testingConnection = false;
  String? _connectionResult;
  bool? _connectionSuccess;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final host = await ApiConfig.getBaseUrl();
    final mock = await ApiConfig.isMockModeEnabled();
    setState(() {
      _hostController.text = host;
      _mockMode = mock;
    });
  }

  Future<void> _testConnection() async {
    setState(() {
      _testingConnection = true;
      _connectionResult = null;
    });

    await ApiConfig.setBaseUrl(_hostController.text.trim());
    final success = await _apiService.checkConnection();

    setState(() {
      _testingConnection = false;
      _connectionSuccess = success;
      _connectionResult = success 
          ? "Connected to LinuxONE (s390x) successfully!" 
          : "Could not reach LinuxONE. Check IP/firewall or keep mock fallback enabled.";
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF060B14),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        title: const Text("LinuxONE Connection Settings", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Highlight Box
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF0043CE).withOpacity(0.12),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF0043CE)),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.hub, color: Color(0xFF38BDF8), size: 20),
                    SizedBox(width: 8),
                    Text(
                      "IBM LinuxONE REST Gateway",
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                  ],
                ),
                SizedBox(height: 8),
                Text(
                  "Configure the IP address of your LinuxONE virtual instance running the FastAPI backend. Mobile app offloads all heavy DSP & AI processing to this host.",
                  style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.4),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          const Text(
            "LINUXONE HOST URL",
            style: TextStyle(color: Color(0xFF38BDF8), fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _hostController,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: "http://192.168.1.50:8000",
              hintStyle: const TextStyle(color: Colors.white30),
              filled: true,
              fillColor: const Color(0xFF0F172A),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              prefixIcon: const Icon(Icons.dns, color: Color(0xFF38BDF8)),
            ),
          ),
          const SizedBox(height: 12),

          ElevatedButton.icon(
            onPressed: _testingConnection ? null : _testConnection,
            icon: _testingConnection 
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.network_check),
            label: Text(_testingConnection ? "Pinging LinuxONE..." : "Test Health Endpoint"),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0043CE),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),

          if (_connectionResult != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: (_connectionSuccess == true ? Colors.green : Colors.amber).withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _connectionSuccess == true ? Colors.green : Colors.amber),
              ),
              child: Text(
                _connectionResult!,
                style: TextStyle(
                  color: _connectionSuccess == true ? Colors.greenAccent : Colors.amberAccent,
                  fontSize: 12,
                ),
              ),
            ),
          ],

          const SizedBox(height: 24),
          const Divider(color: Colors.white12),
          const SizedBox(height: 12),

          // Mock Mode Switch
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text("Hackathon Pitch Rehearsal Mode", style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
            subtitle: const Text(
              "Automatically serves realistic simulated vital signs if LinuxONE server is offline or unreachable during the pitch demo.",
              style: TextStyle(color: Colors.white54, fontSize: 11),
            ),
            value: _mockMode,
            activeColor: const Color(0xFF38BDF8),
            onChanged: (val) async {
              setState(() => _mockMode = val);
              await ApiConfig.setMockMode(val);
            },
          ),
        ],
      ),
    );
  }
}
