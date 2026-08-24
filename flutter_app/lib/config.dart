/// Configuration globale — modifier uniquement ici si l'IP du serveur change
class AppConfig {
  /// IP du serveur backend (Python FastAPI, port 8000).
  /// Changer cette valeur si l'ordinateur change d'IP sur le réseau local.
  static const String serverIp = '192.168.0.23';
  static const String backendUrl = 'http://$serverIp:8000';
}
