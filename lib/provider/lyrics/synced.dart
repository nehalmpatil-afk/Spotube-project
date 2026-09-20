import 'dart:async';

import 'package:collection/collection.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:fuzzywuzzy/fuzzywuzzy.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lrc/lrc.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:spotube/models/database/database.dart';
import 'package:spotube/models/lyrics.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/provider/database/database.dart';
import 'package:spotube/services/dio/dio.dart';
import 'package:spotube/services/logger/logger.dart';

String _normalizeString(String str) {
  var s = str.toLowerCase();
  s = s.replaceAll(
      RegExp(r'\s*[\(\[](feat|ft)\.?\s+[^\]\)]*[\)\]]', caseSensitive: false),
      '');
  s = s.replaceAll(
      RegExp(r'\s+feat\.?\s+.*|\s+ft\.?\s+.*', caseSensitive: false), '');
  s = s.replaceAll(
      RegExp(
          r'\s*[\(\[\-]\s*(remastered|remaster|live|deluxe|bonus track|official video|audio|lyrics|version|edition|mix)[\)\]]?',
          caseSensitive: false),
      '');
  s = s.replaceAll(RegExp(r'[^\w\s]'), '');
  return s.replaceAll(RegExp(r'\s+'), ' ').trim();
}

class SyncedLyricsNotifier
    extends FamilyAsyncNotifier<SubtitleSimple, SpotubeTrackObject?> {
  SpotubeTrackObject get _track => arg!;

  Future<SubtitleSimple?> _searchLRCLibFallback(String userAgent) async {
    try {
      final cleanTrack = _normalizeString(_track.name);
      final cleanArtist =
          _normalizeString(_track.artists.firstOrNull?.name ?? "");
      final searchQuery = "$cleanTrack $cleanArtist".trim();

      if (searchQuery.isEmpty) return null;

      final searchRes = await globalDio.getUri(
        Uri(
          scheme: "https",
          host: "lrclib.net",
          path: "/api/search",
          queryParameters: {
            "q": searchQuery,
          },
        ),
        options: Options(
          headers: {"User-Agent": userAgent},
          responseType: ResponseType.json,
        ),
      );

      if (searchRes.statusCode != 200 || searchRes.data is! List) {
        return null;
      }

      final items = searchRes.data as List;
      if (items.isEmpty) return null;

      final targetTrackNorm = _normalizeString(_track.name);
      final targetArtistNorm =
          _normalizeString(_track.artists.firstOrNull?.name ?? "");
      final targetDurationSec =
          _track.durationMs > 0 ? _track.durationMs / 1000.0 : 0.0;

      ({Map<String, dynamic> item, double score})? bestMatch;

      for (final rawItem in items) {
        if (rawItem is! Map) continue;
        final item = rawItem.cast<String, dynamic>();

        final syncedLyricsRaw = item["syncedLyrics"] as String?;
        final plainLyricsRaw = item["plainLyrics"] as String?;

        final hasSynced = syncedLyricsRaw?.isNotEmpty == true;
        final hasPlain = plainLyricsRaw?.isNotEmpty == true;

        if (!hasSynced && !hasPlain) continue;

        final candidateTrack = item["trackName"] as String? ?? "";
        final candidateArtist = item["artistName"] as String? ?? "";
        final candidateDuration =
            (item["duration"] as num?)?.toDouble() ?? 0.0;

        final candidateTrackNorm = _normalizeString(candidateTrack);
        final candidateArtistNorm = _normalizeString(candidateArtist);

        final trackSim =
            ratio(targetTrackNorm, candidateTrackNorm).toDouble();
        final artistSim =
            targetArtistNorm.isNotEmpty && candidateArtistNorm.isNotEmpty
                ? ratio(targetArtistNorm, candidateArtistNorm).toDouble()
                : 100.0;

        double textScore = (trackSim * 0.65) + (artistSim * 0.35);

        if (trackSim < 45 && textScore < 50) continue;

        double durationScoreBonus = 0.0;
        if (targetDurationSec > 0 && candidateDuration > 0) {
          final durDiff = (targetDurationSec - candidateDuration).abs();
          if (durDiff <= 2.0) {
            durationScoreBonus = 20.0;
          } else if (durDiff <= 5.0) {
            durationScoreBonus = 12.0;
          } else if (durDiff <= 10.0) {
            durationScoreBonus = 5.0;
          } else if (durDiff > 30.0) {
            durationScoreBonus = -30.0;
          }
        }

        double syncedBonus = hasSynced ? 25.0 : 0.0;
        double totalScore = textScore + durationScoreBonus + syncedBonus;

        if (bestMatch == null || totalScore > bestMatch.score) {
          bestMatch = (item: item, score: totalScore);
        }
      }

      if (bestMatch == null) return null;

      final matchedItem = bestMatch.item;
      final syncedLyricsRaw = matchedItem["syncedLyrics"] as String?;
      final plainLyricsRaw = matchedItem["plainLyrics"] as String?;

      if (syncedLyricsRaw?.isNotEmpty == true) {
        final syncedLyrics = Lrc.parse(syncedLyricsRaw!)
            .lyrics
            .map(LyricSlice.fromLrcLine)
            .toList();

        if (syncedLyrics.isNotEmpty) {
          return SubtitleSimple(
            lyrics: syncedLyrics,
            name: _track.name,
            uri: searchRes.realUri,
            rating: 90,
            provider: "LRCLib",
          );
        }
      }

      if (plainLyricsRaw?.isNotEmpty == true) {
        final plainLyrics = plainLyricsRaw!
            .split("\n")
            .map((line) => LyricSlice(text: line, time: Duration.zero))
            .toList();

        return SubtitleSimple(
          lyrics: plainLyrics,
          name: _track.name,
          uri: searchRes.realUri,
          rating: 0,
          provider: "LRCLib",
        );
      }
    } catch (e, stack) {
      AppLogger.reportError(e, stack);
    }

    return null;
  }

  /// Lyrics credits: [lrclib.net](https://lrclib.net) and their contributors
  /// Thanks for their generous public API
  Future<SubtitleSimple> getLRCLibLyrics() async {
    final packageInfo = await PackageInfo.fromPlatform();
    final userAgent =
        "Spotube v${packageInfo.version} (https://github.com/KRTirtho/spotube)";

    SubtitleSimple? exactResult;

    try {
      final res = await globalDio.getUri(
        Uri(
          scheme: "https",
          host: "lrclib.net",
          path: "/api/get",
          queryParameters: {
            "artist_name": _track.artists.first.name,
            "track_name": _track.name,
            "album_name": _track.album.name,
            if (_track.durationMs > 0)
              "duration": (_track.durationMs / 1000).toInt().toString(),
          },
        ),
        options: Options(
          headers: {"User-Agent": userAgent},
          responseType: ResponseType.json,
        ),
      );

      if (res.statusCode == 200 && res.data is Map<String, dynamic>) {
        final json = res.data as Map<String, dynamic>;

        final syncedLyricsRaw = json["syncedLyrics"] as String?;
        final syncedLyrics = syncedLyricsRaw?.isNotEmpty == true
            ? Lrc.parse(syncedLyricsRaw!)
                .lyrics
                .map(LyricSlice.fromLrcLine)
                .toList()
            : null;

        if (syncedLyrics?.isNotEmpty == true) {
          return SubtitleSimple(
            lyrics: syncedLyrics!,
            name: _track.name,
            uri: res.realUri,
            rating: 100,
            provider: "LRCLib",
          );
        }

        final plainLyricsRaw = json["plainLyrics"] as String?;
        if (plainLyricsRaw?.isNotEmpty == true) {
          final plainLyrics = plainLyricsRaw!
              .split("\n")
              .map((line) => LyricSlice(text: line, time: Duration.zero))
              .toList();

          exactResult = SubtitleSimple(
            lyrics: plainLyrics,
            name: _track.name,
            uri: res.realUri,
            rating: 0,
            provider: "LRCLib",
          );
        }
      }
    } catch (_) {
      // Exact match lookup failed or returned error status; proceed to fallback search
    }

    final fallbackResult = await _searchLRCLibFallback(userAgent);

    if (fallbackResult != null && fallbackResult.lyrics.isNotEmpty) {
      if (fallbackResult.rating > 0 ||
          exactResult == null ||
          exactResult.lyrics.isEmpty) {
        return fallbackResult;
      }
    }

    if (exactResult != null) {
      return exactResult;
    }

    return SubtitleSimple(
      lyrics: [],
      name: _track.name,
      uri: Uri.parse("https://lrclib.net"),
      rating: 0,
      provider: "LRCLib",
    );
  }

  @override
  FutureOr<SubtitleSimple> build(track) async {
    try {
      final database = ref.watch(databaseProvider);

      if (track == null) {
        throw "No track currently";
      }

      final cachedLyrics = await (database.select(database.lyricsTable)
            ..where((tbl) => tbl.trackId.equals(track.id)))
          .map((row) => row.data)
          .getSingleOrNull();

      SubtitleSimple? lyrics = cachedLyrics;

      if (lyrics == null ||
          lyrics.lyrics.isEmpty ||
          lyrics.lyrics.length <= 5) {
        lyrics = await getLRCLibLyrics();
      }

      if (lyrics.lyrics.isEmpty) {
        throw Exception("Unable to find lyrics");
      }

      if (cachedLyrics == null || cachedLyrics.lyrics.isEmpty) {
        await database.into(database.lyricsTable).insert(
              LyricsTableCompanion.insert(
                trackId: track.id,
                data: lyrics,
              ),
              mode: InsertMode.replace,
            );
      }

      return lyrics;
    } catch (e, stackTrace) {
      AppLogger.reportError(e, stackTrace);
      rethrow;
    }
  }
}

final syncedLyricsDelayProvider = StateProvider<int>((ref) => 0);

final syncedLyricsProvider = AsyncNotifierProviderFamily<SyncedLyricsNotifier,
    SubtitleSimple, SpotubeTrackObject?>(
  () => SyncedLyricsNotifier(),
);

final syncedLyricsMapProvider =
    FutureProvider.family((ref, SpotubeTrackObject? track) async {
  final syncedLyrics = await ref.watch(syncedLyricsProvider(track).future);

  final isStaticLyrics =
      syncedLyrics.lyrics.every((l) => l.time == Duration.zero);

  final lyricsMap = syncedLyrics.lyrics
      .map((lyric) => {lyric.time.inSeconds: lyric.text})
      .reduce((accumulator, lyricSlice) => {...accumulator, ...lyricSlice});

  return (static: isStaticLyrics, lyricsMap: lyricsMap);
});
