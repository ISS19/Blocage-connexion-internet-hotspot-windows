from flask import Flask, jsonify
from flask_cors import CORS
import subprocess
import re
import json
import time
import socket
from concurrent.futures import ThreadPoolExecutor, as_completed
from functools import lru_cache
import threading

app = Flask(__name__)
CORS(app)  # Permet les requêtes cross-origin depuis React

# Cache pour les noms d'appareils
device_name_cache = {}
cache_lock = threading.Lock()
CACHE_DURATION = 300  # 5 minutes

@lru_cache(maxsize=256)
def get_device_type_by_mac(mac):
    """Détermine le type d'appareil basé sur l'adresse MAC (avec cache)"""
    try:
        mac_prefix = mac.upper().replace('-', ':')[:8]
        
        # Base de données simplifiée des préfixes MAC
        mac_vendors = {
            '00:08:22': 'InProComm', 
            'DC:85:DE': 'Espressif (ESP32/Arduino)',
            '34:CF:F6': 'Espressif (ESP32)',
            '7A:66:E1': 'Android Device',
            '7C:F3:1B': 'Samsung',
            '98:B8:BA': 'Vivo',
            '00:1A:2B': 'Apple',
            '00:50:56': 'VMware',
            'AC:87:A3': 'LiteOn',
            'B8:27:EB': 'Raspberry Pi'
        }
        
        for prefix, vendor in mac_vendors.items():
            if mac_prefix.startswith(prefix):
                return vendor
        
        # Types génériques basés sur les patterns
        if any(x in mac.upper() for x in ['DC:85', '34:CF', '98:B8']):
            return 'Mobile/IoT'
        elif any(x in mac.upper() for x in ['00:1A', '00:50']):
            return 'Ordinateur'
        else:
            return 'Appareil réseau'
            
    except:
        return 'Inconnu'

def get_device_name_fast(ip):
    """Version rapide de récupération du nom avec cache et timeout"""
    current_time = time.time()
    
    # Vérifier le cache
    with cache_lock:
        if ip in device_name_cache:
            cached_name, timestamp = device_name_cache[ip]
            if current_time - timestamp < CACHE_DURATION:
                return cached_name
    
    # Essayer seulement la méthode la plus rapide
    try:
        # Méthode 1: Résolution DNS inverse avec timeout très court
        socket.setdefaulttimeout(2)  # 2 secondes maximum
        try:
            hostname = socket.gethostbyaddr(ip)[0]
            if hostname and hostname != ip and '.' in hostname:
                # Extraire juste le nom de l'hôte sans le domaine
                device_name = hostname.split('.')[0]
                with cache_lock:
                    device_name_cache[ip] = (device_name, current_time)
                return device_name
        except:
            pass
        
        # Méthode 2: ping rapide avec résolution de nom
        try:
            # Ping avec timeout de 1 seconde et résolution de nom
            ping_result = subprocess.check_output(
                f'ping -a -n 1 -w 1000 {ip}', 
                shell=True, 
                timeout=3,
                stderr=subprocess.DEVNULL,
                text=True
            )
            match = re.search(r'Pinging ([^\s\[]+)', ping_result)
            if match and match.group(1) != ip:
                device_name = match.group(1).split('.')[0]  # Nom sans domaine
                with cache_lock:
                    device_name_cache[ip] = (device_name, current_time)
                return device_name
        except:
            pass
        
        # Nom par défaut basé sur l'IP
        default_name = f"Appareil-{ip.split('.')[-1]}"
        with cache_lock:
            device_name_cache[ip] = (default_name, current_time)
        return default_name
            
    except Exception:
        # En cas d'erreur, retourner un nom par défaut
        default_name = f"Appareil-{ip.split('.')[-1]}"
        with cache_lock:
            device_name_cache[ip] = (default_name, current_time)
        return default_name
    finally:
        socket.setdefaulttimeout(None)  # Reset timeout

