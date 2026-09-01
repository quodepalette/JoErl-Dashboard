import 'package:flutter/material.dart';
import '../models/app_entry.dart';
import '../theme/app_theme.dart';

class AppTile extends StatefulWidget {
  final AppEntry app;
  final bool isRunning;
  final bool isLaunching;
  final VoidCallback onLaunch;
  final VoidCallback? onOpenFolder;
  final VoidCallback? onRemove;

  const AppTile({
    super.key,
    required this.app,
    required this.isRunning,
    required this.isLaunching,
    required this.onLaunch,
    this.onOpenFolder,
    this.onRemove,
  });

  @override
  State<AppTile> createState() => _AppTileState();
}

class _AppTileState extends State<AppTile> {
  bool _hovering = false;

  Future<void> _showContextMenu(BuildContext context, Offset position) async {
    final selection = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx, position.dy),
      color: AppColors.surfaceElevated,
      items: const [
        PopupMenuItem(value: 'remove', child: Text('Remove from dashboard', style: TextStyle(fontSize: 13))),
      ],
    );
    if (selection == 'remove') widget.onRemove?.call();
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    // No "Focus" / bring-to-front from the grid anymore - a running app's
    // tile just dims and stops responding to clicks. (Focusing a running
    // app's window is still available from the tray's "Running Apps" list,
    // which reuses AppLauncherService's focus/no-duplicate logic directly.)
    final inertWhileRunning = widget.isRunning;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      cursor: inertWhileRunning ? SystemMouseCursors.basic : SystemMouseCursors.click,
      child: GestureDetector(
        onTap: (widget.isLaunching || inertWhileRunning) ? null : widget.onLaunch,
        onSecondaryTapUp: widget.onRemove == null ? null : (details) => _showContextMenu(context, details.globalPosition),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _hovering ? AppColors.surfaceElevated : AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _hovering
                  ? app.accentColor.withValues(alpha: 0.6)
                  : AppColors.border,
              width: 1,
            ),
            boxShadow: _hovering
                ? [
                    BoxShadow(
                      color: app.accentColor.withValues(alpha: 0.18),
                      blurRadius: 20,
                      spreadRadius: -4,
                    ),
                  ]
                : [],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: app.accentColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: app.iconAsset != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.asset(
                              app.iconAsset!,
                              width: 26,
                              height: 26,
                              errorBuilder: (context, error, stackTrace) =>
                                  Text(app.iconGlyph, style: const TextStyle(fontSize: 20)),
                            ),
                          )
                        : Text(app.iconGlyph, style: const TextStyle(fontSize: 20)),
                  ),
                  const Spacer(),
                  if (app.inProgress)
                    const _Badge(label: 'WIP', color: AppColors.accentAmber)
                  else if (widget.isRunning)
                    const _Badge(label: 'RUNNING', color: AppColors.running, dot: true)
                  else if (widget.onOpenFolder != null)
                    IconButton(
                      icon: const Icon(Icons.folder_open, size: 18),
                      color: AppColors.textMuted,
                      tooltip: 'Open folder',
                      onPressed: widget.onOpenFolder,
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                app.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Expanded(
                child: Text(
                  app.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary, height: 1.3),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 34,
                child: Opacity(
                  opacity: inertWhileRunning ? 0.4 : 1.0,
                  child: OutlinedButton(
                    onPressed: (widget.isLaunching || inertWhileRunning) ? null : widget.onLaunch,
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: app.accentColor.withValues(alpha: 0.5)),
                      foregroundColor: app.accentColor,
                      disabledForegroundColor: app.accentColor,
                      padding: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: widget.isLaunching
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            widget.isRunning ? 'Running' : 'Launch',
                            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color color;
  final bool dot;
  const _Badge({required this.label, required this.color, this.dot = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot) ...[
            Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(width: 5),
          ],
          Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color, letterSpacing: 0.5)),
        ],
      ),
    );
  }
}
