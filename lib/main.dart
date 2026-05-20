import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

import 'app/app.dart';
import 'core/l10n/app_strings.dart';
import 'data/repositories/app_text_sync_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (kIsWeb) {
    databaseFactory = databaseFactoryFfiWebNoWebWorker;
  }

  try {
    await dotenv.load(fileName: '.env');
  } catch (_) {
    // The app can still run with local defaults when .env is absent.
  }

  await AppTextSyncService.instance.pullRemoteTexts();
  await S.loadFromDatabase();
  await S.seedDefaults();
  await AppTextSyncService.instance.pushLocalTexts();

  // Force portrait orientation
  if (!kIsWeb) {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
  }

  if (!kIsWeb) {
    // Transparent status bar
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ),
    );
  }

  runApp(const PaeGoApp());
}