def process_device(ip, mac):
    """Traite un appareil individuel en parallèle"""
    try:
        device_name = get_device_name_fast(ip)
        device_type = get_device_type_by_mac(mac)
        device_status = get_device_status_fast(ip)
        
        return {
            "ip": ip,
            "mac": mac,
            "name": device_name,
            "type": device_type,
            "status": device_status,
            "last_seen": time.strftime("%H:%M:%S")
        }
    except Exception as e:
        print(f"Erreur lors du traitement de {ip}: {e}")
        return None

def get_device_status_fast(ip):
    """Version rapide de vérification du statut"""
    try:
        # Vérification rapide des règles firewall seulement
        result = subprocess.check_output(
            f'netsh advfirewall firewall show rule name="HOTSPOT_BLOCK_{ip}_OUT"',
            shell=True,
            timeout=2,
            stderr=subprocess.DEVNULL,
            text=True
        )
        return "blocked" if "HOTSPOT_BLOCK_" in result else "active"
    except:
        return "active"

def get_devices():
    """Version optimisée avec parallélisation"""
    devices = []
    
    try:
        # Récupération rapide des IPs et MACs
        arp_result = subprocess.check_output(
            "arp -a",
            shell=True,
            timeout=5,
            text=True
        )
        
        # Extraction des IPs et MACs du hotspot
        device_ips_macs = []
        for line in arp_result.splitlines():
            match = re.search(r'(\d+\.\d+\.\d+\.\d+)\s+([a-fA-F0-9-:]{17})', line)
            if match and "192.168.137" in match.group(1):
                ip = match.group(1)
                mac = match.group(2)
                # Éviter l'IP de la passerelle
                if not ip.endswith('.1'):
                    device_ips_macs.append((ip, mac))
        
        # Traitement en parallèle avec un maximum de 8 threads
        with ThreadPoolExecutor(max_workers=min(8, len(device_ips_macs))) as executor:
            # Soumettre toutes les tâches
            futures = {
                executor.submit(process_device, ip, mac): (ip, mac) 
                for ip, mac in device_ips_macs
            }
            
            # Récupérer les résultats avec timeout
            for future in as_completed(futures, timeout=10):
                try:
                    result = future.result(timeout=5)
                    if result:
                        devices.append(result)
                except Exception as e:
                    ip, mac = futures[future]
                    print(f"Timeout/erreur pour {ip}: {e}")
                    # Ajouter un appareil avec des infos minimales
                    devices.append({
                        "ip": ip,
                        "mac": mac,
                        "name": f"Appareil-{ip.split('.')[-1]}",
                        "type": get_device_type_by_mac(mac),
                        "status": "active",
                        "last_seen": time.strftime("%H:%M:%S")
                    })
    
    except Exception as e:
        print(f"Erreur lors de la récupération des appareils: {e}")
    
    return devices

def get_network_interface():
    """Version optimisée de récupération de l'interface"""
    try:
        result = subprocess.check_output('ipconfig', shell=True, timeout=3, text=True)
        lines = result.split('\n')
        
        for i, line in enumerate(lines):
            if "192.168.137.1" in line:
                # Remonte pour trouver le nom de l'interface
                for j in range(i-1, max(0, i-10), -1):
                    if "adaptateur" in lines[j].lower() or "adapter" in lines[j].lower():
                        interface_name = lines[j].split(':')[0].strip()
                        return interface_name
                break
        return None
    except:
        return None

@app.route("/devices")
def devices():
    start_time = time.time()
    result = jsonify(get_devices())
    end_time = time.time()
    print(f"⏱️ Récupération des appareils terminée en {end_time - start_time:.2f}s")
    return result

