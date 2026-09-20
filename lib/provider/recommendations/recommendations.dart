import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:spotube/models/database/database.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/provider/database/database.dart';
import 'package:spotube/provider/history/top.dart';
import 'package:spotube/provider/metadata_plugin/metadata_plugin_provider.dart';
import 'package:spotube/services/logger/logger.dart';

class RateLimitException implements Exception {
  final Object originalError;
  RateLimitException(this.originalError);

  @override
  String toString() => 'RateLimitException: $originalError';
}

bool isRateLimitError(dynamic e) {
  if (e is DioException) {
    if (e.response?.statusCode == 429) return true;
  }
  final str = e.toString().toLowerCase();
  return str.contains('429') || str.contains('too many requests');
}

Future<T?> safePluginCall<T>(
  Future<T> Function() call, {
  int maxRetries = 1,
  Duration initialDelay = const Duration(milliseconds: 500),
}) async {
  int attempts = 0;
  while (attempts <= maxRetries) {
    try {
      return await call();
    } catch (e, stack) {
      attempts++;
      if (isRateLimitError(e)) {
        AppLogger.reportError(
            e, null, 'Rate limit hit (429): skipping further plugin retries.');
        throw RateLimitException(e);
      }
      if (attempts > maxRetries) {
        AppLogger.reportError(e, stack);
        return null;
      }
      await Future.delayed(initialDelay * (1 << (attempts - 1)));
    }
  }
  return null;
}

