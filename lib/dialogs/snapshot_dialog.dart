import 'package:fluent_ui/fluent_ui.dart';
import 'package:intl/intl.dart';
import '../core/theme.dart';
import '../models/flow_session.dart';
import '../models/snapshot.dart';
import '../models/snapshot_store.dart';

void showSaveSnapshotDialog(BuildContext context, FlowSession flow) {
  showDialog(
    context: context,
    barrierDismissible: true,
    dismissWithEsc: true,
    builder: (context) => _SaveSnapshotDialogContent(flow: flow),
  );
}

class _SaveSnapshotDialogContent extends StatefulWidget {
  const _SaveSnapshotDialogContent({required this.flow});

  final FlowSession flow;

  @override
  State<_SaveSnapshotDialogContent> createState() =>
      _SaveSnapshotDialogContentState();
}

class _SaveSnapshotDialogContentState
    extends State<_SaveSnapshotDialogContent> {
  late final TextEditingController _nameController;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: '${widget.flow.title} — ${_formatNow()}',
    );
  }

  String _formatNow() {
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${now.year}-${two(now.month)}-${two(now.day)} ${two(now.hour)}:${two(now.minute)}';
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty || _isSaving) return;

    setState(() => _isSaving = true);

    final snapshot = Snapshot.fromFlowSession(widget.flow, name: name);
    await SnapshotStore.instance.save(snapshot);

    if (!mounted) return;
    Navigator.of(context).pop();
    displayInfoBar(
      context,
      builder: (context, close) => InfoBar(
        title: const Text('Snapshot Saved'),
        content: Text('"$name" was saved.'),
        severity: InfoBarSeverity.success,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = appColors(context);
    final type = appTypography(context);
    final hasHistory = widget.flow.timelineHistory.any((h) => h.isNotEmpty);

    return ContentDialog(
      constraints: const BoxConstraints(maxWidth: 460),
      title: Row(
        children: [
          Icon(FluentIcons.camera, size: 20, color: colors.accent),
          const SizedBox(width: 10),
          Text('Save Snapshot', style: type.title.copyWith(fontSize: 16)),
        ],
      ),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!hasHistory)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                'This flow has no recorded ping history yet — the snapshot will be empty.',
                style: type.caption.copyWith(color: colors.latencyWarn),
              ),
            ),
          InfoLabel(
            label: 'Name',
            child: TextBox(
              controller: _nameController,
              placeholder: 'e.g. Home WiFi outage 8/15',
              autofocus: true,
              onSubmitted: (_) => _save(),
            ),
          ),
        ],
      ),
      actions: [
        Button(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isSaving ? null : _save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}

void showSnapshotsDialog(
  BuildContext context, {
  required ValueChanged<Snapshot> onOpenSnapshot,
}) {
  showDialog(
    context: context,
    barrierDismissible: true,
    dismissWithEsc: true,
    builder: (context) => _SnapshotsDialogContent(onOpenSnapshot: onOpenSnapshot),
  );
}

class _SnapshotsDialogContent extends StatelessWidget {
  const _SnapshotsDialogContent({required this.onOpenSnapshot});

  final ValueChanged<Snapshot> onOpenSnapshot;

  @override
  Widget build(BuildContext context) {
    final colors = appColors(context);
    final type = appTypography(context);

    return ContentDialog(
      constraints: const BoxConstraints(maxWidth: 580, maxHeight: 620),
      title: Row(
        children: [
          Icon(FluentIcons.history, size: 20, color: colors.accent),
          const SizedBox(width: 8),
          Text('Snapshots', style: type.title.copyWith(fontSize: 16)),
        ],
      ),
      content: SizedBox(
        height: 440,
        child: SnapshotsListView(
          onOpenSnapshot: (snapshot) {
            Navigator.of(context).pop();
            onOpenSnapshot(snapshot);
          },
        ),
      ),
      actions: [
        Button(
          child: const Text('Close'),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}

/// Shared list body reused by [showSnapshotsDialog] (desktop) and the
/// mobile Snapshots tab, so both surfaces render the same list/open/delete
/// behavior.
class SnapshotsListView extends StatelessWidget {
  const SnapshotsListView({super.key, required this.onOpenSnapshot});

  final ValueChanged<Snapshot> onOpenSnapshot;

  Future<void> _open(BuildContext context, SnapshotMeta meta) async {
    final type = appTypography(context);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: ProgressRing()),
    );

    final snapshot = await SnapshotStore.instance.load(meta.id);

    if (!context.mounted) return;
    Navigator.of(context).pop(); // close loading indicator

    if (snapshot == null) {
      displayInfoBar(
        context,
        builder: (context, close) => InfoBar(
          title: const Text('Failed to Open Snapshot'),
          content: Text('"${meta.name}" could not be loaded.', style: type.body),
          severity: InfoBarSeverity.error,
        ),
      );
      return;
    }

    onOpenSnapshot(snapshot);
  }

  Future<void> _delete(BuildContext context, SnapshotMeta meta) async {
    await SnapshotStore.instance.delete(meta.id);
    if (!context.mounted) return;
    displayInfoBar(
      context,
      builder: (context, close) => InfoBar(
        title: const Text('Snapshot Deleted'),
        content: Text('"${meta.name}" was deleted.'),
        severity: InfoBarSeverity.success,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = appColors(context);
    final type = appTypography(context);

    return ListenableBuilder(
      listenable: SnapshotStore.instance,
      builder: (context, _) {
        final snapshots = SnapshotStore.instance.snapshots;
        final autoSnapshots = SnapshotStore.instance.autoSnapshots;

        if (snapshots.isEmpty && autoSnapshots.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(FluentIcons.camera, size: 30, color: colors.textSecondary),
                const SizedBox(height: 10),
                Text('No snapshots yet', style: type.bodyStrong),
                const SizedBox(height: 4),
                Text(
                  'Save a snapshot from any flow to see it here.',
                  style: type.caption.copyWith(color: colors.textSecondary),
                ),
              ],
            ),
          );
        }

        final entries = <Widget>[];

        if (snapshots.isNotEmpty) {
          entries.add(_SectionHeader(label: 'Saved', type: type, colors: colors));
          for (final meta in snapshots) {
            entries.add(_SnapshotCard(
              meta: meta,
              onOpen: () => _open(context, meta),
              onDelete: () => _delete(context, meta),
            ));
          }
        }

        if (autoSnapshots.isNotEmpty) {
          entries.add(_SectionHeader(
            label: 'Auto-saved (last ${SnapshotStore.maxAutoSnapshots})',
            type: type,
            colors: colors,
          ));
          for (final meta in autoSnapshots) {
            entries.add(_SnapshotCard(
              meta: meta,
              onOpen: () => _open(context, meta),
              onDelete: () => _delete(context, meta),
            ));
          }
        }

        return ListView.separated(
          primary: false,
          itemCount: entries.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, index) => entries[index],
        );
      },
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label, required this.type, required this.colors});

  final String label;
  final AppTypography type;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 2),
      child: Text(
        label.toUpperCase(),
        style: type.caption.copyWith(
          color: colors.textSecondary,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _SnapshotCard extends StatelessWidget {
  const _SnapshotCard({
    required this.meta,
    required this.onOpen,
    required this.onDelete,
  });

  final SnapshotMeta meta;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  String _formatDuration(int ms) {
    final seconds = ms ~/ 1000;
    if (seconds < 60) return '${seconds}s';
    final minutes = seconds ~/ 60;
    if (minutes < 60) return '${minutes}m ${seconds % 60}s';
    final hours = minutes ~/ 60;
    return '${hours}h ${minutes % 60}m';
  }

  @override
  Widget build(BuildContext context) {
    final colors = appColors(context);
    final type = appTypography(context);

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
                    Flexible(
                      child: Text(
                        meta.name,
                        style: type.bodyStrong,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: colors.accent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        meta.target,
                        style: type.caption.copyWith(
                          color: colors.accent,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (meta.isAuto) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: colors.textSecondary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'AUTO',
                          style: type.caption.copyWith(
                            color: colors.textSecondary,
                            fontWeight: FontWeight.w600,
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${DateFormat('MMM d, y • h:mm a').format(meta.createdAt)} · ${_formatDuration(meta.durationMs)}',
                  style: type.caption.copyWith(color: colors.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(onPressed: onOpen, child: const Text('Open')),
          const SizedBox(width: 6),
          IconButton(
            icon: Icon(FluentIcons.delete, size: 14, color: colors.latencyBad),
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}
