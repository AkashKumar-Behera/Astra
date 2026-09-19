import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;

/// Service for offline & high-speed local disk caching of map tiles.
/// Eliminates repeated tile loading and enables instant 60fps rendering for 20-50 km areas.
class MapCacheService {
  static Directory? _cacheDir;
  static bool _isPrecaching = false;

  /// Returns the local cache directory for storing map tiles.
  static Future<Directory> getCacheDirectory() async {
    if (_cacheDir != null && await _cacheDir!.exists()) {
      return _cacheDir!;
    }

    // Try standard Android internal app storage paths first
    final candidatePaths = [
      '/data/user/0/com.croto.astra/files/map_tiles',
      '/data/data/com.croto.astra/files/map_tiles',
      '${Directory.systemTemp.path}/astra_map_tiles',
    ];

    Directory? selected;
    for (final path in candidatePaths) {
      try {
        final d = Directory(path);
        if (!await d.exists()) {
          await d.create(recursive: true);
        }
        // Test write
        final testFile = File('${d.path}/.test_probe');
        await testFile.writeAsString('ok');
        await testFile.delete();
        selected = d;
        break;
      } catch (_) {}
    }

    _cacheDir = selected ?? Directory('${Directory.systemTemp.path}/astra_map_tiles');
    if (!await _cacheDir!.exists()) {
      await _cacheDir!.create(recursive: true);
    }
    return _cacheDir!;
  }

  /// Generates a unique, deterministic local file for a given tile.
  static Future<File> getTileFile({
    required String styleKey,
    required int z,
    required int x,
    required int y,
    bool isRetina = false,
  }) async {
    final dir = await getCacheDirectory();
    final suffix = isRetina ? '@2x' : '';
    final fileName = '${styleKey}_z${z}_x${x}_y$y$suffix.tile';
    return File('${dir.path}/$fileName');
  }

  /// Calculates total cache size in bytes.
  static Future<int> getCacheSizeBytes() async {
    try {
      final dir = await getCacheDirectory();
      int total = 0;
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is File) {
          total += await entity.length();
        }
      }
      return total;
    } catch (_) {
      return 0;
    }
  }

  /// Clears all locally cached tiles.
  static Future<void> clearCache() async {
    try {
      final dir = await getCacheDirectory();
      if (await dir.exists()) {
        await for (final entity in dir.list(followLinks: false)) {
          if (entity is File) {
            await entity.delete();
          }
        }
      }
    } catch (_) {}
  }

  /// Pre-caches a geographic radius (e.g. 20-50 km) around a location
  /// so that tiles are available offline and load with zero lag.
  static Future<void> precacheArea({
    required double latitude,
    required double longitude,
    double radiusKm = 30.0,
    required String urlTemplate,
    required String styleKey,
    List<int> zoomLevels = const [13, 14, 15],
    void Function(int completed, int total)? onProgress,
  }) async {
    if (_isPrecaching) return;
    _isPrecaching = true;

    try {
      final tilesToDownload = <_TileTask>[];

      for (final zoom in zoomLevels) {
        final box = _getBoundingBoxTiles(
          latitude: latitude,
          longitude: longitude,
          radiusKm: radiusKm,
          zoom: zoom,
        );

        for (int x = box.minX; x <= box.maxX; x++) {
          for (int y = box.minY; y <= box.maxY; y++) {
            final file = await getTileFile(
              styleKey: styleKey,
              z: zoom,
              x: x,
              y: y,
              isRetina: urlTemplate.contains('{r}'),
            );

            if (!await file.exists()) {
              // Construct actual URL for this tile
              final url = _formatTileUrl(urlTemplate, zoom, x, y);
              tilesToDownload.add(_TileTask(url: url, file: file));
            }
          }
        }
      }

      final total = tilesToDownload.length;
      if (total == 0) {
        onProgress?.call(0, 0);
        _isPrecaching = false;
        return;
      }

      int completed = 0;
      final client = http.Client();

      // Bounded concurrency pool (6 simultaneous downloads)
      const concurrency = 6;
      final chunks = <List<_TileTask>>[];
      for (int i = 0; i < tilesToDownload.length; i += concurrency) {
        chunks.add(tilesToDownload.sublist(
          i,
          i + concurrency > tilesToDownload.length ? tilesToDownload.length : i + concurrency,
        ));
      }

      for (final chunk in chunks) {
        await Future.wait(
          chunk.map((task) async {
            try {
              final res = await client
                  .get(Uri.parse(task.url))
                  .timeout(const Duration(seconds: 8));

              if (res.statusCode == 200 && res.bodyBytes.isNotEmpty) {
                final temp = File('${task.file.path}.tmp');
                await temp.writeAsBytes(res.bodyBytes, flush: true);
                await temp.rename(task.file.path);
              }
            } catch (_) {} finally {
              completed++;
              onProgress?.call(completed, total);
            }
          }),
        );
      }

      client.close();
    } catch (_) {
    } finally {
      _isPrecaching = false;
    }
  }

  static String _formatTileUrl(String template, int z, int x, int y) {
    final sub = template.contains('google.com') ? '1' : 'a';
    return template
        .replaceAll('{z}', z.toString())
        .replaceAll('{x}', x.toString())
        .replaceAll('{y}', y.toString())
        .replaceAll('{r}', '@2x')
        .replaceAll('{s}', sub);
  }

  static _TileBoundingBox _getBoundingBoxTiles({
    required double latitude,
    required double longitude,
    required double radiusKm,
    required int zoom,
  }) {
    // 1 deg latitude ≈ 111.0 km
    final deltaLat = radiusKm / 111.0;
    // 1 deg longitude ≈ 111.0 * cos(lat) km
    final cosLat = math.cos(latitude * math.pi / 180.0);
    final deltaLng = radiusKm / (111.0 * (cosLat.abs() < 0.01 ? 0.01 : cosLat));

    final minLat = latitude - deltaLat;
    final maxLat = latitude + deltaLat;
    final minLng = longitude - deltaLng;
    final maxLng = longitude + deltaLng;

    final n = 1 << zoom;
    int latToTileY(double lat) {
      final rad = lat * math.pi / 180.0;
      final val = (1.0 - (math.log(math.tan(rad) + (1.0 / math.cos(rad))) / math.pi)) / 2.0 * n;
      return val.floor().clamp(0, n - 1);
    }

    int lngToTileX(double lng) {
      final val = ((lng + 180.0) / 360.0) * n;
      return val.floor().clamp(0, n - 1);
    }

    final minX = lngToTileX(minLng);
    final maxX = lngToTileX(maxLng);
    final minY = latToTileY(maxLat); // North latitude has lower Y in Mercator
    final maxY = latToTileY(minLat);

    return _TileBoundingBox(
      minX: math.min(minX, maxX),
      maxX: math.max(minX, maxX),
      minY: math.min(minY, maxY),
      maxY: math.max(minY, maxY),
    );
  }
}

