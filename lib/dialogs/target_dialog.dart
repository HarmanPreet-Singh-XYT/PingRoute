import 'package:fluent_ui/fluent_ui.dart';
import '../core/theme.dart';
import '../models/target_directory.dart';

void showTargetDirectoryDialog(
  BuildContext context, {
  required ValueChanged<String> onSelectTarget,
  String initialTarget = '',
}) {
  showDialog(
    context: context,
    builder: (BuildContext context) {
      return _TargetDirectoryDialogContent(
        onSelectTarget: onSelectTarget,
        initialTarget: initialTarget,
      );
    },
  );
}

class _TargetDirectoryDialogContent extends StatefulWidget {
  const _TargetDirectoryDialogContent({
    required this.onSelectTarget,
    required this.initialTarget,
  });

  final ValueChanged<String> onSelectTarget;
  final String initialTarget;

  @override
  State<_TargetDirectoryDialogContent> createState() =>
      _TargetDirectoryDialogContentState();
}

class _TargetDirectoryDialogContentState
    extends State<_TargetDirectoryDialogContent> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _targetController = TextEditingController();
  final TextEditingController _noteController = TextEditingController();

  bool _isAdding = false;
  SavedTarget? _editingTarget;

  @override
  void initState() {
    super.initState();
    if (widget.initialTarget.trim().isNotEmpty &&
        !TargetDirectory.instance.isSaved(widget.initialTarget)) {
      _targetController.text = widget.initialTarget.trim();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _nameController.dispose();
    _targetController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  void _startAdd() {
    setState(() {
      _isAdding = true;
      _editingTarget = null;
      _nameController.clear();
      _targetController.text = widget.initialTarget.trim().isNotEmpty
          ? widget.initialTarget.trim()
          : '';
      _noteController.clear();
    });
  }

  void _startEdit(SavedTarget target) {
    setState(() {
      _isAdding = false;
      _editingTarget = target;
      _nameController.text = target.name;
      _targetController.text = target.target;
      _noteController.text = target.note;
    });
  }

  void _cancelForm() {
    setState(() {
      _isAdding = false;
      _editingTarget = null;
    });
  }

  void _saveForm() {
    final name = _nameController.text.trim();
    final target = _targetController.text.trim();
    final note = _noteController.text.trim();

    if (target.isEmpty) return;

    if (_editingTarget != null) {
      TargetDirectory.instance.updateTarget(
        _editingTarget!.copyWith(
          name: name.isNotEmpty ? name : target,
          target: target,
          note: note,
        ),
      );
    } else {
      TargetDirectory.instance.saveTarget(
        target,
        name: name.isNotEmpty ? name : target,
        note: note,
      );
    }

    setState(() {
      _isAdding = false;
      _editingTarget = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = appColors(context);
    final type = appTypography(context);

    return ListenableBuilder(
      listenable: TargetDirectory.instance,
      builder: (context, _) {
        final query = _searchController.text.trim().toLowerCase();
        final targets = TargetDirectory.instance.savedTargets.where((t) {
          if (query.isEmpty) return true;
          return t.name.toLowerCase().contains(query) ||
              t.target.toLowerCase().contains(query) ||
              t.note.toLowerCase().contains(query);
        }).toList();

        return ContentDialog(
          constraints: const BoxConstraints(maxWidth: 580, maxHeight: 620),
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(FluentIcons.contact_list, size: 20, color: colors.accent),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'IP Directory & Targets',
                        style: type.title.copyWith(fontSize: 16),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (!_isAdding && _editingTarget == null)
                Button(
                  onPressed: _startAdd,
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(FluentIcons.add, size: 14),
                      SizedBox(width: 4),
                      Text('Add'),
                    ],
                  ),
                ),
            ],
          ),
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_isAdding || _editingTarget != null) ...[
                // Add / Edit form
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: colors.panelBackground,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: colors.borderColor),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _editingTarget != null ? 'Edit Target' : 'New Target',
                        style: type.subtitle,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: InfoLabel(
                              label: 'Label / Name',
                              child: TextBox(
                                placeholder: 'e.g. Cloudflare Primary',
                                controller: _nameController,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: InfoLabel(
                              label: 'Target (IP or Domain)*',
                              child: TextBox(
                                placeholder: 'e.g. 1.1.1.1 or example.com',
                                controller: _targetController,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      InfoLabel(
                        label: 'Notes (optional)',
                        child: TextBox(
                          placeholder: 'e.g. Gateway in server rack #2',
                          controller: _noteController,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Button(
                            onPressed: _cancelForm,
                            child: const Text('Cancel'),
                          ),
                          const SizedBox(width: 8),
                          FilledButton(
                            onPressed: _saveForm,
                            child: Text(_editingTarget != null ? 'Save Changes' : 'Add Target'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],

              // Search bar
              TextBox(
                controller: _searchController,
                placeholder: 'Search saved targets by name, IP, or notes...',
                prefix: const Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: Icon(FluentIcons.search, size: 14),
                ),
                suffix: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(FluentIcons.clear, size: 12),
                        onPressed: () {
                          setState(() {
                            _searchController.clear();
                          });
                        },
                      )
                    : null,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),

              // Targets list
              Expanded(
                child: targets.isEmpty
                    ? Center(
                        child: Text(
                          query.isNotEmpty
                              ? 'No targets match "$query"'
                              : 'No saved targets yet. Add your first IP above!',
                          style: type.subtitle,
                        ),
                      )
                    : ListView.separated(
                        primary: false,
                        itemCount: targets.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final item = targets[index];
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: colors.panelBackground,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: colors.borderColor),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Text(item.name, style: type.bodyStrong),
                                          const SizedBox(width: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: colors.accent.withValues(alpha: 0.15),
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              item.target,
                                              style: type.caption.copyWith(
                                                color: colors.accent,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      if (item.note.isNotEmpty) ...[
                                        const SizedBox(height: 4),
                                        Text(
                                          item.note,
                                          style: type.caption,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                FilledButton(
                                  onPressed: () {
                                    widget.onSelectTarget(item.target);
                                    Navigator.of(context).pop();
                                  },
                                  child: const Text('Use Target'),
                                ),
                                const SizedBox(width: 6),
                                IconButton(
                                  icon: Icon(FluentIcons.edit, size: 14, color: colors.textSecondary),
                                  onPressed: () => _startEdit(item),
                                ),
                                IconButton(
                                  icon: Icon(FluentIcons.delete, size: 14, color: colors.latencyBad),
                                  onPressed: () => TargetDirectory.instance.deleteTarget(item.id),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
          actions: [
            Button(
              child: const Text('Close'),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        );
      },
    );
  }
}
