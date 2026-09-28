/// Reading what the office published, apart from any of the machinery that
/// fetches or installs it — so the one rule that decides whether a handset
/// is out of date can be exercised on its own.
abstract final class PublishedBuild {
  /// The build number out of a published version such as "1.0.1+2107".
  ///
  /// Null when the version is not written that way. Anything unrecognised
  /// is treated as "no update" rather than guessed at: offering the wrong
  /// build to a handset in the field is worse than offering none.
  static int? numberOf(String version) {
    final plus = version.lastIndexOf('+');
    if (plus < 0 || plus == version.length - 1) return null;
    return int.tryParse(version.substring(plus + 1).trim());
  }

  /// Whether [published] is newer than what is [running].
  ///
  /// Equal is not newer: a handset already on the build must not be asked
  /// to install it again every time someone signs in.
  static bool isNewer({required String published, required String running}) {
    final there = numberOf(published);
    final here = int.tryParse(running.trim());
    if (there == null || here == null) return false;
    return there > here;
  }
}
