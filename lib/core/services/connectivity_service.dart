import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

/// Streams connectivity changes for the "No Internet Connectivity" banner.
///
/// Replaces `App.StartCheckIfInternet(lbl_NoInternet, this)`, which mutated a
/// Label from a background timer. Here the page just listens to a stream.
class ConnectivityService {
  ConnectivityService([Connectivity? connectivity])
      : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;

  static bool _isOnline(List<ConnectivityResult> results) =>
      results.any((r) => r != ConnectivityResult.none);

  Future<bool> get isOnline async =>
      _isOnline(await _connectivity.checkConnectivity());

  /// Emits `true` when the device has a network route, `false` otherwise.
  ///
  /// A route is not the same as reachability — the API may still be
  /// unreachable. Server reachability is handled separately at sync time.
  Stream<bool> get onStatusChanged =>
      _connectivity.onConnectivityChanged.map(_isOnline);
}
