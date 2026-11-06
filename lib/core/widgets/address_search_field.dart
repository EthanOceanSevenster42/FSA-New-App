import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../services/place_lookup_service.dart';
import '../theme/app_theme.dart';

/// A facility address that can be searched for by name.
///
/// The inspector types "Pick n Pay Lynnwood" rather than the street address
/// and takes the match; the box is filled in and stays editable, because a
/// near-enough match must never go onto a statutory document unchecked
/// (Ethan, 2026-10-08).
///
/// It is a helper laid over an ordinary field, never a replacement: with no
/// signal, no key, or nothing found, it is exactly the typed box it was
/// before. Inspectors work out of range for most of a day.
class AddressSearchField extends StatefulWidget {
  const AddressSearchField({
    super.key,
    required this.controller,
    required this.child,
    this.service,
    this.tokenProvider,
    this.nearLatitude,
    this.nearLongitude,
    this.enabled = true,
  });

  /// The address box itself — whatever the form already draws, so the field
  /// keeps its own label, validation and look.
  final Widget child;

  final TextEditingController controller;

  /// Replaced in tests; built against the Agency's server otherwise.
  final PlaceLookupService? service;

  /// The signed-in inspector's token. The search runs on the Agency's
  /// server, under the inspector's own session, so that the Google key
  /// never has to ship on the tablet (Ethan, 2026-10-08). Without one the
  /// field is the plain typed box it has always been.
  final Future<String?> Function()? tokenProvider;

  /// Where the inspector is, so the facility in front of them ranks first.
  final double? nearLatitude;
  final double? nearLongitude;

  final bool enabled;

  @override
  State<AddressSearchField> createState() => _AddressSearchFieldState();
}

class _AddressSearchFieldState extends State<AddressSearchField> {
  late final PlaceLookupService _service =
      widget.service ?? PlaceLookupService(token: widget.tokenProvider);
  Timer? _debounce;
  double? _lat;
  double? _lon;
  List<PlaceSuggestion> _suggestions = const [];
  bool _searching = false;
  bool _dismissed = false;
  String _session = _newSession();
  String _lastQuery = '';

  static String _newSession() {
    final rnd = Random();
    return List.generate(16, (_) => rnd.nextInt(16).toRadixString(16)).join();
  }

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTyped);
    // Warm the position now. Waiting for a fix on the first search is what
    // made the first search feel broken: the inspector typed, nothing
    // happened for several seconds, and they typed more (Ethan,
    // 2026-10-09).
    _locate();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    widget.controller.removeListener(_onTyped);
    super.dispose();
  }

  /// Searches on a pause in typing, not on every letter: it keeps the search
  /// inside one billed session and spares the inspector's data.
  void _onTyped() {
    if (!widget.enabled || !_service.isAvailable) return;
    final query = widget.controller.text.trim();
    if (query == _lastQuery) return;
    _lastQuery = query;
    _dismissed = false;
    _debounce?.cancel();
    if (query.length < 3) {
      if (_suggestions.isNotEmpty) setState(() => _suggestions = const []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () => _search(query));
  }

  /// Where the inspector is standing, which is what makes a suggestion
  /// trustworthy: they are AT the facility, so a match a province away is
  /// another branch of the same chain and must never be offered. Asked for
  /// once per field and kept; a refusal or no fix simply means no
  /// suggestions, which is the plain typed box (Ethan, 2026-10-09).
  Future<void> _locate() async {
    if (widget.nearLatitude != null && widget.nearLongitude != null) {
      _lat = widget.nearLatitude;
      _lon = widget.nearLongitude;
      return;
    }
    if (_lat != null && _lon != null) return;
    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }
      // The fix the handset already has, which comes back at once. An
      // inspector standing at a facility has not moved since it was taken,
      // and 10 km of slack covers the rest.
      final known = await Geolocator.getLastKnownPosition();
      if (known != null) {
        _lat = known.latitude;
        _lon = known.longitude;
        return;
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          // Medium is plenty to tell this shop from one in the next town,
          // and it fixes faster than high indoors, which is where the
          // inspector is standing.
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 8),
        ),
      );
      _lat = position.latitude;
      _lon = position.longitude;
    } on Object {
      // No fix. The search offers nothing and the field stays as typed.
    }
  }

  Future<void> _search(String query) async {
    setState(() => _searching = true);
    await _locate();
    final found = await _service.suggest(
      query,
      sessionToken: _session,
      nearLatitude: _lat,
      nearLongitude: _lon,
    );
    if (!mounted) return;
    // Answers can overtake each other on a slow link. Anything that is no
    // longer what the inspector is looking for is dropped, or the list
    // flickers back to an older search.
    if (query != _lastQuery) return;
    setState(() {
      _searching = false;
      _suggestions = found;
    });
  }

  Future<void> _take(PlaceSuggestion suggestion) async {
    setState(() {
      _suggestions = const [];
      _searching = true;
    });
    final address = suggestion.address.isNotEmpty
        ? suggestion.address
        : await _service.addressOf(suggestion.placeId,
            sessionToken: _session);
    if (!mounted) return;
    // A new session: this search is closed and paid for.
    _session = _newSession();
    final filled = address.isNotEmpty ? address : suggestion.label;
    _lastQuery = filled;
    widget.controller.text = filled;
    widget.controller.selection =
        TextSelection.collapsed(offset: filled.length);
    setState(() => _searching = false);
  }

  @override
  Widget build(BuildContext context) {
    final showing = !_dismissed && (_suggestions.isNotEmpty || _searching);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        widget.child,
        if (showing)
          // A Material, not a coloured Container: a ListTile paints its
          // ripple on the nearest Material, so a plain box swallowed the
          // tap feedback and a press looked like nothing happened.
          Container(
            margin: const EdgeInsets.only(top: 4, bottom: 10),
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.muted.withValues(alpha: 0.4)),
              borderRadius: BorderRadius.circular(10),
            ),
            clipBehavior: Clip.antiAlias,
            child: Material(
              color: Theme.of(context).colorScheme.surface,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_searching)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 14),
                      child: SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  for (final s in _suggestions)
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.place_outlined, size: 20),
                      title: Text(s.primary,
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: s.secondary.isEmpty ? null : Text(s.secondary),
                      trailing: s.distanceKm == null
                          ? null
                          : Text('${s.distanceKm!.toStringAsFixed(1)} km',
                              style: const TextStyle(fontSize: 12)),
                      onTap: () => _take(s),
                    ),
                  if (_suggestions.isNotEmpty)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () => setState(() => _dismissed = true),
                        child: const Text('Type it myself'),
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
