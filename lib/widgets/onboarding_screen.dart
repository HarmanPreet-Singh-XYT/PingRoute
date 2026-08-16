import 'dart:ui' show PointerDeviceKind;
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import '../core/breakpoints.dart';
import '../core/theme.dart';
import '../dialogs/settings.dart';

/// Callback when user completes or skips onboarding, optionally passing
/// a target IP/hostname to start probing immediately.
typedef OnboardingCompleteCallback = void Function(String? startTarget, bool autoStart);

/// Slide data representation for the onboarding flow.
class OnboardingSlide {
  final String title;
  final String subtitle;
  final IconData icon;
  final List<String> bulletPoints;
  final String badgeText;

  const OnboardingSlide({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.bulletPoints,
    required this.badgeText,
  });
}

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({
    super.key,
    required this.onComplete,
    this.isDialogMode = false,
  });

  final OnboardingCompleteCallback onComplete;
  final bool isDialogMode;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  final FocusNode _focusNode = FocusNode();
  final TextEditingController _customTargetController =
      TextEditingController(text: '1.1.1.1');

  int _currentPage = 0;
  String _selectedPreset = '1.1.1.1';

  final List<OnboardingSlide> _slides = const [
    OnboardingSlide(
      title: 'Welcome to PingRoute',
      subtitle:
          'Next-gen visual network traceroute, hop-by-hop latency profiling, and diagnostics engine in a clean, high-performance UI.',
      icon: FluentIcons.network_tower,
      badgeText: 'Live Network Engine',
      bulletPoints: [
        'Real-time ICMP / UDP probing with millisecond precision',
        'Continuous hop-by-hop latency, jitter, and packet loss tracking',
        'Instant DNS and reverse hostname resolution across all hops',
      ],
    ),
    OnboardingSlide(
      title: 'Multi-Flow Workspaces',
      subtitle:
          'Monitor multiple cloud providers, CDN endpoints, and game servers simultaneously with responsive layouts.',
      icon: FluentIcons.grid_view_medium,
      badgeText: 'Adaptive Layouts',
      bulletPoints: [
        'Multi-tab workspace on mobile and tablet devices',
        '2-Flow Split & 4-Flow Grid views on laptops and desktops',
        'Duplicate, isolate, and compare network routes in parallel',
      ],
    ),
    OnboardingSlide(
      title: 'Deep Telemetry & Visual Charts',
      subtitle:
          'Understand your network stability at a glance with interactive charts and statistical summaries.',
      icon: FluentIcons.bar_chart_vertical,
      badgeText: 'Visual Analytics',
      bulletPoints: [
        'Color-coded hop latency bars with health thresholds (<50ms, 150ms+)',
        'Rolling timeline chart tracking latency trends and drop spikes',
        'Summary metrics: Min, Avg, Max, StdDev, and Jitter percentiles',
      ],
    ),
    OnboardingSlide(
      title: 'Directory, Diagnostics & Export',
      subtitle:
          'Curated target presets, local adapter inspection, and multi-format reporting built right in.',
      icon: FluentIcons.open_folder_horizontal,
      badgeText: 'Pro Diagnostics',
      bulletPoints: [
        'Built-in presets for Public DNS, Cloud Services, and Gaming clusters',
        'Network Interface Inspector: Gateway, DNS servers, Public IP, and MTU',
        'One-click export to formatted ASCII MTR tables, CSV, and JSON',
      ],
    ),
    OnboardingSlide(
      title: 'Ready to Start Probing',
      subtitle:
          'Pick your initial target endpoint and theme preference to launch directly into PingRoute.',
      icon: FluentIcons.rocket,
      badgeText: 'Quick Setup',
      bulletPoints: [
        'Select a curated target or enter your custom IP / Hostname',
        'Customize your dark / light theme preference',
        'Start probing instantly with one tap',
      ],
    ),
  ];

  @override
  void dispose() {
    _pageController.dispose();
    _focusNode.dispose();
    _customTargetController.dispose();
    super.dispose();
  }

  void _nextPage() {
    if (_currentPage < _slides.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      _finishOnboarding(autoStart: true);
    }
  }

  void _prevPage() {
    if (_currentPage > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _finishOnboarding({bool autoStart = false}) {
    final target = _customTargetController.text.trim().isNotEmpty
        ? _customTargetController.text.trim()
        : _selectedPreset;
    widget.onComplete(target, autoStart);
  }

  @override
  Widget build(BuildContext context) {
    final colors = appColors(context);
    final type = appTypography(context);

    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
            _nextPage();
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
            _prevPage();
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.escape) {
            _finishOnboarding(autoStart: false);
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.enter) {
            _nextPage();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final screenClass = screenClassForWidth(width);

          final content = Container(
            color: colors.pageBackground,
            child: SafeArea(
              child: Column(
                children: [
                  // Top Header Bar with Logo, Stepper, and Skip button
                  _buildHeader(colors, type, screenClass),

                  // Main Content Carousel with Slide Gestures
                  Expanded(
                    child: GestureDetector(
                      onHorizontalDragEnd: (details) {
                        final velocity = details.primaryVelocity ?? 0;
                        if (velocity < -120) {
                          _nextPage();
                        } else if (velocity > 120) {
                          _prevPage();
                        }
                      },
                      child: ScrollConfiguration(
                        behavior: const _OnboardingScrollBehavior(),
                        child: PageView.builder(
                          controller: _pageController,
                          physics: const BouncingScrollPhysics(),
                          onPageChanged: (page) => setState(() => _currentPage = page),
                          itemCount: _slides.length,
                          itemBuilder: (context, index) {
                            final slide = _slides[index];
                            if (screenClass == ScreenClass.mobile) {
                              return _buildMobileSlide(slide, colors, type, index);
                            } else if (screenClass == ScreenClass.tablet) {
                              return _buildTabletSlide(slide, colors, type, index);
                            } else {
                              return _buildDesktopSlide(slide, colors, type, index);
                            }
                          },
                        ),
                      ),
                    ),
                  ),

                  // Bottom Action Bar (Back, Dots Indicator, Next / Start)
                  _buildBottomBar(colors, type, screenClass),
                ],
              ),
            ),
          );

          if (widget.isDialogMode) {
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _finishOnboarding(autoStart: false),
              child: Center(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {}, // Prevent click inside the card from closing
                  child: Container(
                    width: screenClass == ScreenClass.mobile
                        ? double.infinity
                        : screenClass == ScreenClass.tablet
                            ? 650
                            : 880,
                    height: screenClass == ScreenClass.mobile
                        ? double.infinity
                        : screenClass == ScreenClass.tablet
                            ? 600
                            : 620,
                    margin: screenClass == ScreenClass.mobile
                        ? EdgeInsets.zero
                        : const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: colors.panelBackground,
                      borderRadius: screenClass == ScreenClass.mobile
                          ? BorderRadius.zero
                          : BorderRadius.circular(16),
                      border: screenClass == ScreenClass.mobile
                          ? null
                          : Border.all(color: colors.borderColor),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.35),
                          blurRadius: 28,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: content,
                  ),
                ),
              ),
            );
          }

          return content;
        },
      ),
    );
  }

  Widget _buildHeader(AppColors colors, AppTypography type, ScreenClass screenClass) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: screenClass == ScreenClass.mobile ? 16 : 24,
        vertical: 12,
      ),
      decoration: BoxDecoration(
        color: colors.panelBackground,
        border: Border(bottom: BorderSide(color: colors.borderColor)),
      ),
      child: Row(
        children: [
          // App Icon & Brand
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: colors.accent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: colors.accent.withValues(alpha: 0.3)),
            ),
            child: Icon(FluentIcons.globe, size: 18, color: colors.accent),
          ),
          const SizedBox(width: 8),
          Text(
            'PingRoute',
            style: type.subtitle.copyWith(
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
              fontSize: 15,
            ),
          ),
          if (screenClass != ScreenClass.mobile) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: colors.accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'v1.1',
                style: type.caption.copyWith(
                  color: colors.accent,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
          const Spacer(),

          // Page Indicator Chip
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: colors.panelBackgroundAlt,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: colors.borderColor),
            ),
            child: Text(
              '${_currentPage + 1} / ${_slides.length}',
              style: type.caption.copyWith(
                fontWeight: FontWeight.w600,
                color: colors.textSecondary,
                fontSize: 11,
              ),
            ),
          ),

          const SizedBox(width: 8),

          // Skip Button
          Button(
            onPressed: () => _finishOnboarding(autoStart: false),
            child: Text(
              screenClass == ScreenClass.mobile ? 'Skip' : 'Skip Tour',
              style: type.body.copyWith(
                color: colors.textSecondary,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar(
      AppColors colors, AppTypography type, ScreenClass screenClass) {
    final isLastPage = _currentPage == _slides.length - 1;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: screenClass == ScreenClass.mobile ? 16 : 24,
        vertical: 14,
      ),
      decoration: BoxDecoration(
        color: colors.panelBackground,
        border: Border(top: BorderSide(color: colors.borderColor)),
      ),
      child: Row(
        children: [
          // Back Button
          if (_currentPage > 0)
            Button(
              onPressed: _prevPage,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(FluentIcons.chevron_left, size: 12),
                  const SizedBox(width: 4),
                  Text('Back', style: type.body),
                ],
              ),
            )
          else
            const SizedBox(width: 70),

          const Spacer(),

          // Page Indicator Dots
          Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(_slides.length, (index) {
              final isSelected = index == _currentPage;
              return GestureDetector(
                onTap: () => _pageController.animateToPage(
                  index,
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                ),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: isSelected ? 22 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: isSelected
                        ? colors.accent
                        : colors.textSecondary.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              );
            }),
          ),

          const Spacer(),

          // Next or Start Probing Button
          FilledButton(
            onPressed: _nextPage,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  isLastPage ? 'Start Probing' : 'Next',
                  style: type.body.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 6),
                Icon(
                  isLastPage ? FluentIcons.play : FluentIcons.chevron_right,
                  size: 12,
                  color: Colors.white,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // MOBILE SLIDE LAYOUT (<600px)
  // ==========================================
  Widget _buildMobileSlide(
      OnboardingSlide slide, AppColors colors, AppTypography type, int index) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Badge
          _buildBadge(slide.badgeText, colors, type),
          const SizedBox(height: 12),

          // Title & Subtitle
          Text(slide.title, style: type.title.copyWith(fontSize: 22)),
          const SizedBox(height: 8),
          Text(
            slide.subtitle,
            style: type.body.copyWith(
              color: colors.textSecondary,
              height: 1.4,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 16),

          // Interactive Visual Preview Mock
          _buildVisualMock(index, colors, type, isCompact: true),
          const SizedBox(height: 16),

          // Key Feature Highlights
          if (index < _slides.length - 1)
            _buildFeatureList(slide.bulletPoints, colors, type)
          else
            _buildQuickSetupPanel(colors, type, isCompact: true),
        ],
      ),
    );
  }

  // ==========================================
  // TABLET / IPAD SLIDE LAYOUT (600px - 1000px)
  // ==========================================
  Widget _buildTabletSlide(
      OnboardingSlide slide, AppColors colors, AppTypography type, int index) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 620 || widget.isDialogMode;
        if (isNarrow) {
          return SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildBadge(slide.badgeText, colors, type),
                const SizedBox(height: 10),
                Text(slide.title, style: type.title.copyWith(fontSize: 22)),
                const SizedBox(height: 8),
                Text(
                  slide.subtitle,
                  style: type.body.copyWith(
                    color: colors.textSecondary,
                    height: 1.45,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 16),
                _buildVisualMock(index, colors, type, isCompact: true),
                const SizedBox(height: 16),
                if (index < _slides.length - 1)
                  _buildFeatureList(slide.bulletPoints, colors, type)
                else
                  _buildQuickSetupPanel(colors, type, isCompact: true),
              ],
            ),
          );
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 6,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildBadge(slide.badgeText, colors, type),
                    const SizedBox(height: 10),
                    Text(slide.title, style: type.title.copyWith(fontSize: 24)),
                    const SizedBox(height: 8),
                    Text(
                      slide.subtitle,
                      style: type.body.copyWith(
                        color: colors.textSecondary,
                        height: 1.45,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 18),
                    if (index < _slides.length - 1)
                      _buildFeatureList(slide.bulletPoints, colors, type)
                    else
                      _buildQuickSetupPanel(colors, type, isCompact: false),
                  ],
                ),
              ),
              const SizedBox(width: 24),
              Expanded(
                flex: 5,
                child: _buildVisualMock(index, colors, type, isCompact: false),
              ),
            ],
          ),
        );
      },
    );
  }

  // ==========================================
  // DESKTOP & LAPTOP SLIDE LAYOUT (>1000px)
  // ==========================================
  Widget _buildDesktopSlide(
      OnboardingSlide slide, AppColors colors, AppTypography type, int index) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Left Column: Story, Title, Feature Badges & Bullets
          Expanded(
            flex: 5,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildBadge(slide.badgeText, colors, type),
                const SizedBox(height: 14),
                Text(
                  slide.title,
                  style: type.title.copyWith(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  slide.subtitle,
                  style: type.body.copyWith(
                    color: colors.textSecondary,
                    height: 1.5,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 24),
                if (index < _slides.length - 1)
                  _buildFeatureList(slide.bulletPoints, colors, type)
                else
                  _buildQuickSetupPanel(colors, type, isCompact: false),
              ],
            ),
          ),

          const SizedBox(width: 36),

          // Right Column: Interactive UI Visual Illustration Mock
          Expanded(
            flex: 5,
            child: _buildVisualMock(index, colors, type, isCompact: false),
          ),
        ],
      ),
    );
  }

  Widget _buildBadge(String text, AppColors colors, AppTypography type) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: colors.accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.accent.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: colors.accent,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            text,
            style: type.caption.copyWith(
              color: colors.accent,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureList(
      List<String> points, AppColors colors, AppTypography type) {
    return Column(
      children: points.map((point) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 3),
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: colors.latencyGood.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  FluentIcons.check_mark,
                  size: 10,
                  color: colors.latencyGood,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  point,
                  style: type.body.copyWith(
                    color: colors.textPrimary,
                    fontSize: 13.5,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  // ==========================================
  // DESKTOP WINDOW FRAME HELPER
  // ==========================================
  Widget _buildDesktopWindowFrame({
    required Widget child,
    required String title,
    required AppColors colors,
    required AppTypography type,
    Widget? trailing,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: colors.cardBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.16),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Window title bar with mac-style controls
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: colors.panelBackgroundAlt,
              border: Border(bottom: BorderSide(color: colors.borderColor)),
            ),
            child: Row(
              children: [
                Container(
                  width: 9,
                  height: 9,
                  decoration: const BoxDecoration(
                    color: Color(0xffFF5F56),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  width: 9,
                  height: 9,
                  decoration: const BoxDecoration(
                    color: Color(0xffFFBD2E),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  width: 9,
                  height: 9,
                  decoration: const BoxDecoration(
                    color: Color(0xff27C93F),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: type.caption.copyWith(
                      fontWeight: FontWeight.bold,
                      color: colors.textSecondary,
                      fontSize: 11,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (trailing != null) trailing,
              ],
            ),
          ),
          // Window body
          Padding(
            padding: const EdgeInsets.all(12),
            child: child,
          ),
        ],
      ),
    );
  }

  // ==========================================
  // VISUAL ILLUSTRATION MOCKS FOR EACH SLIDE
  // ==========================================
  Widget _buildVisualMock(
      int index, AppColors colors, AppTypography type, {required bool isCompact}) {
    switch (index) {
      case 0:
        return _buildHopPathMock(colors, type, isCompact);
      case 1:
        return _buildWorkspacesMock(colors, type, isCompact);
      case 2:
        return _buildChartsMock(colors, type, isCompact);
      case 3:
        return _buildDirectoryExportMock(colors, type, isCompact);
      case 4:
        return _buildTargetLaunchMock(colors, type, isCompact);
      default:
        return const SizedBox();
    }
  }

  Widget _buildHopPathMock(
      AppColors colors, AppTypography type, bool isCompact) {
    if (!isCompact) {
      return _buildDesktopWindowFrame(
        title: 'PingRoute — Live Traceroute (1.1.1.1)',
        colors: colors,
        type: type,
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: colors.latencyGood.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: colors.latencyGood,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                'LIVE • 1000ms',
                style: type.caption.copyWith(
                  color: colors.latencyGood,
                  fontSize: 9.5,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
        child: Column(
          children: [
            // Connected Topology Nodes
            _buildTopologyNode(
              hop: '1',
              label: 'Local Gateway (192.168.1.1)',
              latency: '1.2 ms',
              icon: FluentIcons.home,
              colors: colors,
              type: type,
            ),
            _buildTopologyLink(colors),
            _buildTopologyNode(
              hop: '2',
              label: 'ISP Backbone (10.240.0.1)',
              latency: '8.4 ms',
              icon: FluentIcons.network_tower,
              colors: colors,
              type: type,
            ),
            _buildTopologyLink(colors),
            _buildTopologyNode(
              hop: '3',
              label: 'Transit Exchange (172.16.8.44)',
              latency: '14.1 ms',
              icon: FluentIcons.cloud,
              colors: colors,
              type: type,
            ),
            _buildTopologyLink(colors),
            _buildTopologyNode(
              hop: '4',
              label: 'Target: Cloudflare Anycast (1.1.1.1)',
              latency: '11.8 ms',
              icon: FluentIcons.globe,
              isDestination: true,
              colors: colors,
              type: type,
            ),
            const SizedBox(height: 10),
            // Telemetry HUD Bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: colors.panelBackgroundAlt,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: colors.borderColor),
              ),
              child: Row(
                children: [
                  Expanded(child: _buildHudStat('Packets', '64/64', colors, type)),
                  Expanded(child: _buildHudStat('Loss', '0.0%', colors, type, highlightGood: true)),
                  Expanded(child: _buildHudStat('Avg', '11.8 ms', colors, type)),
                  Expanded(child: _buildHudStat('Jitter', '1.2 ms', colors, type)),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // Mobile Compact version
    final hops = [
      {'hop': '1', 'ip': '192.168.1.1 (Gateway)', 'ms': '1.2 ms'},
      {'hop': '2', 'ip': '10.240.0.1 (ISP Core)', 'ms': '8.4 ms'},
      {'hop': '3', 'ip': '172.16.8.44 (Transit)', 'ms': '14.1 ms'},
      {'hop': '4', 'ip': '1.1.1.1 (Cloudflare DNS)', 'ms': '11.8 ms'},
    ];

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.cardBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(FluentIcons.speed_high, size: 14, color: colors.accent),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Live Traceroute Stream',
                  style: type.caption.copyWith(fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: colors.latencyGood.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'HEALTHY',
                  style: type.caption.copyWith(
                    color: colors.latencyGood,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...hops.map((h) {
            final isTarget = h['hop'] == '4';
            return Container(
              margin: const EdgeInsets.only(bottom: 5),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: isTarget
                    ? colors.accent.withValues(alpha: 0.08)
                    : colors.panelBackgroundAlt,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: isTarget
                      ? colors.accent.withValues(alpha: 0.3)
                      : colors.borderColor,
                ),
              ),
              child: Row(
                children: [
                  Text(
                    '#${h['hop']}',
                    style: type.caption.copyWith(
                      fontWeight: FontWeight.bold,
                      color: isTarget ? colors.accent : colors.textSecondary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      h['ip']!,
                      style: type.caption.copyWith(
                        fontWeight: isTarget ? FontWeight.bold : FontWeight.normal,
                        fontSize: 11.5,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: colors.latencyGood.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      h['ms']!,
                      style: type.caption.copyWith(
                        color: colors.latencyGood,
                        fontWeight: FontWeight.bold,
                        fontSize: 10.5,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildTopologyNode({
    required String hop,
    required String label,
    required String latency,
    required IconData icon,
    required AppColors colors,
    required AppTypography type,
    bool isDestination = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isDestination
            ? colors.accent.withValues(alpha: 0.12)
            : colors.panelBackgroundAlt,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDestination ? colors.accent : colors.borderColor,
          width: isDestination ? 1.5 : 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: isDestination
                  ? colors.accent.withValues(alpha: 0.2)
                  : colors.borderColor.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Icon(icon, size: 12, color: isDestination ? colors.accent : colors.textSecondary),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: colors.cardBackground,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: colors.borderColor),
            ),
            child: Text(
              '#$hop',
              style: type.caption.copyWith(
                fontWeight: FontWeight.bold,
                fontSize: 10,
                color: isDestination ? colors.accent : colors.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: type.caption.copyWith(
                fontWeight: isDestination ? FontWeight.bold : FontWeight.w500,
                fontSize: 11.5,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: colors.latencyGood.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              latency,
              style: type.caption.copyWith(
                color: colors.latencyGood,
                fontWeight: FontWeight.bold,
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopologyLink(AppColors colors) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          const SizedBox(width: 18),
          Container(
            width: 2,
            height: 8,
            color: colors.accent.withValues(alpha: 0.4),
          ),
          const SizedBox(width: 8),
          Container(
            width: 3,
            height: 3,
            decoration: BoxDecoration(
              color: colors.accent,
              shape: BoxShape.circle,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHudStat(String label, String value, AppColors colors, AppTypography type, {bool highlightGood = false}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: type.caption.copyWith(fontSize: 9.5, color: colors.textSecondary),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: type.caption.copyWith(
            fontWeight: FontWeight.bold,
            fontSize: 11,
            color: highlightGood ? colors.latencyGood : colors.textPrimary,
          ),
        ),
      ],
    );
  }

  Widget _buildWorkspacesMock(
      AppColors colors, AppTypography type, bool isCompact) {
    if (!isCompact) {
      return _buildDesktopWindowFrame(
        title: 'Multi-Flow Workspace — 2-Flow Split View',
        colors: colors,
        type: type,
        trailing: Wrap(
          spacing: 4,
          children: [
            _buildPillTag('Tabs', isSelected: false, colors: colors, type: type),
            _buildPillTag('2-Flow Split', isSelected: true, colors: colors, type: type),
            _buildPillTag('4-Flow Grid', isSelected: false, colors: colors, type: type),
          ],
        ),
        child: Column(
          children: [
            // Tabs Bar simulation
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              decoration: BoxDecoration(
                color: colors.panelBackgroundAlt,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: colors.borderColor),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _buildTabPill('1.1.1.1 (Cloudflare)', isActive: true, colors: colors, type: type),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: _buildTabPill('8.8.8.8 (Google DNS)', isActive: true, colors: colors, type: type),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: colors.cardBackground,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: colors.borderColor),
                    ),
                    child: Icon(FluentIcons.add, size: 10, color: colors.accent),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            // Side by Side Live Split Windows
            Row(
              children: [
                // Pane 1
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: colors.panelBackgroundAlt,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: colors.accent.withValues(alpha: 0.6)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(FluentIcons.globe, size: 12, color: colors.accent),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'Cloudflare (1.1.1.1)',
                                style: type.caption.copyWith(fontWeight: FontWeight.bold),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Avg: 11.4 ms', style: type.caption.copyWith(fontSize: 10.5, color: colors.latencyGood, fontWeight: FontWeight.bold)),
                            Text('0% Loss', style: type.caption.copyWith(fontSize: 10.5, color: colors.textSecondary)),
                          ],
                        ),
                        const SizedBox(height: 6),
                        // Mini Sparkline bars
                        SizedBox(
                          height: 24,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: List.generate(8, (i) {
                              final heights = [10.0, 12.0, 11.0, 14.0, 11.5, 12.0, 10.8, 11.4];
                              return Container(
                                width: 8,
                                height: heights[i % heights.length],
                                decoration: BoxDecoration(
                                  color: colors.latencyGood.withValues(alpha: 0.75),
                                  borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
                                ),
                              );
                            }),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                // Pane 2
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: colors.panelBackgroundAlt,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: colors.borderColor),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(FluentIcons.globe, size: 12, color: colors.textSecondary),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'Google DNS (8.8.8.8)',
                                style: type.caption.copyWith(fontWeight: FontWeight.bold),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Avg: 14.9 ms', style: type.caption.copyWith(fontSize: 10.5, color: colors.latencyGood, fontWeight: FontWeight.bold)),
                            Text('0% Loss', style: type.caption.copyWith(fontSize: 10.5, color: colors.textSecondary)),
                          ],
                        ),
                        const SizedBox(height: 6),
                        // Mini Sparkline bars
                        SizedBox(
                          height: 24,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: List.generate(8, (i) {
                              final heights = [14.0, 15.0, 14.2, 16.0, 15.1, 14.8, 15.5, 14.9];
                              return Container(
                                width: 8,
                                height: heights[i % heights.length],
                                decoration: BoxDecoration(
                                  color: colors.accent.withValues(alpha: 0.75),
                                  borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
                                ),
                              );
                            }),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    // Mobile / Tablet compact
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.cardBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(FluentIcons.view, size: 14, color: colors.accent),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Split View & Tab Switching',
                  style: type.caption.copyWith(fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: colors.panelBackgroundAlt,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: colors.accent),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Cloudflare (1.1.1.1)', style: type.caption.copyWith(fontWeight: FontWeight.bold, fontSize: 11), overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 3),
                      Text('11.4 ms • 0% Loss', style: type.caption.copyWith(color: colors.textSecondary, fontSize: 10)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: colors.panelBackgroundAlt,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: colors.borderColor),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Google (8.8.8.8)', style: type.caption.copyWith(fontWeight: FontWeight.bold, fontSize: 11), overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 3),
                      Text('15.2 ms • 0% Loss', style: type.caption.copyWith(color: colors.textSecondary, fontSize: 10)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTabPill(String title, {required bool isActive, required AppColors colors, required AppTypography type}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isActive ? colors.cardBackground : Colors.transparent,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: isActive ? colors.borderColor : Colors.transparent),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(FluentIcons.globe, size: 10, color: isActive ? colors.accent : colors.textSecondary),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              title,
              style: type.caption.copyWith(
                fontSize: 10.5,
                fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                color: isActive ? colors.textPrimary : colors.textSecondary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPillTag(String label, {required bool isSelected, required AppColors colors, required AppTypography type}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: isSelected ? colors.accent : colors.cardBackground,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: isSelected ? colors.accent : colors.borderColor),
      ),
      child: Text(
        label,
        style: type.caption.copyWith(
          color: isSelected ? Colors.white : colors.textSecondary,
          fontSize: 9.5,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
    );
  }

  Widget _buildChartsMock(
      AppColors colors, AppTypography type, bool isCompact) {
    final bars = [
      {'name': 'Hop 1', 'height': 0.18, 'ms': '1.2ms', 'color': colors.latencyGood},
      {'name': 'Hop 2', 'height': 0.40, 'ms': '8.4ms', 'color': colors.latencyGood},
      {'name': 'Hop 3', 'height': 0.65, 'ms': '14.1ms', 'color': colors.latencyGood},
      {'name': 'Hop 4', 'height': 0.55, 'ms': '11.8ms', 'color': colors.latencyGood},
      {'name': 'Hop 5', 'height': 0.85, 'ms': '22.0ms', 'color': colors.latencyWarn},
    ];

    if (!isCompact) {
      return _buildDesktopWindowFrame(
        title: 'Telemetry Analytics & Latency Histograms',
        colors: colors,
        type: type,
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: colors.cardBackground,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: colors.borderColor),
          ),
          child: Text('WINDOW: 25 PKTS', style: type.caption.copyWith(fontSize: 9.5, fontWeight: FontWeight.bold, color: colors.textSecondary)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Latency Bar Chart Section
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: colors.panelBackgroundAlt,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: colors.borderColor),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: Text(
                          'Hop Latency Distribution',
                          style: type.caption.copyWith(fontWeight: FontWeight.bold, fontSize: 11),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildLegendDot(colors.latencyGood, '<50ms Fast', colors, type),
                          const SizedBox(width: 6),
                          _buildLegendDot(colors.latencyWarn, '50-150ms', colors, type),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 75,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: bars.map((b) {
                        return Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text(
                              b['ms'] as String,
                              style: type.caption.copyWith(
                                fontSize: 9.5,
                                fontWeight: FontWeight.bold,
                                color: b['color'] as Color,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Container(
                              width: 32,
                              height: 48 * (b['height'] as double),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    b['color'] as Color,
                                    (b['color'] as Color).withValues(alpha: 0.5),
                                  ],
                                ),
                                borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              b['name'] as String,
                              style: type.caption.copyWith(fontSize: 9.5, color: colors.textSecondary),
                            ),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            // Rolling Timeline Sparkline Preview
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: colors.panelBackgroundAlt,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: colors.borderColor),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Rolling Jitter & Stability Trend', style: type.caption.copyWith(fontWeight: FontWeight.bold, fontSize: 11)),
                      Text('Jitter: 1.2ms (Stable)', style: type.caption.copyWith(color: colors.latencyGood, fontSize: 10, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Simulated continuous waveform
                  SizedBox(
                    height: 28,
                    child: CustomPaint(
                      painter: _MiniWaveformPainter(color: colors.accent),
                      child: Container(),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // Compact layout
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.cardBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(FluentIcons.chart, size: 14, color: colors.accent),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Latency Distribution & Trends',
                  style: type.caption.copyWith(fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 70,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: bars.map((b) {
                return Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      b['ms'] as String,
                      style: type.caption.copyWith(
                        fontSize: 9.5,
                        fontWeight: FontWeight.bold,
                        color: b['color'] as Color,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Container(
                      width: 24,
                      height: 42 * (b['height'] as double),
                      decoration: BoxDecoration(
                        color: (b['color'] as Color).withValues(alpha: 0.85),
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(b['name'] as String, style: type.caption.copyWith(fontSize: 9)),
                  ],
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLegendDot(Color dotColor, String label, AppColors colors, AppTypography type) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 6, height: 6, decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(label, style: type.caption.copyWith(fontSize: 9.5, color: colors.textSecondary)),
      ],
    );
  }

  Widget _buildDirectoryExportMock(
      AppColors colors, AppTypography type, bool isCompact) {
    if (!isCompact) {
      return _buildDesktopWindowFrame(
        title: 'Target Directory & Telemetry Export Terminal',
        colors: colors,
        type: type,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Presets category pills
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _buildPresetChip('🌐 1.1.1.1 (Cloudflare)', '11ms', colors, type, isSelected: true),
                _buildPresetChip('🌐 8.8.8.8 (Google)', '14ms', colors, type),
                _buildPresetChip('☁️ AWS us-east-1', '28ms', colors, type),
                _buildPresetChip('🎮 Steam CDN', '16ms', colors, type),
              ],
            ),
            const SizedBox(height: 10),
            // Dark Terminal MTR Table Simulation
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xff121417),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xff2A2E33)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(FluentIcons.code, size: 11, color: colors.accent),
                      const SizedBox(width: 6),
                      Text(
                        'MTR Telemetry Output (ASCII Report)',
                        style: type.caption.copyWith(color: const Color(0xff8B949E), fontSize: 10, fontFamily: 'monospace'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'HOST: 1.1.1.1        Loss%   Snt   Last    Avg    Min    Max\n'
                    ' 1.|-- 192.168.1.1    0.0%    32   1.2ms  1.1ms  0.9ms  1.8ms\n'
                    ' 2.|-- 10.240.0.1     0.0%    32   8.4ms  8.1ms  7.4ms  9.2ms\n'
                    ' 3.|-- 1.1.1.1        0.0%    32  11.8ms 11.5ms 10.9ms 13.6ms',
                    style: type.caption.copyWith(
                      color: const Color(0xff7EE787),
                      fontSize: 10,
                      fontFamily: 'monospace',
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            // Export Format Quick Actions
            Row(
              children: [
                Expanded(child: _buildExportButton(FluentIcons.copy, 'Copy MTR', colors, type)),
                const SizedBox(width: 6),
                Expanded(child: _buildExportButton(FluentIcons.table, 'CSV', colors, type)),
                const SizedBox(width: 6),
                Expanded(child: _buildExportButton(FluentIcons.code, 'JSON', colors, type)),
              ],
            ),
          ],
        ),
      );
    }

    // Compact mobile
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.cardBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(FluentIcons.folder_horizontal, size: 14, color: colors.accent),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Presets & Diagnostic Exports',
                  style: type.caption.copyWith(fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _buildPill('🌐 Public DNS', colors, type),
              _buildPill('☁️ Cloud & CDN', colors, type),
              _buildPill('🎮 Gaming Clusters', colors, type),
            ],
          ),
          const SizedBox(height: 8),
          Divider(style: DividerThemeData(decoration: BoxDecoration(color: colors.borderColor))),
          const SizedBox(height: 6),
          Wrap(
            alignment: WrapAlignment.spaceAround,
            spacing: 6,
            runSpacing: 4,
            children: [
              _buildFormatTag('MTR ASCII', colors, type),
              _buildFormatTag('CSV Export', colors, type),
              _buildFormatTag('JSON Data', colors, type),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPresetChip(String name, String latency, AppColors colors, AppTypography type, {bool isSelected = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isSelected ? colors.accent.withValues(alpha: 0.15) : colors.panelBackgroundAlt,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: isSelected ? colors.accent : colors.borderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(name, style: type.caption.copyWith(fontSize: 10.5, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: colors.latencyGood.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(latency, style: type.caption.copyWith(fontSize: 9, color: colors.latencyGood, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildExportButton(IconData icon, String label, AppColors colors, AppTypography type) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colors.panelBackgroundAlt,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: colors.borderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: colors.accent),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              style: type.caption.copyWith(fontSize: 10.5, fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPill(String label, AppColors colors, AppTypography type) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colors.panelBackgroundAlt,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.borderColor),
      ),
      child: Text(label, style: type.caption.copyWith(fontSize: 11)),
    );
  }

  Widget _buildFormatTag(String label, AppColors colors, AppTypography type) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: colors.accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: type.caption.copyWith(
          color: colors.accent,
          fontWeight: FontWeight.bold,
          fontSize: 11,
        ),
      ),
    );
  }

  Widget _buildTargetLaunchMock(
      AppColors colors, AppTypography type, bool isCompact) {
    if (!isCompact) {
      return _buildDesktopWindowFrame(
        title: 'Diagnostic Readiness & Probing Engine',
        colors: colors,
        type: type,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: colors.accent.withValues(alpha: 0.12),
                shape: BoxShape.circle,
                border: Border.all(color: colors.accent.withValues(alpha: 0.3)),
              ),
              child: Icon(FluentIcons.rocket, size: 32, color: colors.accent),
            ),
            const SizedBox(height: 10),
            Text(
              'Diagnostic Engine Ready',
              style: type.subtitle.copyWith(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 4),
            Text(
              'Active Target: $_selectedPreset',
              style: type.caption.copyWith(
                color: colors.accent,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 14),
            // Diagnostic checks list
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: colors.panelBackgroundAlt,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: colors.borderColor),
              ),
              child: Column(
                children: [
                  _buildCheckRow('ICMP & UDP Native Socket Stack', true, colors, type),
                  const SizedBox(height: 6),
                  _buildCheckRow('Reverse DNS & Host Resolver', true, colors, type),
                  const SizedBox(height: 6),
                  _buildCheckRow('Multi-Flow Parallel Probing Engine', true, colors, type),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.cardBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.accent.withValues(alpha: 0.4)),
        boxShadow: [
          BoxShadow(
            color: colors.accent.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colors.accent.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(FluentIcons.rocket, size: 28, color: colors.accent),
          ),
          const SizedBox(height: 8),
          Text(
            'Ready to Analyze',
            style: type.subtitle.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            'Target: $_selectedPreset',
            style: type.caption.copyWith(
              color: colors.accent,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCheckRow(String label, bool isOk, AppColors colors, AppTypography type) {
    return Row(
      children: [
        Icon(FluentIcons.check_mark, size: 11, color: colors.latencyGood),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: type.caption.copyWith(fontSize: 11, color: colors.textPrimary),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
          decoration: BoxDecoration(
            color: colors.latencyGood.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text('OK', style: type.caption.copyWith(fontSize: 9, fontWeight: FontWeight.bold, color: colors.latencyGood)),
        ),
      ],
    );
  }

  // ==========================================
  // QUICK SETUP PANEL (SLIDE 5)
  // ==========================================
  Widget _buildQuickSetupPanel(
      AppColors colors, AppTypography type, {required bool isCompact}) {
    final presets = [
      {'title': 'Cloudflare DNS', 'ip': '1.1.1.1'},
      {'title': 'Google DNS', 'ip': '8.8.8.8'},
      {'title': 'OpenDNS', 'ip': '208.67.222.222'},
      {'title': 'Quad9 DNS', 'ip': '9.9.9.9'},
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Select Initial Probing Target:',
          style: type.body.copyWith(fontWeight: FontWeight.bold, fontSize: 13),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: presets.map((p) {
            final isSelected = _selectedPreset == p['ip'];
            return GestureDetector(
              onTap: () {
                setState(() {
                  _selectedPreset = p['ip']!;
                  _customTargetController.text = p['ip']!;
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: isSelected
                      ? colors.accent.withValues(alpha: 0.15)
                      : colors.cardBackground,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: isSelected ? colors.accent : colors.borderColor,
                    width: isSelected ? 1.5 : 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isSelected)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: Icon(FluentIcons.check_mark, size: 11, color: colors.accent),
                      ),
                    Text(
                      '${p['title']} (${p['ip']})',
                      style: type.caption.copyWith(
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        color: isSelected ? colors.accent : colors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 12),
        Text(
          'Or Custom Host / IP:',
          style: type.body.copyWith(fontWeight: FontWeight.bold, fontSize: 13),
        ),
        const SizedBox(height: 6),
        TextBox(
          controller: _customTargetController,
          placeholder: 'e.g. google.com or 1.1.1.1',
          onChanged: (val) {
            setState(() {
              _selectedPreset = val.trim();
            });
          },
        ),
        const SizedBox(height: 14),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            Text('App Theme:', style: type.caption.copyWith(fontWeight: FontWeight.bold)),
            _buildThemeOption('System', ThemeMode.system, colors, type),
            _buildThemeOption('Dark', ThemeMode.dark, colors, type),
            _buildThemeOption('Light', ThemeMode.light, colors, type),
          ],
        ),
      ],
    );
  }

  Widget _buildThemeOption(
      String label, ThemeMode mode, AppColors colors, AppTypography type) {
    final isSelected = AppSettings.instance.themeMode == mode;
    return GestureDetector(
      onTap: () {
        AppSettings.instance.setThemeMode(mode);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected
              ? colors.accent.withValues(alpha: 0.15)
              : colors.cardBackground,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isSelected ? colors.accent : colors.borderColor,
          ),
        ),
        child: Text(
          label,
          style: type.caption.copyWith(
            color: isSelected ? colors.accent : colors.textSecondary,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            fontSize: 11,
          ),
        ),
      ),
    );
  }
}

/// Custom painter for rendering rolling latency sparkline in desktop diagrams.
class _MiniWaveformPainter extends CustomPainter {
  final Color color;

  const _MiniWaveformPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          color.withValues(alpha: 0.35),
          color.withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    final path = Path();
    final fillPath = Path();

    final points = [
      Offset(0, size.height * 0.6),
      Offset(size.width * 0.12, size.height * 0.55),
      Offset(size.width * 0.24, size.height * 0.70),
      Offset(size.width * 0.36, size.height * 0.40),
      Offset(size.width * 0.48, size.height * 0.50),
      Offset(size.width * 0.60, size.height * 0.35),
      Offset(size.width * 0.72, size.height * 0.65),
      Offset(size.width * 0.84, size.height * 0.45),
      Offset(size.width, size.height * 0.50),
    ];

    path.moveTo(points[0].dx, points[0].dy);
    fillPath.moveTo(points[0].dx, size.height);
    fillPath.lineTo(points[0].dx, points[0].dy);

    for (int i = 1; i < points.length; i++) {
      path.lineTo(points[i].dx, points[i].dy);
      fillPath.lineTo(points[i].dx, points[i].dy);
    }

    fillPath.lineTo(size.width, size.height);
    fillPath.close();

    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(path, paint);

    // Active pulse dot at tip
    final dotPaint = Paint()..color = color;
    canvas.drawCircle(points.last, 3.5, dotPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Helper function to display the onboarding tour as a modal dialog anytime.
Future<void> showOnboardingDialog(
  BuildContext context, {
  OnboardingCompleteCallback? onComplete,
}) async {
  await showDialog(
    context: context,
    barrierDismissible: true,
    dismissWithEsc: true,
    builder: (dialogContext) {
      return OnboardingScreen(
        isDialogMode: true,
        onComplete: (target, autoStart) {
          Navigator.of(dialogContext).pop();
          if (onComplete != null) {
            onComplete(target, autoStart);
          }
        },
      );
    },
  );
}

/// Custom scroll behavior enabling drag and swipe gestures across touch, mouse, trackpad, and stylus.
class _OnboardingScrollBehavior extends ScrollBehavior {
  const _OnboardingScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
      };

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    return const BouncingScrollPhysics();
  }
}
