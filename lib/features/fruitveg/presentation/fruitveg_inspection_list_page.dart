import 'package:flutter/material.dart';

import '../../../core/widgets/responsive.dart';

import '../../../core/data/local_database.dart';
import '../../../core/theme/app_theme.dart';
import '../data/fruitveg_repository.dart';

/// Saved inspections on this device.
///
/// Fruit & Vegetable inspection management. Upload state is shown
/// explicitly, because on an offline-first device "saved" and "sent" are
/// different things and conflating them loses records.
class FruitVegInspectionListPage extends StatefulWidget {
  const FruitVegInspectionListPage({super.key, required this.repository});

  final FruitVegRepository repository;

  @override
  State<FruitVegInspectionListPage> createState() =>
      _FruitVegInspectionListPageState();
}

class _FruitVegInspectionListPageState
    extends State<FruitVegInspectionListPage> {
  late Future<List<FvInspection>> _items;
  Map<int, String> _commodityNames = {};

  @override
  void initState() {
    super.initState();
    _items = _load();
  }

  Future<List<FvInspection>> _load() async {
    final commodities = await widget.repository.commodities();
    _commodityNames = {for (final c in commodities) c.id: c.name};
    return widget.repository.savedInspections();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text(
          'Inspection Management',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.ink,
        elevation: 0,
        shape: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      body: ContentWidth(
          child: FutureBuilder<List<FvInspection>>(
        future: _items,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final items = snap.data ?? const <FvInspection>[];
          if (items.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  'No inspections captured on this device yet.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.muted, height: 1.4),
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final item = items[i];
              return Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.border),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _commodityNames[item.commodityId] ??
                                'Commodity ${item.commodityId}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 15.5,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: item.isUploaded
                                ? const Color(0xFFEAF5EB)
                                : AppColors.noticeBackground,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            item.isUploaded ? 'Uploaded' : 'On device',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w900,
                              color: item.isUploaded
                                  ? const Color(0xFF2E7D32)
                                  : AppColors.noticeForeground,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${item.inspectedAt.toLocal()}'.split('.').first,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: AppColors.muted,
                      ),
                    ),
                    if (item.clientName.isNotEmpty)
                      Text(
                        item.clientName,
                        style: const TextStyle(fontSize: 13),
                      ),
                    if (item.gradeOverridden)
                      const Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: Text(
                          'Class overridden by inspector',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppColors.brandPrimary,
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          );
        },
      )),
    );
  }
}
