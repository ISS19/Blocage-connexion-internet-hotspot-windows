import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'dart:async';

void main() {
  runApp(const HotspotManagerApp());
}

class HotspotManagerApp extends StatelessWidget {
  const HotspotManagerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'No-Net',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      themeMode: ThemeMode.system,
      home: const HotspotManagerPage(),
    );
  }
}

class Device {
  final String ip;
  final String mac;
  final String name;
  final String type;
  final String status;
  final String lastSeen;

  Device({
    required this.ip,
    required this.mac,
    required this.name,
    required this.type,
    required this.status,
    required this.lastSeen,
  });

  factory Device.fromJson(Map<String, dynamic> json) {
    return Device(
      ip: json['ip'] ?? '',
      mac: json['mac'] ?? '',
      name: json['name'] ?? 'Inconnu',
      type: json['type'] ?? 'Inconnu',
      status: json['status'] ?? 'active',
      lastSeen: json['last_seen'] ?? '',
    );
  }

  bool get isBlocked => status == 'blocked';
}

class HotspotManagerPage extends StatefulWidget {
  const HotspotManagerPage({super.key});

  @override
  State<HotspotManagerPage> createState() => _HotspotManagerPageState();
}

class _HotspotManagerPageState extends State<HotspotManagerPage> {
  List<Device> devices = [];
  bool isLoading = true;
  String? errorMessage;
  Timer? refreshTimer;
  bool autoRefreshEnabled = false; // État du rafraîchissement auto
  
  // Configuration de l'URL du backend
  final String baseUrl = 'http://192.168.1.46:5000';
  
  Map<String, dynamic>? serverStatus;

  @override
  void initState() {
    super.initState();
    fetchDevices();
    fetchServerStatus();
  }

  @override
  void dispose() {
    refreshTimer?.cancel();
    super.dispose();
  }

