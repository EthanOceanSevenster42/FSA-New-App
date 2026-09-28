import 'package:flutter/material.dart';

/// Layout rules for screens wider than the handsets the app was drawn for.
///
/// The forms were laid out against a 360dp phone. A tablet is more than twice
/// that, and a column of fields simply stretched across it reads badly: lines
/// run too long and tiles sized by aspect ratio balloon. These two helpers are
/// the whole treatment — cap the content and centre it, and size grid tiles by
/// height rather than by ratio so they flow into more columns instead of
/// growing.
abstract final class AppLayout {
  /// Narrowest the content column gets on a screen wider than a handset.
  ///
  /// Wide enough that nothing on a handset is affected — no phone is this
  /// wide — and narrow enough that a form still reads as a form.
  static const double minContentWidth = 620;

  /// Widest it is allowed to get, however big the screen.
  static const double maxContentWidth = 880;

  /// How wide the content column should be on this screen.
  ///
  /// A handset gets the whole width, exactly as before. Anything wider gets
  /// four fifths of the screen, held between the two bounds — so a portrait
  /// tablet keeps a comfortable margin and a landscape one does not end up
  /// as a narrow strip marooned in white space.
  static double contentWidthFor(double screenWidth) {
    if (screenWidth <= minContentWidth) return screenWidth;
    final share = screenWidth * 0.8;
    if (share < minContentWidth) return minContentWidth;
    return share > maxContentWidth ? maxContentWidth : share;
  }

  /// Widest a grid tile may be before another column is added.
  ///
  /// Matches roughly what a two-column grid gives on a large handset, so the
  /// tiles keep the size they were drawn at and the tablet simply fits more
  /// of them across.
  static const double tileWidth = 210;
}

/// Centres [child] and stops it stretching the full width of a tablet.
///
/// A no-op on a handset, which is narrower than the smallest cap.
class ContentWidth extends StatelessWidget {
  const ContentWidth({super.key, required this.child, this.maxWidth});

  final Widget child;

  /// Overrides the width this screen would otherwise be given.
  final double? maxWidth;

  @override
  Widget build(BuildContext context) {
    // sizeOf rather than of(context): a keyboard opening changes viewInsets,
    // and there is no reason to rebuild every page when it does.
    final width =
        maxWidth ?? AppLayout.contentWidthFor(MediaQuery.sizeOf(context).width);
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: width),
        child: child,
      ),
    );
  }
}

/// A grid whose tiles keep a fixed height and flow into as many columns as
/// the screen has room for.
///
/// [rowHeight] is the height the tile was drawn at on a handset; it does not
/// change with the screen, which is the point — an aspect ratio would make
/// every tile taller on a tablet as well as wider.
///
/// The column count is also balanced: four tiles across three columns leaves
/// one stranded on a row of its own, so they are laid out two and two.
class AppTileGrid extends StatelessWidget {
  const AppTileGrid({
    super.key,
    required this.rowHeight,
    required this.children,
    this.spacing = 12,
    this.tileWidth,
  });

  final double rowHeight;
  final List<Widget> children;
  final double spacing;
  final double? tileWidth;

  /// Widest a tile may be stretched past the width it was drawn at before
  /// another column is used instead. Two tiles spread across a landscape
  /// tablet are slabs, not tiles.
  static const double _stretch = 1.5;

  /// How many columns to use: as many as fit, without stretching a tile far
  /// past its drawn width, and evened out so the last row is not a single
  /// tile trailing behind a full one.
  static int columnsFor({
    required double width,
    required int count,
    required double tileWidth,
    required double spacing,
  }) {
    if (count == 0) return 1;
    // Same arithmetic as SliverGridDelegateWithMaxCrossAxisExtent.
    var fits = (width / (tileWidth + spacing)).ceil();
    if (fits < 1) fits = 1;

    double widthAt(int columns) => (width - (columns - 1) * spacing) / columns;

    var columns = count < fits ? count : fits;
    // Fewer tiles than columns: leave the spare slots empty rather than
    // blowing each tile up to fill the row.
    while (columns < fits && widthAt(columns) > tileWidth * _stretch) {
      columns++;
    }
    while (columns > 2 && count % columns == 1) {
      columns--;
    }
    return columns;
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) => GridView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columnsFor(
              width: constraints.maxWidth,
              count: children.length,
              tileWidth: tileWidth ?? AppLayout.tileWidth,
              spacing: spacing,
            ),
            mainAxisExtent: rowHeight,
            mainAxisSpacing: spacing,
            crossAxisSpacing: spacing,
          ),
          children: children,
        ),
      );
}
