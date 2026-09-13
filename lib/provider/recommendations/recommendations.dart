import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:drift/drift.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:spotube/models/database/database.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/provider/database/database.dart';
import 'package:spotube/provider/history/top.dart';
import 'package:spotube/provider/metadata_plugin/metadata_plugin_provider.dart';
import 'package:spotube/services/logger/logger.dart';

class RecommendedTracksNotifier
    extends AsyncNotifier<List<SpotubeTrackObject>> {
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

    final subscription = query.watch().listen((_) {
      ref.invalidateSelf();
    });
    ref.onDispose(() => subscription.cancel());

    final historyEntries = await query.get();

    if (historyEntries.isEmpty) {
      return [];
    }

    final metadataPlugin = await ref.watch(metadataPluginProvider.future);
    if (metadataPlugin == null) {
      return [];
    }

    // Parse tracks and extract statistics from playback history
    final listenedTracks = <SpotubeTrackObject>[];
    final listenedTrackIds = <String>{};
    final artistCounts =
        <String, ({int count, SpotubeSimpleArtistObject artist})>{};

    for (final entry in historyEntries) {
      try {
        final trackJson = jsonDecode(entry.data) as Map<String, dynamic>;
        final track = SpotubeTrackObject.fromJson(trackJson);
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
      return [];
    }

    // Sort top artists by count
    final sortedTopArtists = artistCounts.values.toList()
      ..sort((a, b) => b.count.compareTo(a.count));

    final topArtists = sortedTopArtists.take(5).map((e) => e.artist).toList();

    final recommendedTracks = <SpotubeTrackObject>[];
    final seenIds = Set<String>.from(listenedTrackIds);

    void addUnique(Iterable<SpotubeTrackObject> tracks) {
      for (final track in tracks) {
        if (seenIds.contains(track.id)) continue;
        seenIds.add(track.id);
        recommendedTracks.add(track);
      }
    }

    // 1. Top tracks for each of the top listened artists
    for (final artist in topArtists) {
      if (recommendedTracks.length >= 20) break;
      try {
        final topTracksRes = await metadataPlugin.artist.topTracks(
          artist.id,
          limit: 10,
        );
        addUnique(topTracksRes.items);
      } catch (e, stack) {
        AppLogger.reportError(e, stack);
      }
    }

    // 2. Top tracks from related artists of the top artist
    if (topArtists.isNotEmpty && recommendedTracks.length < 15) {
      try {
        final relatedArtists = await metadataPlugin.artist.related(
          topArtists.first.id,
          limit: 5,
        );

        for (final related in relatedArtists.items) {
          if (recommendedTracks.length >= 20) break;
          try {
            final relatedTopTracks = await metadataPlugin.artist.topTracks(
              related.id,
              limit: 5,
            );
            addUnique(relatedTopTracks.items);
          } catch (e, stack) {
            AppLogger.reportError(e, stack);
          }
        }
      } catch (e, stack) {
        AppLogger.reportError(e, stack);
      }
    }

    // 3. Track radio for most recently played tracks
    if (listenedTracks.isNotEmpty && recommendedTracks.length < 10) {
      for (final seedTrack in listenedTracks.take(3)) {
        if (recommendedTracks.length >= 20) break;
        try {
          final radioTracks = await metadataPlugin.track.radio(seedTrack.id);
          addUnique(radioTracks);
        } catch (e, stack) {
          AppLogger.reportError(e, stack);
        }
      }
    }

    return recommendedTracks;
  }
}

final recommendedTracksProvider = AsyncNotifierProvider<
    RecommendedTracksNotifier,
    List<SpotubeTrackObject>>(
  () => RecommendedTracksNotifier(),
);
