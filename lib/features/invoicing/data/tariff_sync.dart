import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/data/local_database.dart';
import '../domain/invoice_rules.dart';

/// Brings the RFI tariff down from the server and keeps a copy on the
/// device, so a tablet with no signal still bills with the last figures it
/// was given (Ethan, 2026-09-29).
class TariffSync {
  TariffSync({required this.database, this.baseUrl = '', http.Client? client})
      : _client = client ?? http.Client();

  final LocalDatabase database;
  final String baseUrl;
  final http.Client _client;

  static const stateKey = 'invoice.tariff';

  /// Puts the copy kept on the device in force. Called as the app starts.
  Future<void> load() async {
    final raw = await database.readSyncState(stateKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final json = jsonDecode(raw);
      if (json is Map) {
        InvoiceRates.use(InvoiceTariff.fromJson(json.cast<String, Object?>()));
      }
    } on FormatException {
      // A copy that cannot be read leaves the tariff in force as it was.
    }
  }

  /// Fetches the server's tariff, keeps it, and puts it in force. Returns
  /// true when the figures changed.
  Future<bool> pull({required String token}) async {
    if (baseUrl.isEmpty) return false;
    final response = await _client.get(
      Uri.parse('$baseUrl/api/visits/tariff/'),
      headers: {
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
      },
    ).timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) return false;
    final json = jsonDecode(response.body);
    if (json is! Map) return false;
    final tariff = InvoiceTariff.fromJson(json.cast<String, Object?>());
    final changed = tariff != InvoiceRates.current;
    await database.writeSyncState(stateKey, jsonEncode(tariff.toJson()));
    InvoiceRates.use(tariff);
    return changed;
  }
}
