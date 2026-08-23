import 'package:flutter/material.dart';

/// Public OSM-derived tile URL configured at build time. Production builds
/// should provide MAP_TILE_URL rather than relying on the development fallback.
const mapTileUrl = String.fromEnvironment(
  'MAP_TILE_URL',
  defaultValue: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
);

const mapAttribution = '© OpenStreetMap contributors';

Widget mapAttributionWidget(BuildContext context) {
  return ColoredBox(
    color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.9),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      child: Text(
        mapAttribution,
        style: Theme.of(context).textTheme.labelSmall,
      ),
    ),
  );
}
