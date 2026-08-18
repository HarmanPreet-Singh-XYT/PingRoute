import 'package:fluent_ui/fluent_ui.dart';

enum ScreenClass { mobile, tablet, desktop }

const double kMobileBreakpoint = 600;
const double kTabletBreakpoint = 1000;
const double kShortLandscapeHeightBreakpoint = 550;

ScreenClass screenClassOf(BuildContext context) {
  final size = MediaQuery.of(context).size;
  return screenClassForSize(size);
}

ScreenClass screenClassForSize(Size size) {
  // If the screen height is very short (e.g. phone in landscape), classify as mobile
  if (size.height < kShortLandscapeHeightBreakpoint && size.width < kTabletBreakpoint) {
    return ScreenClass.mobile;
  }
  return screenClassForWidth(size.width);
}

ScreenClass screenClassForWidth(double width) {
  if (width < kMobileBreakpoint) return ScreenClass.mobile;
  if (width < kTabletBreakpoint) return ScreenClass.tablet;
  return ScreenClass.desktop;
}
