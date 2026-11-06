import 'package:uuid/uuid.dart';

/// The grading record graded underneath the labelling of the label checklist
/// [labelUuid] (Ethan, 2026-09-29). Worked out from the checklist's own id,
/// so the two find each other without a column to link them.
String gradingUuidForLabel(String labelUuid) => const Uuid()
    .v5(Namespace.url.value, 'fsa-poultry-label-grading/$labelUuid');
