import 'package:fluent_ui/fluent_ui.dart';

enum ScreenClass { mobile, tablet, desktop }

const double kMobileBreakpoint = 600;
const double kTabletBreakpoint = 1000;

ScreenClass screenClassOf(BuildContext context) {
  final width = MediaQuery.of(context).size.width;
  return screenClassForWidth(width);
}

ScreenClass screenClassForWidth(double width) {
  if (width < kMobileBreakpoint) return ScreenClass.mobile;
  if (width < kTabletBreakpoint) return ScreenClass.tablet;
  return ScreenClass.desktop;
}
