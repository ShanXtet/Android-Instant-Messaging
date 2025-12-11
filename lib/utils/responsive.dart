// lib/utils/responsive.dart
import 'package:flutter/material.dart';

class Responsive {
  static double screenWidth(BuildContext context) => MediaQuery.of(context).size.width;
  static double screenHeight(BuildContext context) => MediaQuery.of(context).size.height;
  
  static bool isMobile(BuildContext context) => screenWidth(context) < 600;
  static bool isTablet(BuildContext context) => screenWidth(context) >= 600 && screenWidth(context) < 1200;
  static bool isDesktop(BuildContext context) => screenWidth(context) >= 1200;
  
  static double getResponsiveValue(BuildContext context, {
    required double mobile,
    double? tablet,
    double? desktop,
  }) {
    if (isDesktop(context)) return desktop ?? tablet ?? mobile;
    if (isTablet(context)) return tablet ?? mobile;
    return mobile;
  }
  
  static int getColumnsCount(BuildContext context) {
    if (isDesktop(context)) return 3;
    if (isTablet(context)) return 2;
    return 1;
  }
  
  static EdgeInsets getPadding(BuildContext context) {
    if (isDesktop(context)) return const EdgeInsets.all(24);
    if (isTablet(context)) return const EdgeInsets.all(16);
    return const EdgeInsets.all(12);
  }
  
  static double getMessageMaxWidth(BuildContext context) {
    if (isDesktop(context)) return 600;
    if (isTablet(context)) return 500;
    return double.infinity;
  }
  
  static double getChatListWidth(BuildContext context) {
    if (isDesktop(context)) return 400;
    if (isTablet(context)) return 350;
    return double.infinity;
  }
}


