/// The shape a facility address has to be written in.
///
/// One box, as it has always been — but written to a fixed order, so the
/// parts can be told apart afterwards.
///
/// The reason is what happens downstream. APS holds the address in pieces,
/// and the bridge splits the handset's one box on its commas to fill them.
/// When inspectors wrote the box freely — sometimes a street and a town,
/// sometimes a town and a postcode, sometimes one run-on line — the split
/// put whatever happened to be in the second position into the Town field,
/// and bare postcodes ended up there. Nothing was lost, but the data could
/// not be searched, grouped or trusted by town.
///
/// So the tail is pinned: an address ends with the province, then the
/// four-digit postal code. What comes before is the street and town, in
/// that order, with a suburb if there is one — a farm or a depot often has
/// no suburb, and demanding one would only invite a filler word.
abstract final class FacilityAddress {
  /// What the inspector is shown above the box.
  static const format = 'Street, Suburb, Town, Province, Postal code';

  /// A filled-in example, which teaches the format faster than the format
  /// does.
  static const example = '12 Mill Road, Epping, Cape Town, Western Cape, 7460';

  /// What the box asks for, under the field.
  ///
  /// A sentence, not a checklist. The order is short enough to read at a
  /// glance, and a scoreboard under the field took up half the form to say
  /// what one line says.
  static const asking =
      'Please include all of these, separated by commas: street, suburb, '
      'town, province, postal code.\ne.g. $example';

  /// The nine provinces, spelled as the Department spells them.
  static const provinces = <String>[
    'Eastern Cape',
    'Free State',
    'Gauteng',
    'KwaZulu-Natal',
    'Limpopo',
    'Mpumalanga',
    'Northern Cape',
    'North West',
    'Western Cape',
  ];

  /// Spellings seen in the field, mapped to the one that is kept.
  ///
  /// An inspector who writes "KZN" or "North-West" has named the province
  /// correctly; refusing it would teach them that the box is fussy rather
  /// than that the order matters.
  static const _aliases = <String, String>{
    'kzn': 'KwaZulu-Natal',
    'kwazulu natal': 'KwaZulu-Natal',
    'kwazulunatal': 'KwaZulu-Natal',
    'natal': 'KwaZulu-Natal',
    'north-west': 'North West',
    'northwest': 'North West',
    'nw': 'North West',
    'ec': 'Eastern Cape',
    'wc': 'Western Cape',
    'nc': 'Northern Cape',
    'fs': 'Free State',
    'gp': 'Gauteng',
    'gt': 'Gauteng',
    'mp': 'Mpumalanga',
    'lp': 'Limpopo',
    'western-cape': 'Western Cape',
    'eastern-cape': 'Eastern Cape',
    'northern-cape': 'Northern Cape',
    'free-state': 'Free State',
  };

  static final _postalCode = RegExp(r'^\d{4}$');
  static final _runsOfSpace = RegExp(r'\s+');

  /// The address split on its commas, blanks dropped and spacing evened.
  static List<String> parts(String raw) => [
        for (final part in raw.split(','))
          if (part.trim().isNotEmpty)
            part.trim().replaceAll(_runsOfSpace, ' '),
      ];

  /// The address written back in the one spelling of itself.
  ///
  /// Only spacing, stray commas and the province's spelling are touched.
  /// A street name is never re-cased: "de Waal Drive" is not a mistake.
  static String tidy(String raw) {
    final cleaned = parts(raw);
    if (cleaned.isEmpty) return '';
    final province = _provinceAt(cleaned, cleaned.length - 2);
    if (province != null) cleaned[cleaned.length - 2] = province;
    return cleaned.join(', ');
  }

  /// The province named in the address, or null when none is.
  static String? provinceOf(String raw) {
    final cleaned = parts(raw);
    return cleaned.length < 2 ? null : _provinceAt(cleaned, cleaned.length - 2);
  }

  /// The postal code at the end, or null when the address does not end in
  /// one.
  static String? postalCodeOf(String raw) {
    final cleaned = parts(raw);
    if (cleaned.isEmpty) return null;
    final last = cleaned.last;
    return _postalCode.hasMatch(last) ? last : null;
  }

  static String? _provinceAt(List<String> cleaned, int index) =>
      index < 0 || index >= cleaned.length
          ? null
          : _namedProvince(cleaned[index]);

  /// The province this text names, however it is spelled, or null.
  static String? _namedProvince(String text) {
    final value = text.trim().toLowerCase().replaceAll(_runsOfSpace, ' ');
    for (final province in provinces) {
      if (province.toLowerCase() == value) return province;
    }
    return _aliases[value];
  }

  /// What is wrong with the address, in the order worth fixing it.
  ///
  /// Empty means it is well formed. An empty box returns nothing: whether
  /// an address is required at all is the form's question, not this one's,
  /// and a blank box must not be scolded for its format before anyone has
  /// typed in it.
  static List<String> problems(String raw) {
    final cleaned = parts(raw);
    if (cleaned.isEmpty) return const [];

    final out = <String>[];
    if (postalCodeOf(raw) == null) {
      out.add('End with the four-digit postal code.');
    }
    if (provinceOf(raw) == null) {
      out.add('Name the province before the postal code.');
    }
    // Street and town, at the least, in front of the province and code.
    if (cleaned.length < 4) {
      out.add('Give the street and the town before the province.');
    }
    return out;
  }

  static bool isWellFormed(String raw) =>
      raw.trim().isNotEmpty && problems(raw).isEmpty;
}
