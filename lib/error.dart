import 'package:fluent_ui/fluent_ui.dart';
import 'theme.dart';

void showErrorPopup(BuildContext context) {
  showDialog(
    context: context,
    builder: (BuildContext context) {
      final colors = appColors(context);
      final type = appTypography(context);
      return ContentDialog(
        constraints: const BoxConstraints(maxWidth: 380),
        title: Row(
          children: [
            Icon(FluentIcons.error_badge, color: colors.latencyBad),
            const SizedBox(width: 8),
            Text('Connection error', style: type.title),
          ],
        ),
        content: Text(
          'PingRoute could not reach that target. Check the IP address or '
          'domain and your network connection, then try again.',
          style: type.body,
        ),
        actions: [
          FilledButton(
            child: const Text('Close'),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      );
    },
  );
}
