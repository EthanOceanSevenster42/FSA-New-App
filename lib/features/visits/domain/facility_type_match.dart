/// Matches the facility type chosen once at the door to each commodity's own
/// facility-type list.
///
/// Every commodity keeps its own list, and they do not agree on spelling:
/// eggs say "Retailer/Distr. Center", the meat modules "Retailer/Shops/Distr.
/// Centers"; raw meat adds "Butchery", poultry "Abattoir" and "Repacker". The
/// inspector answers the question once on the visit, and each inspection
/// finds its own row for that answer — or, when its list has nothing like it,
/// asks on the form as before.
abstract final class FacilityTypeMatch {
  /// The name every commodity's row for the same kind of premises shares.
  static String key(String name) {
    final lower = name.toLowerCase();
    if (lower.startsWith('retail')) return 'retailer';
    return lower.replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  /// Index in [names] of the row that means [chosen], or null.
  static int? indexOf(String chosen, List<String> names) {
    if (chosen.trim().isEmpty) return null;
    final wanted = key(chosen);
    for (var i = 0; i < names.length; i++) {
      if (key(names[i]) == wanted) return i;
    }
    return null;
  }

  /// The door-side list: every commodity's names, one entry per kind, in
  /// first-seen order — so "Retailer…" appears once whichever way a module
  /// spells it, and "Butchery" appears because raw meat has it.
  static List<String> union(Iterable<Iterable<String>> lists) {
    final seen = <String>{};
    final out = <String>[];
    for (final list in lists) {
      for (final name in list) {
        if (name.trim().isEmpty) continue;
        if (seen.add(key(name))) out.add(name.trim());
      }
    }
    return out;
  }
}
