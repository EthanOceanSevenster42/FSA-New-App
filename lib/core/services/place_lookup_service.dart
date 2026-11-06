import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';

/// One suggestion from the address search: what the inspector sees, and the
/// id needed to fetch its full address.
class PlaceSuggestion {
  const PlaceSuggestion({
    required this.placeId,
    required this.primary,
    required this.secondary,
    this.address = '',
    this.distanceKm,
  });

  final String placeId;

  /// The place itself — "Pick n Pay Lynnwood".
  final String primary;

  /// Where it is — "Lynnwood Road, Pretoria".
  final String secondary;

  /// The full address, where the server already has it. OpenStreetMap
  /// answers in one call, so there is usually no second lookup to make.
  final String address;

  /// How far the place is from where the inspector is standing. Shown, so
  /// a match can be judged before it is taken: they are at the facility,
  /// and a kilometre away is somebody else's branch.
  final double? distanceKm;

  String get label => secondary.isEmpty ? primary : '$primary, $secondary';
}

/// Looks up a facility's address by name, the way a ride app does: the
/// inspector types "Pick n Pay Lynnwood" instead of the street address.
///
/// Google answers it, but through the Agency's own server rather than from
/// here. A key shipped inside the APK can be lifted straight back out of
/// it, and whoever lifts it spends the Agency's free allowance; and a key
/// that only lives on the server is rotated by editing one line there,
/// instead of putting a new build on every tablet in the field (Ethan,
/// 2026-10-08). The handset sends nothing but what was typed, under the
/// inspector's own token.
///
/// Every failure answers with nothing rather than throwing — offline, not
/// signed in, server down, allowance spent. The forms keep the plain typed
/// box they have always had, which is what an inspector out of range needs.
class PlaceLookupService {
  PlaceLookupService({
    String? baseUrl,
    Future<String?> Function()? token,
    http.Client? client,
    bool? enabled,
    this.timeout = const Duration(seconds: 8),
  })  : _baseUrl = (baseUrl ?? AppConfig.fromEnvironment().apiBaseUrl)
            .replaceAll(RegExp(r'/+$'), ''),
        _token = token,
        _enabled = enabled ?? _enabledByBuild,
        _client = client ?? http.Client();

  /// Whether this build offers the search at all —
  /// `--dart-define=ADDRESS_SEARCH=true`.
  ///
  /// Off unless a build asks for it. The search answers from OpenStreetMap,
  /// which knows the chains but not every branch, and a facility address
  /// goes onto statutory documents: until the data is good enough for the
  /// Agency to rely on, inspectors keep the typed box they know rather than
  /// a helper that is right some of the time (Ethan, 2026-10-11).
  static const _enabledByBuild = bool.fromEnvironment('ADDRESS_SEARCH');

  final String _baseUrl;
  final Future<String?> Function()? _token;
  final bool _enabled;
  final http.Client _client;
  final Duration timeout;

  /// False when there is nowhere to ask or nobody to ask as. The forms check
  /// before offering the search, so a screen with no session behaves exactly
  /// as it did before the search existed.
  bool get isAvailable => _enabled && _baseUrl.isNotEmpty && _token != null;

  Future<Map<String, String>?> _headers() async {
    final token = await _token?.call();
    if (token == null || token.trim().isEmpty) return null;
    return {'Authorization': 'Bearer $token'};
  }

  /// Suggestions for what has been typed so far.
  ///
  /// [sessionToken] must be the same for every keystroke of one search and
  /// must change once a suggestion is taken — that is what makes the search
  /// bill as one session rather than once per letter. The server holds the
  /// monthly ceiling; when it is reached this simply returns nothing.
  Future<List<PlaceSuggestion>> suggest(
    String query, {
    required String sessionToken,
    double? nearLatitude,
    double? nearLongitude,
  }) async {
    if (!isAvailable || query.trim().length < 3) return const [];
    final headers = await _headers();
    if (headers == null) return const [];
    final uri = Uri.parse('$_baseUrl/api/places/suggest/').replace(
      queryParameters: {
        'q': query.trim(),
        'session': sessionToken,
        if (nearLatitude != null && nearLongitude != null) ...{
          'lat': '$nearLatitude',
          'lng': '$nearLongitude',
        },
      },
    );
    try {
      final response = await _client.get(uri, headers: headers).timeout(timeout);
      if (response.statusCode != 200) return const [];
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) return const [];
      final suggestions = decoded['suggestions'];
      if (suggestions is! List) return const [];
      return [
        for (final entry in suggestions)
          if (entry is Map)
            if (_suggestionOf(entry) case final PlaceSuggestion s) s,
      ];
    } on Object {
      // Offline, signed out, server cross — all the same to the form.
      return const [];
    }
  }

  static PlaceSuggestion? _suggestionOf(Map<dynamic, dynamic> entry) {
    final id = (entry['place_id'] ?? '').toString();
    final primary = (entry['primary'] ?? '').toString();
    // No id where the address came with the suggestion; the name is what
    // makes it a suggestion at all.
    if (primary.isEmpty) return null;
    final km = entry['km'];
    return PlaceSuggestion(
      placeId: id,
      primary: primary,
      secondary: (entry['secondary'] ?? '').toString(),
      address: (entry['address'] ?? '').toString(),
      distanceKm: km is num ? km.toDouble() : null,
    );
  }

  /// The full street address for a taken suggestion.
  ///
  /// Sending the session token with it is what closes the session, and so
  /// what keeps the keystrokes before it from being billed separately.
  /// Returns empty when it cannot be fetched, leaving whatever was typed.
  Future<String> addressOf(String placeId,
      {required String sessionToken}) async {
    if (!isAvailable || placeId.isEmpty) return '';
    final headers = await _headers();
    if (headers == null) return '';
    final uri = Uri.parse('$_baseUrl/api/places/address/').replace(
      queryParameters: {'place_id': placeId, 'session': sessionToken},
    );
    try {
      final response = await _client.get(uri, headers: headers).timeout(timeout);
      if (response.statusCode != 200) return '';
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) return '';
      return (decoded['address'] ?? '').toString();
    } on Object {
      return '';
    }
  }
}
