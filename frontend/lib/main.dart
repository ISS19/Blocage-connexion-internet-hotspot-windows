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
          seedColor: const Color(0xFF6366F1),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        cardTheme: const CardThemeData(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(16)),
          ),
        ),
        appBarTheme: const AppBarTheme(centerTitle: true, elevation: 0),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6366F1),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        cardTheme: const CardThemeData(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(16)),
          ),
        ),
        appBarTheme: const AppBarTheme(centerTitle: true, elevation: 0),
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
  bool autoRefreshEnabled = false;

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
        fetchDevices();
        fetchServerStatus();
        refreshTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
          fetchDevices();
          fetchServerStatus();
        });
      } else {
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
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _showBlockConfirmDialog(Device device) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        insetPadding: const EdgeInsets.all(20),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.block, color: Colors.red, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Confirmer le blocage',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: Text(
          'Voulez-vous bloquer l\'appareil "${device.name}" (${device.ip}) ?',
          style: const TextStyle(fontSize: 15),
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
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Bloquer'),
          ),
        ],
      ),
    );
  }

  IconData _getDeviceIcon(String type) {
    if (type.contains('Android') ||
        type.contains('Samsung') ||
        type.contains('Vivo')) {
      return Icons.smartphone;
    } else if (type.contains('Apple') || type.contains('iPhone')) {
      return Icons.phone_iphone;
    } else if (type.contains('Ordinateur') || type.contains('VMware')) {
      return Icons.computer;
    } else if (type.contains('ESP32') ||
        type.contains('Arduino') ||
        type.contains('IoT')) {
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? null : Colors.grey[50],
      appBar: AppBar(
        title: Row(
          mainAxisAlignment: MainAxisAlignment.start, // Alignement à gauche
          mainAxisSize: MainAxisSize.max, // Prend toute la largeur
          children: [
            Image.asset(
              'assets/logo.png',
              width: 50,
              height: 50,
            ),
            const SizedBox(width: 12),
            const Text('No-Net', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: autoRefreshEnabled
                  ? Colors.green.withOpacity(0.1)
                  : Theme.of(context).colorScheme.surfaceVariant,
              borderRadius: BorderRadius.circular(12),
            ),
            child: IconButton(
              icon: Icon(
                autoRefreshEnabled
                    ? Icons.pause_circle_filled
                    : Icons.play_circle_outline,
                color: autoRefreshEnabled ? Colors.green : null,
              ),
              onPressed: toggleAutoRefresh,
              tooltip: autoRefreshEnabled
                  ? 'Arrêter le rafraîchissement auto'
                  : 'Activer le rafraîchissement auto',
            ),
          ),
          Container(
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceVariant,
              borderRadius: BorderRadius.circular(12),
            ),
            child: IconButton(
              icon: const Icon(Icons.refresh_rounded),
              onPressed: () {
                fetchDevices();
                fetchServerStatus();
              },
              tooltip: 'Rafraîchir manuellement',
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Carte de statut moderne
          if (serverStatus != null)
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Theme.of(context).colorScheme.primaryContainer,
                    Theme.of(
                      context,
                    ).colorScheme.primaryContainer.withOpacity(0.5),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withOpacity(0.1),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _StatusItem(
                    icon: Icons.wifi_rounded,
                    label: 'Hotspot',
                    value: serverStatus!['hotspot_active']
                        ? 'Actif'
                        : 'Inactif',
                    color: serverStatus!['hotspot_active']
                        ? Colors.green
                        : Colors.red,
                  ),
                  Container(
                    width: 1,
                    height: 60,
                    color: Theme.of(
                      context,
                    ).colorScheme.onPrimaryContainer.withOpacity(0.1),
                  ),
                  _StatusItem(
                    icon: Icons.devices_rounded,
                    label: 'Connectés',
                    value: '$activeCount',
                    color: const Color(0xFF6366F1),
                  ),
                  Container(
                    width: 1,
                    height: 60,
                    color: Theme.of(
                      context,
                    ).colorScheme.onPrimaryContainer.withOpacity(0.1),
                  ),
                  _StatusItem(
                    icon: Icons.block_rounded,
                    label: 'Bloqués',
                    value: '$blockedCount',
                    color: Colors.red,
                  ),
                ],
              ),
            ),

          // Indicateur de rafraîchissement auto moderne
          if (autoRefreshEnabled)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.green.withOpacity(0.1),
                    Colors.green.withOpacity(0.05),
                  ],
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Colors.green.withOpacity(0.3),
                  width: 1.5,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.sync_rounded,
                      size: 16,
                      color: Colors.green,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    'Rafraîchissement automatique (5s)',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.green,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 8),

          // Liste des appareils
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : errorMessage != null
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.red.withOpacity(0.1),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.error_outline,
                            size: 64,
                            color: Colors.red,
                          ),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          errorMessage!,
                          style: const TextStyle(fontSize: 16),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 24),
                        FilledButton.icon(
                          onPressed: fetchDevices,
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Réessayer'),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                : devices.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.grey.withOpacity(0.1),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.devices_other_rounded,
                            size: 64,
                            color: Colors.grey,
                          ),
                        ),
                        const SizedBox(height: 24),
                        const Text(
                          'Aucun appareil connecté',
                          style: TextStyle(
                            fontSize: 18,
                            color: Colors.grey,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: fetchDevices,
                    child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
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
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withOpacity(0.15),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: color, size: 28),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: Theme.of(
              context,
            ).colorScheme.onPrimaryContainer.withOpacity(0.7),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 20,
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: device.isBlocked
            ? Colors.red.withOpacity(isDark ? 0.1 : 0.05)
            : (isDark ? Theme.of(context).colorScheme.surface : Colors.white),
        borderRadius: BorderRadius.circular(20),
        border: device.isBlocked
            ? Border.all(color: Colors.red.withOpacity(0.3), width: 1.5)
            : null,
        boxShadow: device.isBlocked
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withOpacity(isDark ? 0.3 : 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            gradient: device.isBlocked
                ? null
                : LinearGradient(
                    colors: [
                      Theme.of(context).colorScheme.primary,
                      Theme.of(context).colorScheme.primary.withOpacity(0.7),
                    ],
                  ),
            color: device.isBlocked ? Colors.red.withOpacity(0.1) : null,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(
            deviceIcon,
            color: device.isBlocked ? Colors.red : Colors.white,
            size: 24,
          ),
        ),
        title: Text(
          device.name,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            decoration: device.isBlocked ? TextDecoration.lineThrough : null,
            color: device.isBlocked ? Colors.red : null,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.lan_rounded,
                    size: 14,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withOpacity(0.5),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    device.ip,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withOpacity(0.7),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(
                    Icons.access_time_rounded,
                    size: 14,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withOpacity(0.5),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Vu: ${device.lastSeen}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withOpacity(0.6),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        trailing: device.isBlocked
            ? IconButton(
                onPressed: onUnblock,
                icon: const Icon(Icons.check_circle_rounded),
                color: Colors.white,
                style: IconButton.styleFrom(
                  backgroundColor: Colors.green,
                  padding: const EdgeInsets.all(8),
                  minimumSize: const Size(40, 40),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                tooltip: 'Débloquer',
              )
            : IconButton(
                onPressed: onBlock,
                icon: const Icon(Icons.block_rounded),
                color: Colors.red,
                style: IconButton.styleFrom(
                  backgroundColor: Colors.red.withOpacity(0.1),
                  padding: const EdgeInsets.all(8),
                  minimumSize: const Size(40, 40),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: BorderSide(
                      color: Colors.red.withOpacity(0.5),
                      width: 1.5,
                    ),
                  ),
                ),
                tooltip: 'Bloquer',
              ),
        isThreeLine: true,
      ),
    );
  }
}