@app.route("/block/<ip>")
def block(ip):
    try:
        print(f"\n{'='*70}")
        print(f"🚫 BLOCAGE DE {ip} - MÉTHODE HOTSPOT")
        print(f"{'='*70}")
        
        # ÉTAPE 0: Nettoyage complet
        print(f"\n📋 NETTOYAGE: Suppression des anciennes règles...")
        subprocess.run(
            f'netsh advfirewall firewall delete rule name=all remoteip={ip}',
            shell=True, capture_output=True, text=True, timeout=10
        )
        subprocess.run(
            f'netsh advfirewall firewall delete rule name=all localip={ip}',
            shell=True, capture_output=True, text=True, timeout=10
        )
        
        # STRATÉGIE: Bloquer TOUS les protocoles dans TOUTES les directions
        # en ciblant spécifiquement le trafic passant par l'interface hotspot
        
        print(f"\n📋 CRÉATION DES RÈGLES DE BLOCAGE...")
        
        rules = []
        success_count = 0
        
        # RÈGLE 1: Bloquer TOUT le trafic sortant depuis cette IP vers Internet
        # (Bloque HTTP, HTTPS, DNS, tout protocole)
        rule1 = {
            'name': f'HOTSPOT_BLOCK_{ip}_OUT',
            'cmd': f'netsh advfirewall firewall add rule name="HOTSPOT_BLOCK_{ip}_OUT" dir=out action=block localip={ip} interfacetype=any'
        }
        rules.append(rule1)
        
        # RÈGLE 2: Bloquer tout le trafic entrant vers cette IP depuis Internet
        rule2 = {
            'name': f'HOTSPOT_BLOCK_{ip}_IN',
            'cmd': f'netsh advfirewall firewall add rule name="HOTSPOT_BLOCK_{ip}_IN" dir=in action=block remoteip={ip} interfacetype=any'
        }
        rules.append(rule2)
        
        # RÈGLE 3: Bloquer spécifiquement les protocoles web (TCP 80, 443)
        rule3 = {
            'name': f'HOTSPOT_BLOCK_{ip}_WEB',
            'cmd': f'netsh advfirewall firewall add rule name="HOTSPOT_BLOCK_{ip}_WEB" dir=out action=block protocol=TCP localip={ip} remoteport=80,443'
        }
        rules.append(rule3)
        
        # RÈGLE 4: Bloquer le DNS (port 53)
        rule4 = {
            'name': f'HOTSPOT_BLOCK_{ip}_DNS',
            'cmd': f'netsh advfirewall firewall add rule name="HOTSPOT_BLOCK_{ip}_DNS" dir=out action=block protocol=UDP localip={ip} remoteport=53'
        }
        rules.append(rule4)
        
        # RÈGLE 5: Bloquer ICMP (ping)
        rule5 = {
            'name': f'HOTSPOT_BLOCK_{ip}_ICMP',
            'cmd': f'netsh advfirewall firewall add rule name="HOTSPOT_BLOCK_{ip}_ICMP" dir=out action=block protocol=icmpv4 localip={ip}'
        }
        rules.append(rule5)
        
        # Créer toutes les règles
        for rule in rules:
            print(f"\n   🔧 {rule['name']}")
            result = subprocess.run(
                rule['cmd'],
                shell=True,
                capture_output=True,
                text=True,
                timeout=15
            )
            
            if result.returncode == 0 and "Ok." in result.stdout:
                print(f"   ✅ Créée")
                success_count += 1
            else:
                print(f"   ❌ Échec: {result.stderr}")
        
        # ÉTAPE CRITIQUE: Bloquer au niveau du routage avec une route statique
        print(f"\n📋 BLOCAGE AU NIVEAU ROUTAGE...")
        try:
            # Ajouter une route statique qui redirige tout le trafic de cette IP vers nulle part
            route_cmd = f'route add {ip} mask 255.255.255.255 0.0.0.0 metric 1'
            route_result = subprocess.run(
                route_cmd,
                shell=True,
                capture_output=True,
                text=True,
                timeout=10
            )
            
            if route_result.returncode == 0 or "existe" in route_result.stdout.lower():
                print(f"   ✅ Route de blocage ajoutée")
                success_count += 1
            else:
                print(f"   ⚠️  Route: {route_result.stdout.strip()}")
        except Exception as e:
            print(f"   ⚠️  Erreur route: {e}")
        
        # Forcer la déconnexion
        print(f"\n📋 DÉCONNEXION FORCÉE...")
        try:
            # Supprimer l'entrée ARP pour forcer reconnexion
            subprocess.run(f'arp -d {ip}', shell=True, timeout=5, capture_output=True)
            print(f"   ✅ Cache ARP vidé")
            
            # Optionnel: Tuer les connexions existantes avec netstat (si possible)
            subprocess.run(
                f'netsh interface ip delete arpcache',
                shell=True, timeout=5, capture_output=True
            )
        except:
            pass
        
        with cache_lock:
            if ip in device_name_cache:
                del device_name_cache[ip]
        
        print(f"\n{'='*70}")
        print(f"📊 RÉSULTAT: {success_count} protections activées")
        
        if success_count >= 3:
            print(f"✅ BLOCAGE MULTI-COUCHES ACTIF")
            print(f"{'='*70}\n")
            return jsonify({
                "status": f"Blocked {ip}",
                "success": True,
                "protections": success_count
            })
        else:
            print(f"⚠️  BLOCAGE PARTIEL")
            print(f"{'='*70}\n")
            return jsonify({
                "status": f"Partial block {ip}",
                "success": False,
                "protections": success_count
            }), 500
    
    except Exception as e:
        print(f"\n❌ ERREUR: {e}")
        import traceback
        traceback.print_exc()
        return jsonify({
            "status": f"Error: {str(e)}",
            "success": False
        }), 500

