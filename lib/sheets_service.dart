import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:gsheets/gsheets.dart';
import 'package:intl/intl.dart';

class SheetsService {
  static const _spreadsheetId = '1quYcrXTgzwKgrQJzbAsdPYMCG6Gi3nvd-Zq4YqKhS2g';
  static late GSheets _gsheets;
  static Worksheet? _sheet;

  static Future<void> init() async {
    // Load service account credentials from assets
    final jsonString = await rootBundle.loadString('assets/credentials.json');
    final credentials = jsonDecode(jsonString);

    _gsheets = GSheets(credentials);
    final ss = await _gsheets.spreadsheet(_spreadsheetId);
    _sheet = ss.worksheetByTitle('Sheet1');

    if (_sheet == null) {
      _sheet = await ss.addWorksheet('Sheet1');
      await _sheet!.values.insertRow(1, ['Name', 'Date', 'Time']);
    }
  }

  static Future<void> insertAttendance(String name) async {
    if (_sheet == null) return;

    final now = DateTime.now();
    final date = DateFormat('yyyy-MM-dd').format(now);
    final time = DateFormat('HH:mm:ss').format(now);

    await _sheet!.values.appendRow([name, date, time]);
  }
}
