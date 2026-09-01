import 'dart:io';

/// Toggles "launch on Windows login" via the current user's Run registry
/// key — no admin rights needed, no extra native plugin required.
///
/// The registered command includes a `--startup` flag so the app knows to
/// stay hidden in the tray on a login-launch instead of popping its window
/// open every boot (see main.dart).
class StartupService {
  static const _valueName = 'JoErlDashboard';
  static const _runKey = r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run';

  Future<bool> isEnabled() async {
    if (!Platform.isWindows) return false;
    try {
      final result = await Process.run('reg', ['query', _runKey, '/v', _valueName]);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  Future<bool> setEnabled(bool enabled) async {
    if (!Platform.isWindows) return false;
    try {
      if (enabled) {
        final exe = Platform.resolvedExecutable;
        final value = '"$exe" --startup';
        final result = await Process.run('reg', [
          'add',
          _runKey,
          '/v',
          _valueName,
          '/t',
          'REG_SZ',
          '/d',
          value,
          '/f',
        ]);
        return result.exitCode == 0;
      } else {
        final result = await Process.run('reg', ['delete', _runKey, '/v', _valueName, '/f']);
        return result.exitCode == 0;
      }
    } catch (_) {
      return false;
    }
  }
}