@app.route("/unblock/<ip>")
def unblock(ip):
    try:
        print(f"\n{'='*70}")
        print(f"✅ DÉBLOCAGE DE {ip}")
        print(f"{'='*70}")
        
        deleted = 0
        
        # Supprimer toutes les règles firewall
        print(f"📋 Suppression des règles firewall...")
        rule_names = [
            f'HOTSPOT_BLOCK_{ip}_OUT',
            f'HOTSPOT_BLOCK_{ip}_IN',
            f'HOTSPOT_BLOCK_{ip}_WEB',
            f'HOTSPOT_BLOCK_{ip}_DNS',
            f'HOTSPOT_BLOCK_{ip}_ICMP'
        ]
        
        for rule_name in rule_names:
            result = subprocess.run(
                f'netsh advfirewall firewall delete rule name="{rule_name}"',
                shell=True, capture_output=True, text=True, timeout=10
            )
            if "Ok." in result.stdout:
                deleted += 1
        
        # Nettoyage complet
        subprocess.run(
            f'netsh advfirewall firewall delete rule name=all remoteip={ip}',
            shell=True, capture_output=True, timeout=10
        )
        subprocess.run(
            f'netsh advfirewall firewall delete rule name=all localip={ip}',
            shell=True, capture_output=True, timeout=10
        )
        
        # CRITIQUE: Supprimer la route statique
        print(f"📋 Suppression de la route de blocage...")
        try:
            route_cmd = f'route delete {ip}'
            route_result = subprocess.run(
                route_cmd,
                shell=True,
                capture_output=True,
                text=True,
                timeout=10
            )
            if route_result.returncode == 0:
                print(f"   ✅ Route supprimée")
                deleted += 1
            else:
                print(f"   ℹ️  {route_result.stdout.strip()}")
        except Exception as e:
            print(f"   ⚠️  {e}")
        
        # Rafraîchir ARP
        subprocess.run(f'arp -d {ip}', shell=True, timeout=5, capture_output=True)
        subprocess.run('netsh interface ip delete arpcache', shell=True, timeout=5, capture_output=True)
        
        with cache_lock:
            if ip in device_name_cache:
                del device_name_cache[ip]
        
        print(f"✅ Déblocage terminé ({deleted} protections retirées)")
        print(f"{'='*70}\n")
        
        return jsonify({
            "status": f"Unblocked {ip}",
            "success": True,
            "removed": deleted
        })
    
    except Exception as e:
        print(f"❌ Erreur: {e}\n")
        return jsonify({
            "status": f"Error: {str(e)}",
            "success": False
        }), 500

@app.route("/status")
def status():
    """Endpoint pour vérifier le statut du serveur"""
    try:
        devices = get_devices()
        return jsonify({
            "status": "running",
            "hotspot_active": check_hotspot_status(),
            "interface": get_network_interface(),
            "connected_devices": len(devices),
            "blocked_devices": len([d for d in devices if d['status'] == 'blocked'])
        })
    except Exception as e:
        print(f"Erreur status: {e}")
        return jsonify({
            "status": "error",
            "hotspot_active": False,
            "interface": None,
            "connected_devices": 0,
            "blocked_devices": 0
        })

