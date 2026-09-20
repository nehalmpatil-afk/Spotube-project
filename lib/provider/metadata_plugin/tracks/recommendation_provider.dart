import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/provider/metadata_plugin/metadata_plugin_provider.dart';
import 'package:spotube/provider/recommendations/recommendations.dart';
import 'package:spotube/services/logger/logger.dart';
import 'package:spotube/services/metadata/errors/exceptions.dart';
import 'package:spotube/services/metadata/metadata.dart';

/// Fetches related track recommendations for a given seed track.
///
/// Priority order:
/// 1. Same artist's top tracks
/// 2. Related artists' top tracks
/// 3. Other tracks from the same album
/// 4. track.radio() results as supplementary source
///
/// Returns 8-12 genuinely relevant tracks rather than 20 weak ones.
/// Excludes the seed track and removes duplicates.
final trackRecommendationProvider = FutureProvider.autoDispose
    .family<List<SpotubeFullTrackObject>, SpotubeFullTrackObject>(
  (ref, seedTrack) async {
    final metadataPlugin = await ref.read(metadataPluginProvider.future);

    if (metadataPlugin == null) {
      throw MetadataPluginException.noDefaultMetadataPlugin();
    }

    return _fetchRecommendations(metadataPlugin, seedTrack);
  },
);

Future<List<SpotubeFullTrackObject>> _fetchRecommendations(
  MetadataPlugin metadataPlugin,
  SpotubeFullTrackObject seedTrack,
) async {
  final seedId = seedTrack.id;
  final seenIds = <String>{seedId};
  final results = <SpotubeFullTrackObject>[];

  void addUnique(Iterable<SpotubeFullTrackObject> tracks) {
    for (final track in tracks) {
      if (seenIds.contains(track.id)) continue;
      seenIds.add(track.id);
      results.add(track);
    }
  }

  try {
    // --- 1. Same artist's top tracks ---
    final primaryArtistId =
        seedTrack.artists.isNotEmpty ? seedTrack.artists.first.id : null;

    if (primaryArtistId != null) {
      final artistTopTracks = await safePluginCall(
        () => metadataPlugin.artist.topTracks(
          primaryArtistId,
          limit: 10,
        ),
      );
      if (artistTopTracks != null) {
        addUnique(artistTopTracks.items);
      }
    }

    // --- 2. Related artists' top tracks (limit to 2 related artists) ---
    if (primaryArtistId != null && results.length < 12) {
      final relatedArtists = await safePluginCall(
        () => metadataPlugin.artist.related(
          primaryArtistId,
          limit: 2,
        ),
      );

      if (relatedArtists != null) {
        for (final relatedArtist in relatedArtists.items) {
          if (results.length >= 12) break;
          final relatedTopTracks = await safePluginCall(
            () => metadataPlugin.artist.topTracks(
              relatedArtist.id,
              limit: 3,
            ),
          );
          if (relatedTopTracks != null) {
            addUnique(relatedTopTracks.items);
          }
        }
      }
    }

    // --- 3. Other tracks from the same album ---
    if (results.length < 12) {
      final albumTracks = await safePluginCall(
        () => metadataPlugin.album.tracks(
          seedTrack.album.id,
          limit: 10,
        ),
      );
      if (albumTracks != null) {
        addUnique(albumTracks.items);
      }
    }

    // --- 4. track.radio() as supplementary source ---
    if (results.length < 8) {
      final radioTracks = await safePluginCall(
        () => metadataPlugin.track.radio(seedId),
      );
      if (radioTracks != null) {
        addUnique(radioTracks);
      }
    }
  } catch (e, stack) {
    if (e is RateLimitException) {
      AppLogger.reportError(
          "Rate limit reached during track recommendation fetch. Returning accumulated tracks.");
    } else {
      AppLogger.reportError(e, stack);
    }
  }

  // Cap at a reasonable number
  if (results.length > 15) {
    return results.sublist(0, 15);
  }

  return results;
}

