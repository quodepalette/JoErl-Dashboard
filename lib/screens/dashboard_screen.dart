import 'dart:async';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../models/app_entry.dart';
import '../services/app_launcher_service.dart';
import '../theme/app_theme.dart';
import '../widgets/add_app_dialog.dart';
import '../widgets/add_app_tile.dart';
import '../widgets/app_tile.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> with WindowListener {
  final _service = AppLauncherService();
  final _searchController = TextEditingController();

  List<AppEntry> _apps = [];
  Set<String> _runningProcessNames = {};
  String? _launchingId;
  String _searchQuery = '';
  AppCategory? _selectedCategory; // null == "All"
  Timer? _pollTimer;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final apps = await _service.loadApps();
    setState(() {
      _apps = apps;
      _loading = false;
    });
    await _refreshRunning();
    _pollTimer = Timer.periodic(const Duration(seconds: 4), (_) => _refreshRunning());
  }

  Future<void> _refreshRunning() async {
    final running = await _service.runningProcessNames();
    if (mounted) setState(() => _runningProcessNames = running);
  }

  bool _isRunning(AppEntry app) {
    final configured = app.processName?.toLowerCase().replaceAll('.exe', '').trim();
    if (configured == null || configured.isEmpty) return false;
    return _runningProcessNames.any((p) {
      final name = p.toLowerCase().replaceAll('.exe', '').trim();
      return name == configured || name.contains(configured) || configured.contains(name);
    });
  }

  Future<void> _handleLaunch(AppEntry app) async {
    // Running apps are inert in the grid now (dimmed, no click action) - the
    // tile's onTap is already disabled in that state, but guard here too
    // in case this is ever called from somewhere else. No focus/bring-to-
    // front from the dashboard; that only happens from the tray menu.
    if (_isRunning(app)) return;

    setState(() => _launchingId = app.id);
    final error = await _service.launch(app);
    if (mounted) {
      setState(() => _launchingId = null);
      if (error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: _ToastContent(icon: Icons.error_outline, iconColor: AppColors.error, title: app.name, detail: error)),
        );
      }
    }
    Future.delayed(const Duration(seconds: 1), _refreshRunning);
  }

  Future<void> _handleAddApp() async {
    final existingIds = _apps.map((a) => a.id).toSet();
    final newApp = await showAddAppDialog(context, _service, existingIds);
    if (newApp == null) return;
    setState(() => _apps = [..._apps, newApp]);
    await _service.saveApps(_apps);
    await _refreshRunning();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: _ToastContent(icon: Icons.check_circle_outline, iconColor: AppColors.success, title: '${newApp.name} added')),
      );
    }
  }

  Future<void> _handleRemoveApp(AppEntry app) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Remove app?'),
        content: Text('This removes "${app.name}" from the dashboard. You can re-add it any time — the exe itself is untouched.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _apps = _apps.where((a) => a.id != app.id).toList());
    await _service.saveApps(_apps);
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    _pollTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _showProcessDebugSheet(BuildContext context) async {
    final names = _runningProcessNames.toList()..sort();
    var query = '';
    await showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final filtered = query.isEmpty
                ? names
                : names.where((n) => n.contains(query.toLowerCase())).toList();
            return Padding(
              padding: const EdgeInsets.all(20),
              child: SizedBox(
                height: 480,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Running processes',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Match one of these exactly (minus .exe is fine) to an app\'s "processName" in apps.json.',
                      style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      onChanged: (v) => setSheetState(() => query = v),
                      style: const TextStyle(fontSize: 13),
                      decoration: InputDecoration(
                        hintText: 'Filter...',
                        prefixIcon: const Icon(Icons.search, size: 18),
                        filled: true,
                        fillColor: AppColors.surfaceElevated,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: ListView.builder(
                        itemCount: filtered.length,
                        itemBuilder: (context, i) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: SelectableText(
                            filtered[i],
                            style: const TextStyle(fontSize: 12.5, fontFamily: 'monospace'),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  List<AppEntry> get _filtered {
    return _apps.where((a) {
      final matchesCategory = _selectedCategory == null || a.category == _selectedCategory;
      final matchesSearch = _searchQuery.isEmpty ||
          a.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          a.description.toLowerCase().contains(_searchQuery.toLowerCase());
      return matchesCategory && matchesSearch;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          _TitleBar(
            runningCount: _apps.where(_isRunning).length,
            totalApps: _apps.length,
            onTapRunningCount: () => _showProcessDebugSheet(context),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : Padding(
                    padding: const EdgeInsets.fromLTRB(28, 20, 28, 28),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _Header(searchController: _searchController, onSearchChanged: (v) => setState(() => _searchQuery = v)),
                        const SizedBox(height: 18),
                        _CategoryFilterRow(
                          selected: _selectedCategory,
                          onSelected: (c) => setState(() => _selectedCategory = c),
                        ),
                        const SizedBox(height: 20),
                        Expanded(child: _buildGrid()),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildGrid() {
    final apps = _filtered;
    final showEmptyMessage = apps.isEmpty && (_searchQuery.isNotEmpty || _selectedCategory != null);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showEmptyMessage)
          const Padding(
            padding: EdgeInsets.only(bottom: 14),
            child: Text('No apps match your search.', style: TextStyle(color: AppColors.textMuted)),
          ),
        Expanded(
          child: GridView.builder(
            itemCount: apps.length + 1,
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 240,
              mainAxisExtent: 200,
              crossAxisSpacing: 14,
              mainAxisSpacing: 14,
            ),
            itemBuilder: (context, i) {
              if (i == apps.length) {
                return AddAppTile(onTap: _handleAddApp);
              }
              final app = apps[i];
              return AppTile(
                app: app,
                isRunning: _isRunning(app),
                isLaunching: _launchingId == app.id,
                onLaunch: () => _handleLaunch(app),
                onOpenFolder: app.folderPath != null ? () => _service.openFolder(app.folderPath!) : null,
                onRemove: () => _handleRemoveApp(app),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Standard toast body: colored icon + bold title, with an optional dimmer
/// detail line underneath (e.g. the exact path that failed to launch).
/// Centralized here so every SnackBar in the app looks and reads the same way.
class _ToastContent extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String? detail;

  const _ToastContent({required this.icon, required this.iconColor, required this.title, this.detail});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: iconColor),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
              ),
              if (detail != null) ...[
                const SizedBox(height: 2),
                Text(
                  detail!,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.textSecondary),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _TitleBar extends StatelessWidget {
  final int runningCount;
  final int totalApps;
  final VoidCallback onTapRunningCount;
  const _TitleBar({
    required this.runningCount,
    required this.totalApps,
    required this.onTapRunningCount,
  });

  @override
  Widget build(BuildContext context) {
    return DragToMoveArea(
      child: Container(
        height: 44,
        color: AppColors.surface,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          children: [
            const Text('⚡', style: TextStyle(fontSize: 15)),
            const SizedBox(width: 8),
            const Text(
              'JoErl Dev Dashboard',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
            ),
            const SizedBox(width: 12),
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: onTapRunningCount,
                child: Text(
                  '$runningCount / $totalApps running',
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppColors.textMuted,
                    decoration: TextDecoration.underline,
                    decorationColor: AppColors.textMuted,
                  ),
                ),
              ),
            ),
            const Spacer(),
            _WindowButton(icon: Icons.remove, onPressed: () => windowManager.minimize()),
            _WindowButton(
              icon: Icons.crop_square,
              onPressed: () async {
                if (await windowManager.isMaximized()) {
                  windowManager.unmaximize();
                } else {
                  windowManager.maximize();
                }
              },
            ),
            _WindowButton(icon: Icons.close, hoverColor: Colors.redAccent, onPressed: () => windowManager.hide()),
          ],
        ),
      ),
    );
  }
}

class _WindowButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final Color? hoverColor;
  const _WindowButton({required this.icon, required this.onPressed, this.hoverColor});

  @override
  State<_WindowButton> createState() => _WindowButtonState();
}

class _WindowButtonState extends State<_WindowButton> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _hover ? (widget.hoverColor ?? AppColors.surfaceElevated).withValues(alpha: 0.2) : null,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(widget.icon, size: 15, color: AppColors.textSecondary),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  const _Header({required this.searchController, required this.onSearchChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('JOERL WORLD', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
            SizedBox(height: 2),
            Text('Launch, track, and manage tools', style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
          ],
        ),
        const Spacer(),
        SizedBox(
          width: 260,
          height: 38,
          child: TextField(
            controller: searchController,
            onChanged: onSearchChanged,
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Search apps...',
              hintStyle: const TextStyle(fontSize: 13, color: AppColors.textMuted),
              prefixIcon: const Icon(Icons.search, size: 18, color: AppColors.textMuted),
              filled: true,
              fillColor: AppColors.surface,
              contentPadding: const EdgeInsets.symmetric(vertical: 0),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(9),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(9),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(9),
                borderSide: const BorderSide(color: AppColors.accentGreen),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _CategoryFilterRow extends StatelessWidget {
  final AppCategory? selected;
  final ValueChanged<AppCategory?> onSelected;
  const _CategoryFilterRow({required this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    Widget chip(String label, AppCategory? value) {
      final isSelected = selected == value;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: GestureDetector(
          onTap: () => onSelected(value),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: isSelected ? AppColors.accentGreen.withValues(alpha: 0.15) : AppColors.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: isSelected ? AppColors.accentGreen : AppColors.border),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: isSelected ? AppColors.accentGreen : AppColors.textSecondary,
              ),
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        chip('All', null),
        ...AppCategory.values.map((c) => chip(c.label, c)),
      ],
    );
  }
}