def check_hotspot_status():
    """Version optimisée de vérification du hotspot"""
    try:
        result = subprocess.check_output('ipconfig', shell=True, timeout=3, text=True)
        return "192.168.137.1" in result
    except:
        return False

@app.route("/cache/clear")
def clear_cache():
    """Endpoint pour vider le cache des noms"""
    with cache_lock:
        device_name_cache.clear()
    return jsonify({"status": "Cache cleared", "success": True})

@app.route("/cache/info")
def cache_info():
    """Informations sur le cache"""
    with cache_lock:
        return jsonify({
            "cached_devices": len(device_name_cache),
            "cache_entries": list(device_name_cache.keys())
        })

@app.route("/rules/<ip>")
def check_rules(ip):
    """Vérifier les règles de pare-feu pour une IP spécifique"""
    try:
        result = subprocess.run(
            'netsh advfirewall firewall show rule name=all',
            shell=True, capture_output=True, text=True, timeout=15
        )
        
        rules_found = []
        current_rule = {}
        
        for line in result.stdout.split('\n'):
            line = line.strip()
            
            if line.startswith('Rule Name:'):
                if current_rule and (ip in str(current_rule.values())):
                    rules_found.append(current_rule)
                current_rule = {'name': line.split(':', 1)[1].strip()}
            elif ':' in line and current_rule:
                key, value = line.split(':', 1)
                current_rule[key.strip()] = value.strip()
        
        if current_rule and (ip in str(current_rule.values())):
            rules_found.append(current_rule)
        
        # Vérifier aussi les routes
        route_result = subprocess.run(
            f'route print | findstr {ip}',
            shell=True, capture_output=True, text=True, timeout=5
        )
        
        return jsonify({
            "ip": ip,
            "rules_count": len(rules_found),
            "rules": rules_found,
            "routes": route_result.stdout.strip() if route_result.stdout else None
        })
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route("/rules/cleanup")
def cleanup_all_rules():
    """Supprimer toutes les règles de blocage créées par l'application"""
    try:
        print(f"\n🧹 NETTOYAGE COMPLET")
        
        result = subprocess.run(
            'netsh advfirewall firewall show rule name=all',
            shell=True, capture_output=True, text=True, timeout=15
        )
        
        rules_to_delete = []
        for line in result.stdout.split('\n'):
            if 'Rule Name:' in line and 'HOTSPOT_BLOCK_' in line:
                rule_name = line.split('Rule Name:')[1].strip()
                rules_to_delete.append(rule_name)
        
        deleted = 0
        for rule_name in set(rules_to_delete):
            result = subprocess.run(
                f'netsh advfirewall firewall delete rule name="{rule_name}"',
                shell=True, capture_output=True, timeout=5, text=True
            )
            if result.returncode == 0:
                deleted += 1
        
        # Nettoyer aussi toutes les routes vers 192.168.137.x
        subprocess.run(
            'route print | findstr "192.168.137" | findstr "255.255.255.255"',
            shell=True, capture_output=True, timeout=5
        )
        
        print(f"✅ {deleted} règles supprimées\n")
        
        return jsonify({
            "status": "cleanup completed",
            "rules_deleted": deleted,
            "success": True
        })
    except Exception as e:
        return jsonify({"error": str(e), "success": False}), 500

if __name__ == "__main__":
    print("🔥 Serveur de gestion du hotspot démarré sur http://0.0.0.0:5000")
    print("⚠️  IMPORTANT: Exécutez en tant qu'ADMINISTRATEUR!")
    print("\n📋 Endpoints disponibles:")
    print("   - GET /devices : Liste des appareils")
    print("   - GET /block/<ip> : Bloquer un appareil") 
    print("   - GET /unblock/<ip> : Débloquer un appareil")
    print("   - GET /status : Statut du serveur")
    print("   - GET /rules/<ip> : Vérifier les règles pour une IP")
    print("   - GET /rules/cleanup : Nettoyer toutes les règles")
    print("\n" + "="*70 + "\n")
    app.run(host="0.0.0.0", port=5000, debug=True)