class _TileTask {
  final String url;
  final File file;
  _TileTask({required this.url, required this.file});
}

class _TileBoundingBox {
  final int minX;
  final int maxX;
  final int minY;
  final int maxY;

  _TileBoundingBox({
    required this.minX,
    required this.maxX,
    required this.minY,
    required this.maxY,
  });
}

/// Custom FlutterMap [TileProvider] that saves downloaded tiles directly to disk
/// and loads from local storage first for instant offline/cached rendering.
class CachedTileProvider extends TileProvider {
  final String styleKey;
  final http.Client _client = http.Client();

  CachedTileProvider({
    required this.styleKey,
    super.headers,
  });

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    final url = getTileUrl(coordinates, options);
    return CachedTileImageProvider(
      url: url,
      styleKey: styleKey,
      coordinates: coordinates,
      isRetina: options.resolvedRetinaMode == RetinaMode.server,
      client: _client,
      headers: headers,
    );
  }

  @override
  void dispose() {
    _client.close();
    super.dispose();
  }
}

/// Custom [ImageProvider] that loads tiles from disk cache if present,
/// otherwise fetches from network, saves to disk, and decodes.
class CachedTileImageProvider extends ImageProvider<CachedTileImageProvider> {
  final String url;
  final String styleKey;
  final TileCoordinates coordinates;
  final bool isRetina;
  final http.Client client;
  final Map<String, String>? headers;

  CachedTileImageProvider({
    required this.url,
    required this.styleKey,
    required this.coordinates,
    required this.isRetina,
    required this.client,
    this.headers,
  });

  @override
  Future<CachedTileImageProvider> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture<CachedTileImageProvider>(this);
  }

  @override
  ImageStreamCompleter loadImage(
    CachedTileImageProvider key,
    ImageDecoderCallback decode,
  ) {
    return MultiFrameImageStreamCompleter(
      codec: _loadAsync(decode),
      scale: 1.0,
      informationCollector: () => [
        DiagnosticsProperty<ImageProvider>('Image provider', this),
        DiagnosticsProperty<CachedTileImageProvider>('Image key', key),
      ],
    );
  }

  Future<ui.Codec> _loadAsync(ImageDecoderCallback decode) async {
    try {
      final file = await MapCacheService.getTileFile(
        styleKey: styleKey,
        z: coordinates.z,
        x: coordinates.x,
        y: coordinates.y,
        isRetina: isRetina,
      );

      // 1. FAST PATH: Load from local disk cache
      if (await file.exists()) {
        final bytes = await file.readAsBytes();
        if (bytes.isNotEmpty) {
          final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
          return decode(buffer);
        }
      }

      // 2. NETWORK PATH: Download and cache to disk
      final res = await client
          .get(Uri.parse(url), headers: headers)
          .timeout(const Duration(seconds: 12));

      if (res.statusCode == 200 && res.bodyBytes.isNotEmpty) {
        // Save asynchronously in background
        _persistToDisk(file, res.bodyBytes);
        final buffer = await ui.ImmutableBuffer.fromUint8List(res.bodyBytes);
        return decode(buffer);
      }
    } catch (_) {}

    // Fallback transparent 1x1 image on error
    final buffer = await ui.ImmutableBuffer.fromUint8List(TileProvider.transparentImage);
    return decode(buffer);
  }

  static void _persistToDisk(File file, Uint8List bytes) async {
    try {
      final temp = File('${file.path}.tmp_${DateTime.now().microsecondsSinceEpoch}');
      await temp.writeAsBytes(bytes, flush: true);
      await temp.rename(file.path);
    } catch (_) {}
  }

  @override
  bool operator ==(Object other) {
    if (other.runtimeType != runtimeType) return false;
    return other is CachedTileImageProvider && other.url == url;
  }

  @override
  int get hashCode => url.hashCode;
}
