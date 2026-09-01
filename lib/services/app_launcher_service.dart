import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;

import '../models/app_entry.dart';

/// Handles everything that isn't UI: reading the app registry, launching
/// exes, opening folders, and polling `tasklist` to see what's running.
///
/// The registry lives at `apps.json` next to the dashboard's own exe so you
/// can add a new tool by editing a file instead of rebuilding. On first run
/// (or if the file is missing) it's seeded from the bundled asset.
class AppLauncherService {
  static const _configFileName = 'apps.json';

  Future<File> _configFile() async {
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    return File(p.join(exeDir, _configFileName));
  }

  Future<List<AppEntry>> loadApps() async {
    final file = await _configFile();

    String raw;
    if (await file.exists()) {
      raw = await file.readAsString();
    } else {
      // First run: seed an editable copy next to the exe from the bundled default.
      raw = await rootBundle.loadString('assets/apps.json');
      try {
        await file.writeAsString(raw);
      } catch (_) {
        // Non-fatal if the exe dir isn't writable (e.g. Program Files) —
        // we just keep using the bundled defaults for this session.
      }
    }

    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .map((e) => AppEntry.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Writes the full app list back to `apps.json` next to the exe, pretty-printed
  /// so it stays easy to hand-edit later. Used by the "+" tile, but also means
  /// anything added through the UI survives a restart.
  Future<void> saveApps(List<AppEntry> apps) async {
    final file = await _configFile();
    const encoder = JsonEncoder.withIndent('  ');
    final json = encoder.convert(apps.map((a) => a.toJson()).toList());
    await file.writeAsString(json);
  }

  /// Opens a native file picker scoped to executables. Returns the chosen
  /// path, or null if the user cancelled.
  Future<String?> pickExecutable() async {
    final result = await FilePicker.platform.pickFiles(
      type: Platform.isWindows ? FileType.custom : FileType.any,
      allowedExtensions: Platform.isWindows ? ['exe'] : null,
      dialogTitle: 'Select executable',
    );
    return result?.files.single.path;
  }

  /// Opens a native folder picker. Returns the chosen path, or null if
  /// cancelled.
  Future<String?> pickFolder() async {
    return FilePicker.platform.getDirectoryPath(dialogTitle: 'Select folder');
  }

  /// Launches an app's exe, or — if it's already running — brings its window
  /// to the front instead. Returns an error string on failure, or null on
  /// success. Relaunching a running app was the actual cause of the
  /// Borderless "elevation required" error: it's admin-only, so trying to
  /// spawn a second instance re-triggers UAC even though one is already open.
  ///
  /// IMPORTANT: if the app is already running we never fall through to
  /// spawning a new process, even if focusing its window fails (e.g.
  /// tray-only apps with no visible window). Launching a duplicate instance
  /// of an already-running app is exactly what this guards against.
  Future<String?> launch(AppEntry app, {bool isRunning = false}) async {
    if (isRunning) {
      await _tryFocus(app);
      return null;
    }

    final exe = File(app.exePath);
    if (!await exe.exists()) {
      return 'Not found:\n${app.exePath}';
    }
    try {
      await Process.start(
        app.exePath,
        [],
        workingDirectory: exe.parent.path,
        mode: ProcessStartMode.detached,
      );
      return null;
    } on ProcessException catch (e) {
      // Windows error 740 = ERROR_ELEVATION_REQUIRED. Some tools (e.g. ones
      // that reposition/resize other windows, like Borderless) declare
      // requireAdministrator in their manifest, so a plain launch from our
      // non-elevated dashboard process fails here even though the exe is
      // right where we expect it. Retry via a UAC prompt scoped to just
      // that exe instead of elevating the whole dashboard.
      if (Platform.isWindows && (e.errorCode == 740 || e.message.toLowerCase().contains('elevation'))) {
        return _launchElevated(app, exe);
      }
      return 'Failed to launch: ${e.message}';
    } catch (e) {
      return 'Failed to launch: $e';
    }
  }

  /// Tries to bring a running app's window to the foreground via a small
  /// PowerShell snippet (matches by process name, then calls user32's
  /// ShowWindow/SetForegroundWindow on its main window handle). Returns
  /// true if a window was found and focused. Tray-only apps with no visible
  /// window (e.g. Clipboard, Screenshot) will return false, which is
  /// expected — there's nothing to bring forward.
  Future<bool> _tryFocus(AppEntry app) async {
    if (!Platform.isWindows) return false;
    final configured = app.processName?.replaceAll('.exe', '').trim();
    if (configured == null || configured.isEmpty) return false;

    final script = '''
\$p = Get-Process | Where-Object { \$_.ProcessName -ieq '$configured' -and \$_.MainWindowHandle -ne 0 } | Select-Object -First 1
if (\$p) {
  Add-Type @"
using System;
using System.Runtime.InteropServices;
public class JoErlWin32Focus {
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
}
"@
  [JoErlWin32Focus]::ShowWindow(\$p.MainWindowHandle, 9) | Out-Null
  [JoErlWin32Focus]::SetForegroundWindow(\$p.MainWindowHandle) | Out-Null
  Write-Output 'FOCUSED'
}
''';
    try {
      final result = await Process.run('powershell', ['-NoProfile', '-WindowStyle', 'Hidden', '-Command', script]);
      return (result.stdout as String).contains('FOCUSED');
    } catch (_) {
      return false;
    }
  }

  Future<String?> _launchElevated(AppEntry app, File exe) async {
    try {
      // Single-quoted PowerShell literal; escape any embedded single quotes
      // in the path by doubling them (PowerShell's escape convention).
      String psQuote(String s) => "'${s.replaceAll("'", "''")}'";
      final result = await Process.run('powershell', [
        '-NoProfile',
        '-WindowStyle', 'Hidden',
        '-Command',
        'Start-Process -FilePath ${psQuote(app.exePath)} '
            '-WorkingDirectory ${psQuote(exe.parent.path)} -Verb RunAs',
      ]);
      if (result.exitCode != 0) {
        return 'Needs admin rights, and the UAC prompt was cancelled or blocked.';
      }
      return null;
    } catch (e) {
      return 'Needs admin rights: $e';
    }
  }

  Future<void> openFolder(String folderPath) async {
    if (!Platform.isWindows) return;
    await Process.start('explorer.exe', [folderPath]);
  }

  /// Returns the set of process names (e.g. "autohibernation.exe") currently
  /// running, using `tasklist`. Cheap enough to poll every few seconds.
  Future<Set<String>> runningProcessNames() async {
    if (!Platform.isWindows) return {};
    try {
      final result = await Process.run('tasklist', ['/FO', 'CSV', '/NH']);
      final out = result.stdout as String;
      final names = <String>{};
      for (final line in const LineSplitter().convert(out)) {
        if (line.isEmpty) continue;
        final firstField = line.split('","');
        if (firstField.isEmpty) continue;
        final name = firstField.first.replaceAll('"', '');
        names.add(name.toLowerCase());
      }
      return names;
    } catch (_) {
      return {};
    }
  }
}
