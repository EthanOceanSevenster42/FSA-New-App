import 'package:flutter/material.dart';

/// A destination on the home screen.
///
/// The full set of commodity modules, so nothing an inspector needs is
/// missing. Previously the
/// list was assembled inline in `MasterDetailView.PopulateMasterMenuItems()`
/// and filtered by a 32-bit industry bitmask read from device preferences;
/// here the catalogue is data and the filtering is a plain predicate.
enum FeatureGroup { inspections, tools }

class AppFeature {
  const AppFeature({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.group,
    this.requiresAdmin = false,
    this.available = true,
  });

  /// Stable numeric ids so records and routes can be
  /// cross-checked during the rebuild.
  final int id;
  final String title;
  final String subtitle;
  final IconData icon;
  final FeatureGroup group;
  final bool requiresAdmin;

  /// False while a commodity's screens are still being built. Shown but
  /// visibly disabled, rather than silently missing — an inspector should be
  /// able to see that a feature exists and is not yet available.
  final bool available;
}

/// The full catalogue, in the order the drawer presents it.
const kAppFeatures = <AppFeature>[
  // Fruit & Vegetables is intentionally absent while Eggs is the focus.
  // Its screens, repository and backend remain in the tree — re-add an entry
  // with id 1 to bring it back; main.dart still routes that id.
  AppFeature(
    id: 11,
    title: 'Inspection',
    subtitle: 'Plan the store\'s inspections, capture each, sign once',
    icon: Icons.storefront_outlined,
    group: FeatureGroup.inspections,
    available: true,
  ),
  AppFeature(
    id: 12,
    title: 'Inspection Management',
    subtitle: 'Every inspection captured — grouped by facility',
    icon: Icons.fact_check_outlined,
    group: FeatureGroup.inspections,
    available: true,
  ),
  // The standalone commodity entries (Eggs id 2, Poultry Products id 3,
  // Processed Meat id 4, Raw Processed Meat id 5) are parked while all
  // capturing goes through the grouped Inspection flow above — re-add an
  // entry with its id to bring one back; main.dart still routes every id.
  // Note: Processed Meat (PMP) is not yet part of the Inspection plan, so
  // it is unreachable until it is wired in or its tile returns.
  // SAPA (id 6) and Product Scanning (id 7) are removed until their screens
  // exist — re-add entries with those ids to bring them back.
  AppFeature(
    id: 8,
    title: 'Server Sync',
    subtitle: 'Upload inspections, pull reference data',
    icon: Icons.sync,
    group: FeatureGroup.tools,
    available: true,
  ),
  // Information (id 9) is likewise removed until a screen exists behind it.
  AppFeature(
    id: 10,
    title: 'Admin Tools',
    subtitle: 'Organisation and device administration',
    icon: Icons.admin_panel_settings_outlined,
    group: FeatureGroup.tools,
    requiresAdmin: true,
    available: false,
  ),
];
