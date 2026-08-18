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
    id: 2,
    title: 'Eggs',
    subtitle: 'Sizing, Haugh readings and grading',
    icon: Icons.egg_outlined,
    group: FeatureGroup.inspections,
    available: true,
  ),
  AppFeature(
    id: 3,
    title: 'Poultry Products',
    subtitle: 'Grading and classification',
    icon: Icons.food_bank_outlined,
    group: FeatureGroup.inspections,
    available: true,
  ),
  AppFeature(
    id: 4,
    title: 'Processed Meat',
    subtitle: 'PMP inspections and directives',
    icon: Icons.lunch_dining_outlined,
    group: FeatureGroup.inspections,
    available: false,
  ),
  AppFeature(
    id: 5,
    title: 'Raw Processed Meat',
    subtitle: 'Certain raw processed meat products',
    icon: Icons.kebab_dining_outlined,
    group: FeatureGroup.inspections,
    available: false,
  ),
  AppFeature(
    id: 6,
    title: 'SAPA',
    subtitle: 'RMLA levy return forms',
    icon: Icons.receipt_long_outlined,
    group: FeatureGroup.inspections,
    available: false,
  ),
  AppFeature(
    id: 7,
    title: 'Product Scanning',
    subtitle: 'Scan and look up products',
    icon: Icons.qr_code_scanner,
    group: FeatureGroup.tools,
    available: false,
  ),
  AppFeature(
    id: 8,
    title: 'Server Sync',
    subtitle: 'Upload inspections, pull reference data',
    icon: Icons.sync,
    group: FeatureGroup.tools,
    available: false,
  ),
  AppFeature(
    id: 9,
    title: 'Information',
    subtitle: 'Application and device details',
    icon: Icons.info_outline,
    group: FeatureGroup.tools,
    // No screen behind this yet. Marked unavailable so the menu does not
    // promise something that only answers "not built yet".
    available: false,
  ),
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
