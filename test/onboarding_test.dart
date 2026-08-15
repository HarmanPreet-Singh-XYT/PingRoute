import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:PingRoute/core/theme.dart';
import 'package:PingRoute/dialogs/settings.dart';
import 'package:PingRoute/main.dart';
import 'package:PingRoute/widgets/onboarding_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Onboarding Unit & Persistence Tests', () {
    test('AppSettings tracks and persists hasCompletedOnboarding', () async {
      SharedPreferences.setMockInitialValues({'has_completed_onboarding': false});
      final settings = AppSettings.test(initialHasCompletedOnboarding: false);

      expect(settings.hasCompletedOnboarding, isFalse);

      await settings.setHasCompletedOnboarding(true);
      expect(settings.hasCompletedOnboarding, isTrue);

      await settings.resetOnboarding();
      expect(settings.hasCompletedOnboarding, isFalse);
    });
  });

  group('Onboarding Responsive Layouts & Slides Tests', () {
    testWidgets('renders OnboardingScreen at mobile width (375px) without errors',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(375, 667));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      String? completedTarget;
      bool completedAutoStart = false;

      await tester.pumpWidget(
        FluentApp(
          theme: buildFluentTheme(Brightness.light, Colors.blue),
          home: ScaffoldPage(
            padding: EdgeInsets.zero,
            content: OnboardingScreen(
              onComplete: (target, autoStart) {
                completedTarget = target;
                completedAutoStart = autoStart;
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Brand & header elements
      expect(find.text('PingRoute'), findsOneWidget);
      expect(find.text('1 / 5'), findsOneWidget);
      expect(find.text('Skip'), findsOneWidget);

      // Slide 1 Content
      expect(find.text('Welcome to PingRoute'), findsOneWidget);
      expect(find.text('Live Network Engine'), findsOneWidget);

      // Tap Next to advance
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();

      expect(find.text('2 / 5'), findsOneWidget);
      expect(find.text('Multi-Flow Workspaces'), findsOneWidget);

      // Tap Skip
      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();

      expect(completedTarget, isNotNull);
      expect(completedAutoStart, isFalse);
    });

    testWidgets('renders OnboardingScreen at tablet/iPad width (768px)',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(768, 1024));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        FluentApp(
          theme: buildFluentTheme(Brightness.dark, Colors.blue),
          home: ScaffoldPage(
            padding: EdgeInsets.zero,
            content: OnboardingScreen(
              onComplete: (_, __) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('PingRoute'), findsOneWidget);
      expect(find.text('Welcome to PingRoute'), findsOneWidget);
    });

    testWidgets('renders OnboardingScreen at desktop width (1400px) and supports quick start',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      String? chosenTarget;
      bool isAutoStart = false;

      await tester.pumpWidget(
        FluentApp(
          theme: buildFluentTheme(Brightness.dark, Colors.blue),
          home: ScaffoldPage(
            padding: EdgeInsets.zero,
            content: OnboardingScreen(
              onComplete: (target, autoStart) {
                chosenTarget = target;
                isAutoStart = autoStart;
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Navigate to slide 5 (Quick setup)
      for (int i = 0; i < 4; i++) {
        await tester.tap(find.text('Next'));
        await tester.pumpAndSettle();
      }

      expect(find.text('5 / 5'), findsOneWidget);
      expect(find.text('Ready to Start Probing'), findsOneWidget);
      expect(find.text('Start Probing'), findsOneWidget);

      // Pick Google DNS preset
      final googlePreset = find.text('Google DNS (8.8.8.8)');
      expect(googlePreset, findsOneWidget);
      await tester.tap(googlePreset);
      await tester.pumpAndSettle();

      // Tap Start Probing
      await tester.tap(find.text('Start Probing'));
      await tester.pumpAndSettle();

      expect(chosenTarget, '8.8.8.8');
      expect(isAutoStart, isTrue);
    });

    testWidgets('supports keyboard navigation in OnboardingScreen',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        FluentApp(
          theme: buildFluentTheme(Brightness.dark, Colors.blue),
          home: ScaffoldPage(
            padding: EdgeInsets.zero,
            content: OnboardingScreen(
              onComplete: (_, __) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('1 / 5'), findsOneWidget);

      // Right arrow advances slide
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(find.text('2 / 5'), findsOneWidget);

      // Left arrow goes back
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(find.text('1 / 5'), findsOneWidget);
    });

    testWidgets('supports horizontal slide and swipe gestures in OnboardingScreen',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        FluentApp(
          theme: buildFluentTheme(Brightness.dark, Colors.blue),
          home: ScaffoldPage(
            padding: EdgeInsets.zero,
            content: OnboardingScreen(
              onComplete: (_, __) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('1 / 5'), findsOneWidget);

      // Drag left to slide to page 2
      await tester.drag(find.byType(PageView), const Offset(-300, 0));
      await tester.pumpAndSettle();
      expect(find.text('2 / 5'), findsOneWidget);

      // Drag right to slide back to page 1
      await tester.drag(find.byType(PageView), const Offset(300, 0));
      await tester.pumpAndSettle();
      expect(find.text('1 / 5'), findsOneWidget);
    });

    testWidgets('showOnboardingDialog opens and dismisses modal dialog on skip or background click',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        FluentApp(
          theme: buildFluentTheme(Brightness.light, Colors.blue),
          home: ScaffoldPage(
            content: Builder(
              builder: (context) {
                return Button(
                  child: const Text('Open Tour'),
                  onPressed: () => showOnboardingDialog(context),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Open dialog
      await tester.tap(find.text('Open Tour'));
      await tester.pumpAndSettle();
      expect(find.text('Skip Tour'), findsOneWidget);

      // Tap background margin area (e.g. top-left corner (5, 5) outside the modal card)
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();

      // Dialog should be dismissed
      expect(find.text('Skip Tour'), findsNothing);
      expect(find.text('Open Tour'), findsOneWidget);
    });
  });
}
