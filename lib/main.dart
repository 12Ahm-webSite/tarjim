import 'package:flutter/material.dart';

import 'core/constants/app_constants.dart';
import 'core/theme/app_theme.dart';
import 'core/utils/logger.dart';
import 'screens/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  AppLogger.info(
    'Launching ${AppConstants.appName} v${AppConstants.appVersion}',
  );
  runApp(const TarjimApp());
}

/// Root application widget.
///
/// Material 3, dark manga-inspired theme with a light variant,
/// following the system theme by default.
class TarjimApp extends StatelessWidget {
  const TarjimApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      home: const HomeScreen(),
    );
  }
}