  void toggleAutoRefresh() {
    setState(() {
      autoRefreshEnabled = !autoRefreshEnabled;
      
      if (autoRefreshEnabled) {
        // Démarrer le rafraîchissement automatique
        fetchDevices();
        fetchServerStatus();
        refreshTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
          fetchDevices();
          fetchServerStatus();
        });
      } else {
        // Arrêter le rafraîchissement automatique
        refreshTimer?.cancel();
        refreshTimer = null;
      }
    });
  }

  Future<void> fetchDevices() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/devices'));
      
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        setState(() {
          devices = data.map((json) => Device.fromJson(json)).toList();
          isLoading = false;
          errorMessage = null;
        });
      } else {
        setState(() {
          errorMessage = 'Erreur: ${response.statusCode}';
          isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        errorMessage = 'Erreur de connexion: $e';
        isLoading = false;
      });
    }
  }

  Future<void> fetchServerStatus() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/status'));
      if (response.statusCode == 200) {
        setState(() {
          serverStatus = json.decode(response.body);
        });
      }
    } catch (e) {
      // Ignorer les erreurs de statut
    }
  }

  Future<void> blockDevice(String ip) async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/block/$ip'));
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          _showSnackBar('✅ Appareil $ip bloqué avec succès', Colors.green);
          fetchDevices();
        } else {
          _showSnackBar('⚠️ Blocage partiel de $ip', Colors.orange);
        }
      } else {
        _showSnackBar('❌ Échec du blocage', Colors.red);
      }
    } catch (e) {
      _showSnackBar('❌ Erreur: $e', Colors.red);
    }
  }

  Future<void> unblockDevice(String ip) async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/unblock/$ip'));
      
      if (response.statusCode == 200) {
        _showSnackBar('✅ Appareil $ip débloqué', Colors.green);
        fetchDevices();
      } else {
        _showSnackBar('❌ Échec du déblocage', Colors.red);
      }
    } catch (e) {
      _showSnackBar('❌ Erreur: $e', Colors.red);
    }
  }

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _showBlockConfirmDialog(Device device) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmer le blocage'),
        content: Text(
          'Voulez-vous bloquer l\'appareil "${device.name}" (${device.ip}) ?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              blockDevice(device.ip);
            },
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('Bloquer'),
          ),
        ],
      ),
    );
  }

  IconData _getDeviceIcon(String type) {
    if (type.contains('Android') || type.contains('Samsung') || type.contains('Vivo')) {
      return Icons.smartphone;
    } else if (type.contains('Apple') || type.contains('iPhone')) {
      return Icons.phone_iphone;
    } else if (type.contains('Ordinateur') || type.contains('VMware')) {
      return Icons.computer;
    } else if (type.contains('ESP32') || type.contains('Arduino') || type.contains('IoT')) {
      return Icons.developer_board;
    } else if (type.contains('Raspberry')) {
      return Icons.memory;
    }
    return Icons.devices;
  }

  @override
  Widget build(BuildContext context) {
    final blockedCount = devices.where((d) => d.isBlocked).length;
    final activeCount = devices.length - blockedCount;

    return Scaffold(
      appBar: AppBar(
        title: const Text('No-Net'),
        actions: [
          IconButton(
            icon: Icon(
              autoRefreshEnabled ? Icons.pause_circle : Icons.play_circle,
            ),
            onPressed: toggleAutoRefresh,
            tooltip: autoRefreshEnabled 
                ? 'Arrêter le rafraîchissement auto' 
                : 'Activer le rafraîchissement auto',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              fetchDevices();
              fetchServerStatus();
            },
            tooltip: 'Rafraîchir manuellement',
          ),
        ],
      ),
      body: Column(
        children: [
          // Carte de statut
          if (serverStatus != null)
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _StatusItem(
                    icon: Icons.wifi,
                    label: 'Hotspot',
                    value: serverStatus!['hotspot_active'] ? 'Actif' : 'Inactif',
                    color: serverStatus!['hotspot_active'] ? Colors.green : Colors.red,
                  ),
                  _StatusItem(
                    icon: Icons.devices,
                    label: 'Connectés',
                    value: '$activeCount',
                    color: Colors.blue,
                  ),
                  _StatusItem(
                    icon: Icons.block,
                    label: 'Bloqués',
                    value: '$blockedCount',
                    color: Colors.red,
                  ),
                ],
              ),
            ),

          // Indicateur de rafraîchissement auto
          if (autoRefreshEnabled)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.green, width: 1),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.sync, size: 16, color: Colors.green),
                  const SizedBox(width: 6),
                  Text(
                    'Rafraîchissement auto activé (5s)',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.green,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),

          // Liste des appareils
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : errorMessage != null
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.error_outline, size: 64, color: Colors.red),
                            const SizedBox(height: 16),
                            Text(errorMessage!),
                            const SizedBox(height: 16),
                            FilledButton.icon(
                              onPressed: fetchDevices,
                              icon: const Icon(Icons.refresh),
                              label: const Text('Réessayer'),
                            ),
                          ],
                        ),
                      )
                    : devices.isEmpty
                        ? const Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.devices_other, size: 64, color: Colors.grey),
                                SizedBox(height: 16),
                                Text(
                                  'Aucun appareil connecté',
                                  style: TextStyle(fontSize: 18, color: Colors.grey),
                                ),
                              ],
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: fetchDevices,
                            child: ListView.builder(
                              padding: const EdgeInsets.all(8),
                              itemCount: devices.length,
                              itemBuilder: (context, index) {
                                final device = devices[index];
                                return _DeviceCard(
                                  device: device,
                                  onBlock: () => _showBlockConfirmDialog(device),
                                  onUnblock: () => unblockDevice(device.ip),
                                  deviceIcon: _getDeviceIcon(device.type),
                                );
                              },
                            ),
                          ),
          ),
        ],
      ),
    );
  }
}

class _StatusItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _StatusItem({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: color, size: 32),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onPrimaryContainer.withOpacity(0.7),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }
}

class _DeviceCard extends StatelessWidget {
  final Device device;
  final VoidCallback onBlock;
  final VoidCallback onUnblock;
  final IconData deviceIcon;

  const _DeviceCard({
    required this.device,
    required this.onBlock,
    required this.onUnblock,
    required this.deviceIcon,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      elevation: device.isBlocked ? 0 : 2,
      color: device.isBlocked 
          ? Theme.of(context).colorScheme.errorContainer.withOpacity(0.3)
          : null,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: device.isBlocked 
              ? Colors.red.withOpacity(0.2)
              : Theme.of(context).colorScheme.primaryContainer,
          child: Icon(
            deviceIcon,
            color: device.isBlocked 
                ? Colors.red 
                : Theme.of(context).colorScheme.primary,
          ),
        ),
        title: Text(
          device.name,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            decoration: device.isBlocked ? TextDecoration.lineThrough : null,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${device.ip} • ${device.mac}'),
            Text(
              '${device.type} • Vu: ${device.lastSeen}',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
              ),
            ),
          ],
        ),
        trailing: device.isBlocked
            ? FilledButton.icon(
                onPressed: onUnblock,
                icon: const Icon(Icons.check_circle, size: 16),
                label: const Text('Débloquer'),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.green,
                ),
              )
            : OutlinedButton.icon(
                onPressed: onBlock,
                icon: const Icon(Icons.block, size: 16),
                label: const Text('Bloquer'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                ),
              ),
        isThreeLine: true,
      ),
    );
  }
}