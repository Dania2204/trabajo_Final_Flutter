import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

import '../datasources/database_helper.dart';

class AppTextSyncService {
  AppTextSyncService._();
  static final instance = AppTextSyncService._();

  String get _supabaseUrl => dotenv.env['SUPABASE_URL']?.trim() ?? '';
  String get _anonKey => dotenv.env['SUPABASE_ANON_KEY']?.trim() ?? '';
  String get _table =>
      (dotenv.env['SUPABASE_APP_TEXTS_TABLE']?.trim().isNotEmpty ?? false)
      ? dotenv.env['SUPABASE_APP_TEXTS_TABLE']!.trim()
      : 'app_texts';

  bool get isConfigured => _supabaseUrl.isNotEmpty && _anonKey.isNotEmpty;

  Map<String, String> get _headers => {
    'apikey': _anonKey,
    'Authorization': 'Bearer $_anonKey',
    'Content-Type': 'application/json',
  };

  Uri _restUri([String query = '']) {
    final base = _supabaseUrl.endsWith('/')
        ? _supabaseUrl.substring(0, _supabaseUrl.length - 1)
        : _supabaseUrl;
    return Uri.parse('$base/rest/v1/$_table$query');
  }

  Future<void> syncAppTexts() async {
    if (!isConfigured) return;

    await pullRemoteTexts();
    await pushLocalTexts();
  }

  Future<void> pullRemoteTexts() async {
    if (!isConfigured) return;

    final response = await http.get(
      _restUri('?select=key,locale,value'),
      headers: _headers,
    );
    if (response.statusCode < 200 || response.statusCode >= 300) return;

    final decoded = jsonDecode(response.body);
    if (decoded is! List) return;

    final rows = decoded
        .whereType<Map<String, dynamic>>()
        .map(
          (row) => {
            'key': row['key']?.toString() ?? '',
            'locale': row['locale']?.toString() ?? '',
            'value': row['value']?.toString() ?? '',
          },
        )
        .where(
          (row) =>
              row['key']!.isNotEmpty &&
              row['locale']!.isNotEmpty &&
              row['value']!.isNotEmpty,
        )
        .toList();

    await DatabaseHelper.instance.upsertAppTextRows(rows, markSynced: true);
  }

  Future<void> pushLocalTexts() async {
    if (!isConfigured) return;

    final rows = await DatabaseHelper.instance.getAppTextRows();
    if (rows.isEmpty) return;

    final response = await http.post(
      _restUri('?on_conflict=key,locale'),
      headers: {
        ..._headers,
        'Prefer': 'resolution=merge-duplicates,return=minimal',
      },
      body: jsonEncode(rows),
    );

    if (response.statusCode >= 200 && response.statusCode < 300) {
      await DatabaseHelper.instance.markAllAppTextsSynced();
    }
  }
}
