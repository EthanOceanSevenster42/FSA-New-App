/// Matches the reason for inspection chosen once at the door to each
/// commodity's own reason list.
///
/// The lists do not agree on wording: the meat modules say "Follow Up", eggs
/// says "Follow-up Inspection", and eggs alone offers "Complaint". The
/// inspector answers the question once on the visit, and each inspection
/// finds its own row for that answer — or, when its list has nothing like it,
/// asks on the form as before.
///
/// Deliberately a sibling of `FacilityTypeMatch` rather than a shared helper:
/// the two normalise different vocabularies, and folding them together would
/// mean one list's spelling quirk silently changing how the other matches.
abstract final class InspectionReasonMatch {
  /// The only reasons an inspector is offered: an inspection, or a
  /// follow-up — as the original app offers them (Ethan, 2026-09-24).
  /// Eggs' "Complaint" row is not offered.
  static const offered = ['Inspection', 'Follow Up'];

  /// Whether [name] is one of [offered], however a module spells it.
  static bool isOffered(String name) => offered.any((o) => key(o) == key(name));

  /// The name every commodity's row for the same reason shares.
  static String key(String name) {
    final lower = name.toLowerCase();
    // "Follow Up", "Follow-up Inspection", "Followup" — one reason.
    if (lower.startsWith('follow')) return 'followup';
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

  /// The door-side list: every commodity's reasons, one entry per kind, in
  /// first-seen order — so "Follow Up" appears once however a module spells
  /// it, and "Complaint" appears because eggs has it.
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
