import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../models/app_entry.dart';
import '../services/app_launcher_service.dart';
import '../theme/app_theme.dart';

/// Modal for registering a new app. Handles its own text controllers and
/// hands a finished [AppEntry] back to the caller via [showAddAppDialog];
/// the caller decides how to persist it.
class AddAppDialog extends StatefulWidget {
  final AppLauncherService service;
  final Set<String> existingIds;

  const AddAppDialog({super.key, required this.service, required this.existingIds});

  @override
  State<AddAppDialog> createState() => _AddAppDialogState();
}

class _AddAppDialogState extends State<AddAppDialog> {
  final _nameController = TextEditingController();
  final _descController = TextEditingController();
  final _exePathController = TextEditingController();
  final _folderPathController = TextEditingController();
  final _processNameController = TextEditingController();
  final _iconGlyphController = TextEditingController(text: '🗂️');

  AppCategory _category = AppCategory.utilities;
  Color _accentColor = AppColors.accentGreen;
  bool _folderEditedManually = false;

  static const _swatches = [
    AppColors.accentGreen,
    AppColors.accentBlue,
    AppColors.accentPurple,
    AppColors.accentPink,
    AppColors.accentAmber,
  ];

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    _exePathController.dispose();
    _folderPathController.dispose();
    _processNameController.dispose();
    _iconGlyphController.dispose();
    super.dispose();
  }

  Future<void> _browseExe() async {
    final path = await widget.service.pickExecutable();
    if (path == null) return;
    setState(() {
      _exePathController.text = path;
      _processNameController.text = p.basename(path);
      if (!_folderEditedManually) {
        _folderPathController.text = p.dirname(path);
      }
      if (_nameController.text.isEmpty) {
        final base = p.basenameWithoutExtension(path);
        _nameController.text = base
            .replaceAll(RegExp(r'[_\-]+'), ' ')
            .split(' ')
            .where((w) => w.isNotEmpty)
            .map((w) => w[0].toUpperCase() + w.substring(1))
            .join(' ');
      }
    });
  }

  Future<void> _browseFolder() async {
    final path = await widget.service.pickFolder();
    if (path == null) return;
    setState(() {
      _folderEditedManually = true;
      _folderPathController.text = path;
    });
  }

  bool get _canSave => _nameController.text.trim().isNotEmpty && _exePathController.text.trim().isNotEmpty;

  void _save() {
    if (!_canSave) return;
    final id = AppEntry.slugId(_nameController.text, widget.existingIds);
    final entry = AppEntry(
      id: id,
      name: _nameController.text.trim(),
      description: _descController.text.trim(),
      exePath: _exePathController.text.trim(),
      folderPath: _folderPathController.text.trim().isEmpty ? null : _folderPathController.text.trim(),
      category: _category,
      iconGlyph: _iconGlyphController.text.trim().isEmpty ? '🗂️' : _iconGlyphController.text.trim(),
      accentColor: _accentColor,
      processName: _processNameController.text.trim().isEmpty ? null : _processNameController.text.trim(),
    );
    Navigator.of(context).pop(entry);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Register a new app', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              const Text(
                'Saved straight to apps.json — no rebuild needed.',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 18),
              _field('Executable', required: true, child: Row(
                children: [
                  Expanded(
                    child: _textField(_exePathController, hint: r'C:\JOERL-WORLD\MyApp\myapp.exe'),
                  ),
                  const SizedBox(width: 8),
                  _browseButton(onPressed: _browseExe),
                ],
              )),
              const SizedBox(height: 12),
              _field('Name', required: true, child: _textField(_nameController, hint: 'JoErl My App')),
              const SizedBox(height: 12),
              _field('Description', child: _textField(_descController, hint: 'One line about what it does')),
              const SizedBox(height: 12),
              _field('Folder (for the "open folder" button)', child: Row(
                children: [
                  Expanded(child: _textField(_folderPathController, hint: 'Auto-filled from exe path')),
                  const SizedBox(width: 8),
                  _browseButton(onPressed: _browseFolder),
                ],
              )),
              const SizedBox(height: 12),
              _field('Process name (for the RUNNING badge)', child: _textField(_processNameController, hint: 'myapp.exe')),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _field('Category', child: _categoryDropdown()),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _field('Icon (emoji)', child: _textField(_iconGlyphController, hint: '🗂️')),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _field('Accent color', child: _colorPicker()),
              const SizedBox(height: 22),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _canSave ? _save : null,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.accentGreen,
                      foregroundColor: Colors.black,
                      disabledBackgroundColor: AppColors.surfaceElevated,
                    ),
                    child: const Text('Add app', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field(String label, {required Widget child, bool required = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
            if (required) const Text(' *', style: TextStyle(fontSize: 12, color: AppColors.accentPink)),
          ],
        ),
        const SizedBox(height: 6),
        child,
      ],
    );
  }

  Widget _textField(TextEditingController controller, {required String hint}) {
    return TextField(
      controller: controller,
      onChanged: (_) => setState(() {}),
      style: const TextStyle(fontSize: 13),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(fontSize: 12.5, color: AppColors.textMuted),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        filled: true,
        fillColor: AppColors.surfaceElevated,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.border)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.accentGreen)),
      ),
    );
  }

  Widget _browseButton({required VoidCallback onPressed}) {
    return SizedBox(
      height: 38,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: AppColors.border),
          foregroundColor: AppColors.textSecondary,
          padding: const EdgeInsets.symmetric(horizontal: 12),
        ),
        child: const Text('Browse', style: TextStyle(fontSize: 12.5)),
      ),
    );
  }

  Widget _categoryDropdown() {
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<AppCategory>(
          value: _category,
          isExpanded: true,
          dropdownColor: AppColors.surfaceElevated,
          style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
          items: AppCategory.values
              .map((c) => DropdownMenuItem(value: c, child: Text(c.label)))
              .toList(),
          onChanged: (c) => setState(() => _category = c ?? _category),
        ),
      ),
    );
  }

  Widget _colorPicker() {
    return Row(
      children: _swatches.map((color) {
        final selected = color.toARGB32() == _accentColor.toARGB32();
        return Padding(
          padding: const EdgeInsets.only(right: 10),
          child: GestureDetector(
            onTap: () => setState(() => _accentColor = color),
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(color: selected ? Colors.white : Colors.transparent, width: 2),
              ),
              child: selected ? const Icon(Icons.check, size: 14, color: Colors.black) : null,
            ),
          ),
        );
      }).toList(),
    );
  }
}

/// Convenience wrapper: shows the dialog and returns the new [AppEntry],
/// or null if the user cancelled.
Future<AppEntry?> showAddAppDialog(BuildContext context, AppLauncherService service, Set<String> existingIds) {
  return showDialog<AppEntry>(
    context: context,
    builder: (_) => AddAppDialog(service: service, existingIds: existingIds),
  );
}
