import 'dart:async';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:tray_manager/tray_manager.dart';

import 'models/app_entry.dart';
import 'screens/dashboard_screen.dart';
import 'services/app_launcher_service.dart';
import 'services/startup_service.dart';
import 'theme/app_theme.dart';

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  const windowOptions = WindowOptions(
    size: Size(1040, 680),
    minimumSize: Size(760, 480),
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.hidden, // we draw our own title bar
  );

  // Launched by Windows at login (see StartupService) - stay hidden in the
  // tray instead of popping the window open on every boot.
  final startedByWindows = args.contains('--startup');

  windowManager.waitUntilReadyToShow(windowOptions, () async {
    if (startedByWindows) {
      await windowManager.hide();
    } else {
      await windowManager.show();
      await windowManager.focus();
    }
    await windowManager.setPreventClose(true); // let onWindowClose hide-to-tray instead of quitting
  });

  runApp(const JoErlDashboardApp());
}

class JoErlDashboardApp extends StatefulWidget {
  const JoErlDashboardApp({super.key});

  @override
  State<JoErlDashboardApp> createState() => _JoErlDashboardAppState();
}

class _JoErlDashboardAppState extends State<JoErlDashboardApp> with TrayListener, WindowListener {
  final _launcher = AppLauncherService();
  final _startup = StartupService();

  List<AppEntry> _apps = [];
  Set<String> _runningProcessNames = {};
  bool _startWithWindows = false;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    trayManager.addListener(this);
    windowManager.addListener(this);
    _initTray();
  }

  Future<void> _initTray() async {
    // Set a minimal, always-available menu FIRST so right-click never comes
    // up empty even if something below fails (bad apps.json, first-run
    // permission hiccup writing the seed file, icon load issue, etc).
    // Everything after this upgrades the menu once real data is in.
    await _setFallbackMenu();

    try {
      await trayManager.setIcon('assets/tray_icon.ico');
    } catch (_) {
      // Icon failing to load shouldn't take the whole tray down with it.
    }
    try {
      await trayManager.setToolTip('JoErl Dev Dashboard');
    } catch (_) {}

    try {
      _startWithWindows = await _startup.isEnabled();
    } catch (_) {}

    await _refreshState();
    await _rebuildMenu();

    // Keep the "Running Apps" section (and the apps list, in case new tools
    // were added from the dashboard UI) fresh while the tray menu sits idle.
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      await _refreshState();
      await _rebuildMenu();
    });
  }

  /// The bare-minimum menu (Open / Exit) - always safe to set, no data
  /// dependencies. Used as the very first menu and as a fallback if
  /// building the full menu ever throws.
  Future<void> _setFallbackMenu() async {
    try {
      await trayManager.setContextMenu(Menu(items: [
        MenuItem(key: 'show', label: 'Open Dashboard'),
        MenuItem.separator(),
        MenuItem(key: 'exit', label: 'Exit Dashboard'),
      ]));
    } catch (_) {
      // If even this fails, there's nothing more we can do from Dart-land -
      // but this should never throw in practice.
    }
  }

  Future<void> _refreshState() async {
    try {
      final apps = await _launcher.loadApps();
      final running = await _launcher.runningProcessNames();
      if (mounted) {
        setState(() {
          _apps = apps;
          _runningProcessNames = running;
        });
      } else {
        _apps = apps;
        _runningProcessNames = running;
      }
    } catch (_) {
      // Keep whatever we already had rather than letting a bad apps.json
      // (or a locked/missing file on first run) crash the tray refresh loop.
    }
  }

  bool _isRunning(AppEntry app) {
    final configured = app.processName?.toLowerCase().replaceAll('.exe', '').trim();
    if (configured == null || configured.isEmpty) return false;
    return _runningProcessNames.any((p) {
      final name = p.toLowerCase().replaceAll('.exe', '').trim();
      return name == configured || name.contains(configured) || configured.contains(name);
    });
  }

  Future<void> _rebuildMenu() async {
    try {
      final running = _apps.where(_isRunning).toList();

      final items = <MenuItem>[
        MenuItem(key: 'show', label: 'Open Dashboard'),
        MenuItem.separator(),
      ];

      if (running.isEmpty) {
        items.add(MenuItem(key: 'none', label: 'No apps running', disabled: true));
      } else {
        items.add(MenuItem(key: 'running_header', label: 'RUNNING (${running.length})', disabled: true));
        for (final app in running) {
          // Tray-only tools have no window to bring forward - list them but
          // don't offer a no-op click.
          items.add(MenuItem(
            key: app.trayOnly ? 'noop' : 'focus:${app.id}',
            label: '     ${app.name}',
            disabled: app.trayOnly,
          ));
        }
      }

      items.addAll([
        MenuItem.separator(),
        MenuItem.checkbox(
          key: 'toggle_startup',
          label: 'Start with Windows',
          checked: _startWithWindows,
        ),
        MenuItem.separator(),
        MenuItem(key: 'exit', label: 'Exit Dashboard'),
      ]);

      await trayManager.setContextMenu(Menu(items: items));
    } catch (_) {
      // Never leave the tray with no menu at all - fall back to the basics.
      await _setFallbackMenu();
    }
  }

  @override
  void onTrayIconMouseDown() {
    // Left-click: show/focus the dashboard window.
    windowManager.show();
    windowManager.focus();
  }

  @override
  void onTrayIconRightMouseDown() {
    // On Windows, tray_manager doesn't auto-show the context menu on
    // right-click - it has to be popped up explicitly, or right-clicking
    // the icon just does nothing.
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) async {
    final key = menuItem.key ?? '';
    if (key == 'show') {
      windowManager.show();
      windowManager.focus();
    } else if (key == 'exit') {
      windowManager.destroy();
    } else if (key == 'toggle_startup') {
      final next = !_startWithWindows;
      final ok = await _startup.setEnabled(next);
      if (ok) {
        setState(() => _startWithWindows = next);
      }
      await _rebuildMenu();
    } else if (key.startsWith('focus:')) {
      final id = key.substring('focus:'.length);
      final matches = _apps.where((a) => a.id == id);
      if (matches.isNotEmpty) {
        await _launcher.launch(matches.first, isRunning: true);
      }
    }
  }

  // Closing the window minimizes to tray, matching your other tools' pattern.
  @override
  void onWindowClose() async {
    await windowManager.hide();
  }

  @override
  void dispose() {
    trayManager.removeListener(this);
    windowManager.removeListener(this);
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'JoErl Dev Dashboard',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: const DashboardScreen(),
    );
  }
}
