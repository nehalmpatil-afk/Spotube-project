import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/provider/metadata_plugin/metadata_plugin_provider.dart';
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

  // --- 1. Same artist's top tracks ---
  final primaryArtistId =
      seedTrack.artists.isNotEmpty ? seedTrack.artists.first.id : null;

  if (primaryArtistId != null) {
    try {
      final artistTopTracks = await metadataPlugin.artist.topTracks(
        primaryArtistId,
        limit: 10,
      );
      addUnique(artistTopTracks.items);
    } catch (e, stack) {
      AppLogger.reportError(e, stack);
    }
  }

  // --- 2. Related artists' top tracks (limit to 3 related artists) ---
  if (primaryArtistId != null && results.length < 12) {
    try {
      final relatedArtists = await metadataPlugin.artist.related(
        primaryArtistId,
        limit: 3,
      );

      for (final relatedArtist in relatedArtists.items) {
        if (results.length >= 12) break;
        try {
          final relatedTopTracks = await metadataPlugin.artist.topTracks(
            relatedArtist.id,
            limit: 3,
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

  // --- 3. Other tracks from the same album ---
  if (results.length < 12) {
    try {
      final albumTracks = await metadataPlugin.album.tracks(
        seedTrack.album.id,
        limit: 10,
      );
      addUnique(albumTracks.items);
    } catch (e, stack) {
      AppLogger.reportError(e, stack);
    }
  }

  // --- 4. track.radio() as supplementary source ---
  if (results.length < 8) {
    try {
      final radioTracks = await metadataPlugin.track.radio(seedId);
      addUnique(radioTracks);
    } catch (e, stack) {
      AppLogger.reportError(e, stack);
    }
  }

  // Cap at a reasonable number
  if (results.length > 15) {
    return results.sublist(0, 15);
  }

  return results;
}
