/// The regulation reference to show beside a requirement, or empty.
///
/// Some requirements reach the handset with a placeholder instead of a
/// reference — `XXXX`, `XXX`, `[Reg. XX]` — where the server's rule was never
/// given its regulation. Printed as it stands, it read on the checklist and in
/// every direction and PDF as if it were the regulation. A placeholder is
/// treated as no reference at all, so the line is left out rather than
/// showing an inspector — or the client the direction is served on — a row of
/// X's.
String cleanRegulation(String raw) =>
    _placeholder.hasMatch(raw) ? '' : raw.trim();

/// Nothing but X's, optionally inside brackets and after "Reg.".
final _placeholder = RegExp(
  r'^\s*[\[(]?\s*(reg(ulation)?\.?\s*)?[x\s.\-]*x[x\s.\-]*[\])]?\s*$',
  caseSensitive: false,
);