class RecommendedTracksNotifier
    extends AsyncNotifier<List<SpotubeTrackObject>> {
  String? _cachedKey;
  List<SpotubeTrackObject>? _cachedTracks;

  @override
  Future<List<SpotubeTrackObject>> build() async {
    final database = ref.watch(databaseProvider);
    final duration = ref.watch(playbackHistoryTopDurationProvider);

    final sinceDate = switch (duration) {
      HistoryDuration.allTime => DateTime(1970),
      HistoryDuration.days7 =>
        DateTime.now().subtract(const Duration(days: 7)),
      HistoryDuration.days30 =>
        DateTime.now().subtract(const Duration(days: 30)),
      HistoryDuration.months6 =>
        DateTime.now().subtract(const Duration(days: 30 * 6)),
      HistoryDuration.year =>
        DateTime.now().subtract(const Duration(days: 365)),
      HistoryDuration.years2 =>
        DateTime.now().subtract(const Duration(days: 365 * 2)),
    };

    final query = database.select(database.historyTable)
      ..where(
        (tbl) =>
            tbl.type.equalsValue(HistoryEntryType.track) &
            tbl.createdAt.isBiggerOrEqualValue(sinceDate),
      )
      ..orderBy([(tbl) => OrderingTerm.desc(tbl.createdAt)]);

    final subscription = query.watch().skip(1).listen((_) {
      ref.invalidateSelf();
    });
    ref.onDispose(() => subscription.cancel());

    final historyEntries = await query.get();

    if (historyEntries.isEmpty) {
      _cachedKey = null;
      _cachedTracks = [];
      return [];
    }

    final metadataPlugin = await ref.watch(metadataPluginProvider.future);
    if (metadataPlugin == null) {
      _cachedKey = null;
      _cachedTracks = [];
      return [];
    }

    // Parse tracks and extract statistics from playback history
    final listenedTracks = <SpotubeTrackObject>[];
    final listenedTrackIds = <String>{};
    final artistCounts =
        <String, ({int count, SpotubeSimpleArtistObject artist})>{};

    for (final entry in historyEntries) {
      try {
        final track = SpotubeTrackObject.fromJson(entry.data);
        listenedTracks.add(track);
        listenedTrackIds.add(track.id);

        for (final artist in track.artists) {
          if (artist.id.isEmpty) continue;
          final existing = artistCounts[artist.id];
          if (existing != null) {
            artistCounts[artist.id] = (
              count: existing.count + 1,
              artist: existing.artist.images != null
                  ? existing.artist
                  : (artist.images != null ? artist : existing.artist),
            );
          } else {
            artistCounts[artist.id] = (count: 1, artist: artist);
          }
        }
      } catch (e, stack) {
        AppLogger.reportError(e, stack);
      }
    }

    if (artistCounts.isEmpty) {
      _cachedKey = null;
      _cachedTracks = [];
      return [];
    }

    // Sort top artists by count
    final sortedTopArtists = artistCounts.values.toList()
      ..sort((a, b) => b.count.compareTo(a.count));

    final topArtists = sortedTopArtists.take(2).map((e) => e.artist).toList();

    final cacheKey =
        "${duration.name}|${topArtists.map((a) => a.id).join(',')}|${listenedTracks.firstOrNull?.id}";

    if (_cachedKey == cacheKey && _cachedTracks != null) {
      return _cachedTracks!;
    }

    final recommendedTracks = <SpotubeTrackObject>[];
    final seenIds = Set<String>.from(listenedTrackIds);

    void addUnique(Iterable<SpotubeTrackObject> tracks) {
      for (final track in tracks) {
        if (seenIds.contains(track.id)) continue;
        seenIds.add(track.id);
        recommendedTracks.add(track);
      }
    }

    int apiCallCount = 0;
    const maxApiCalls = 4;

    try {
      // 1. Top tracks for each of the top listened artists (max 2 artists, limit 5 tracks)
      for (final artist in topArtists) {
        if (recommendedTracks.length >= 20 || apiCallCount >= maxApiCalls) break;
        apiCallCount++;
        final topTracksRes = await safePluginCall(
          () => metadataPlugin.artist.topTracks(
            artist.id,
            limit: 5,
          ),
        );
        if (topTracksRes != null) {
          addUnique(topTracksRes.items);
        }
      }

      // 2. Top tracks from related artists of the top artist (max 2 related artists, limit 5 tracks)
      if (topArtists.isNotEmpty &&
          recommendedTracks.length < 10 &&
          apiCallCount < maxApiCalls) {
        apiCallCount++;
        final relatedArtists = await safePluginCall(
          () => metadataPlugin.artist.related(
            topArtists.first.id,
            limit: 2,
          ),
        );

        if (relatedArtists != null) {
          for (final related in relatedArtists.items) {
            if (recommendedTracks.length >= 20 || apiCallCount >= maxApiCalls) {
              break;
            }
            apiCallCount++;
            final relatedTopTracks = await safePluginCall(
              () => metadataPlugin.artist.topTracks(
                related.id,
                limit: 5,
              ),
            );
            if (relatedTopTracks != null) {
              addUnique(relatedTopTracks.items);
            }
          }
        }
      }

      // 3. Track radio for most recently played tracks (max 1 seed track)
      if (listenedTracks.isNotEmpty &&
          recommendedTracks.length < 10 &&
          apiCallCount < maxApiCalls) {
        for (final seedTrack in listenedTracks.take(1)) {
          if (recommendedTracks.length >= 20 || apiCallCount >= maxApiCalls) {
            break;
          }
          apiCallCount++;
          final radioTracks = await safePluginCall(
            () => metadataPlugin.track.radio(seedTrack.id),
          );
          if (radioTracks != null) {
            addUnique(radioTracks);
          }
        }
      }
    } catch (e, stack) {
      if (e is RateLimitException) {
        AppLogger.reportError(
            e, null, "Rate limit reached during recommendation fetch. Returning accumulated tracks.");
      } else {
        AppLogger.reportError(e, stack);
      }
    }

    _cachedKey = cacheKey;
    _cachedTracks = recommendedTracks;

    return recommendedTracks;
  }
}

final recommendedTracksProvider = AsyncNotifierProvider<
    RecommendedTracksNotifier,
    List<SpotubeTrackObject>>(
  () => RecommendedTracksNotifier(),
);

