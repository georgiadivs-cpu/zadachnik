import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

import 'session.dart';

abstract interface class SessionStore {
  Future<Session?> read();

  Future<void> write(Session session);

  Future<void> clear();

  Future<String> readOrCreateDeviceId();
}

class SecureSessionStore implements SessionStore {
  SecureSessionStore({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              mOptions: MacOsOptions(usesDataProtectionKeychain: false),
            );

  static const _sessionKey = 'auth.session';
  static const _deviceKey = 'auth.device_id';

  final FlutterSecureStorage _storage;
  final Uuid _uuid = const Uuid();

  @override
  Future<Session?> read() async {
    final raw = await _storage.read(key: _sessionKey);
    return Session.decode(raw);
  }

  @override
  Future<void> write(Session session) =>
      _storage.write(key: _sessionKey, value: Session.encode(session));

  @override
  Future<void> clear() => _storage.delete(key: _sessionKey);

  @override
  Future<String> readOrCreateDeviceId() async {
    final existing = await _storage.read(key: _deviceKey);
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }

    final created = _uuid.v4();
    await _storage.write(key: _deviceKey, value: created);
    return created;
  }
}

class InMemorySessionStore implements SessionStore {
  InMemorySessionStore({this.session, String? deviceId})
      : deviceId = deviceId ?? 'in-memory-device';

  Session? session;
  final String deviceId;

  @override
  Future<Session?> read() async => session;

  @override
  Future<void> write(Session value) async => session = value;

  @override
  Future<void> clear() async => session = null;

  @override
  Future<String> readOrCreateDeviceId() async => deviceId;
}
