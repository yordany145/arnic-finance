import 'package:local_auth/local_auth.dart';

/// Bloqueo de la app con la biometría o el PIN/patrón del sistema
/// (`local_auth`): no hay contraseña propia que gestionar ni guardar.
class AppLock {
  AppLock() : _auth = LocalAuthentication();

  final LocalAuthentication _auth;

  /// `false` si el dispositivo no tiene ninguna forma de desbloqueo configurada
  /// (ni biometría ni PIN/patrón/contraseña): en ese caso no tiene sentido
  /// ofrecer la opción de bloquear la app.
  Future<bool> isSupported() async {
    try {
      return await _auth.isDeviceSupported();
    } on Exception {
      return false;
    }
  }

  /// `true` si se desbloqueó. `biometricOnly: false` deja caer al PIN/patrón/
  /// contraseña del sistema si no hay huella/rostro configurados o fallan.
  Future<bool> authenticate() async {
    try {
      return await _auth.authenticate(
        localizedReason: 'Desbloquea Arnic Finance',
        biometricOnly: false,
        persistAcrossBackgrounding: true,
      );
    } on Exception {
      return false;
    }
  }
}
