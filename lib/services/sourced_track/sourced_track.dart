import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spotube/models/database/database.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/models/playback/track_sources.dart';
import 'package:spotube/provider/database/database.dart';
import 'package:spotube/provider/metadata_plugin/audio_source/quality_presets.dart';
import 'package:spotube/provider/metadata_plugin/metadata_plugin_provider.dart';
import 'package:spotube/services/dio/dio.dart';
import 'package:spotube/services/logger/logger.dart';
import 'package:spotube/services/metadata/errors/exceptions.dart';

import 'package:spotube/services/sourced_track/exceptions.dart';
import 'package:flutter/foundation.dart';
import 'package:spotube/utils/string_utils.dart';
import 'package:spotube/utils/fuzzy_matcher.dart';
import 'package:spotube/utils/artist_comparator.dart';
import 'package:spotube/utils/duration_utils.dart';

void _logTrackMatching(String message) {
  try {
    AppLogger.log.i(message);
  } catch (_) {
    debugPrint(message);
  }
}

final officialMusicRegex = RegExp(
  r"official\s(video|audio|music\svideo|lyric\svideo|visualizer)",
  caseSensitive: false,
);

class SourcedTrack extends BasicSourcedTrack {
  final Ref ref;

  SourcedTrack({
    required this.ref,
    required super.info,
    required super.query,
    required super.source,
    required super.siblings,
    required super.sources,
  });

  static Future<SourcedTrack> fetchFromTrack({
    required SpotubeFullTrackObject query,
    required Ref ref,
  }) async {
    final audioSource = await ref.read(audioSourcePluginProvider.future);
    final audioSourceConfig = await ref.read(metadataPluginsProvider
        .selectAsync((data) => data.defaultAudioSourcePluginConfig));
    if (audioSource == null || audioSourceConfig == null) {
      throw MetadataPluginException.noDefaultAudioSourcePlugin();
    }

    final database = ref.read(databaseProvider);
    final cachedSource = await (database.select(database.sourceMatchTable)
          ..where((s) =>
              s.trackId.equals(query.id) &
              s.sourceType.equals(audioSourceConfig.slug))
          ..limit(1)
          ..orderBy([
            (s) =>
                OrderingTerm(expression: s.createdAt, mode: OrderingMode.desc),
          ]))
        .get()
        .then((s) => s.firstOrNull);

    if (cachedSource == null) {
      final siblings = await fetchSiblings(ref: ref, query: query);
      if (siblings.isEmpty) {
        throw TrackNotFoundError(query);
      }

      await database.into(database.sourceMatchTable).insert(
            SourceMatchTableCompanion.insert(
              trackId: query.id,
              sourceInfo: Value(jsonEncode(siblings.first)),
              sourceType: audioSourceConfig.slug,
            ),
          );

      final manifest = await audioSource.audioSource.streams(siblings.first);

      return SourcedTrack(
        ref: ref,
        siblings: siblings.skip(1).toList(),
        info: siblings.first,
        source: audioSourceConfig.slug,
        sources: manifest,
        query: query,
      );
    }
    final item = SpotubeAudioSourceMatchObject.fromJson(
      jsonDecode(cachedSource.sourceInfo),
    );
    final manifest = await audioSource.audioSource.streams(item);

    final sourcedTrack = SourcedTrack(
      ref: ref,
      siblings: [],
      sources: manifest,
      info: item,
      query: query,
      source: audioSourceConfig.slug,
    );

    AppLogger.log.i("${query.name}: ${sourcedTrack.url}");

    return sourcedTrack;
  }

  static List<SpotubeAudioSourceMatchObject> rankResults(
    List<SpotubeAudioSourceMatchObject> results,
    SpotubeFullTrackObject track,
  ) {
    // Scoring weights
    const int TITLE_EXACT_BONUS = 1000;
    const int TITLE_SIMILARITY_WEIGHT = 1;
    const int ARTIST_MATCH_BONUS = 200;
    const int DURATION_BONUS = 50;
    const int OFFICIAL_BONUS = 10;

    final normalizedQueryTitle = StringUtils.normalize(track.name);
    final queryArtists = track.artists.map((a) => a.name).toList();
    final queryDuration = Duration(milliseconds: track.durationMs);

    _logTrackMatching(
      "[TrackMatching] rankResults() called:\n"
      "  Target Track: '${track.name}'\n"
      "  Target Artists: [${queryArtists.join(', ')}]\n"
      "  Target Duration: $queryDuration\n"
      "  Evaluating ${results.length} candidate(s)...",
    );

    final scored = results.map((sibling) {
      int score = 0;
      final normalizedSiblingTitle = StringUtils.normalize(sibling.title);

      int exactTitleBonus = 0;
      int fuzzySimilarityScore = 0;
      int artistMatchBonus = 0;
      int durationBonus = 0;
      int officialBonus = 0;

      // Exact title match bonus
      if (normalizedQueryTitle == normalizedSiblingTitle) {
        exactTitleBonus = TITLE_EXACT_BONUS;
        score += exactTitleBonus;
      } else {
        // Fuzzy similarity (0‑100) multiplied by weight
        fuzzySimilarityScore = TITLE_SIMILARITY_WEIGHT *
            FuzzyMatcher.score(normalizedQueryTitle, normalizedSiblingTitle);
        score += fuzzySimilarityScore;
      }

      // Artist name match
      for (final artistName in queryArtists) {
        if (sibling.artists
            .any((a) => ArtistComparator.sameName(a, artistName))) {
          artistMatchBonus = ARTIST_MATCH_BONUS;
          score += artistMatchBonus;
          break;
        }
      }

      // Duration closeness (default 5 s tolerance)
      if (DurationUtils.isClose(sibling.duration, queryDuration)) {
        durationBonus = DURATION_BONUS;
        score += durationBonus;
      }

      // Official flag bonus
      if (officialMusicRegex.hasMatch(sibling.title.toLowerCase())) {
        officialBonus = OFFICIAL_BONUS;
        score += officialBonus;
      }

      _logTrackMatching(
        "[TrackMatching] Candidate Scored: '${sibling.title}'\n"
        "  - Artists: [${sibling.artists.join(', ')}]\n"
        "  - Duration: ${sibling.duration} (Target: $queryDuration)\n"
        "  - Exact Title Bonus: +$exactTitleBonus\n"
        "  - Fuzzy Title Similarity: +$fuzzySimilarityScore\n"
        "  - Artist Match Bonus: +$artistMatchBonus\n"
        "  - Duration Bonus: +$durationBonus\n"
        "  - Official Bonus: +$officialBonus\n"
        "  - Total Score: $score",
      );

      return (sibling: sibling, score: score);
    }).toList();

    final sorted = scored.sorted((a, b) => b.score.compareTo(a.score));

    _logTrackMatching(
      "[TrackMatching] Final Sorted Order:\n${sorted.asMap().entries.map((e) => "  [${e.key}] Score: ${e.value.score} | '${e.value.sibling.title}' by [${e.value.sibling.artists.join(', ')}]").join('\n')}",
    );

    if (sorted.isNotEmpty) {
      _logTrackMatching(
        "[TrackMatching] Selected Best Match (Index 0): '${sorted.first.sibling.title}' (Total Score: ${sorted.first.score})",
      );
    }

    return sorted.map((e) => e.sibling).toList();
  }

  static Future<List<SpotubeAudioSourceMatchObject>> fetchSiblings({
    required SpotubeFullTrackObject query,
    required Ref ref,
  }) async {
    final audioSource = await ref.read(audioSourcePluginProvider.future);

    if (audioSource == null) {
      throw MetadataPluginException.noDefaultAudioSourcePlugin();
    }

    final videoResults = <SpotubeAudioSourceMatchObject>[];

    final searchResults = await audioSource.audioSource.matches(query);

    _logTrackMatching(
      "[TrackMatching] Search Results Returned:\n"
      "  Requested Title: '${query.name}'\n"
      "  Requested Artist(s): [${query.artists.map((a) => a.name).join(', ')}]\n"
      "  Requested Duration: ${Duration(milliseconds: query.durationMs)}\n"
      "  Candidates Count: ${searchResults.length}\n"
      "  Candidates:\n${searchResults.asMap().entries.map((e) => "    [${e.key}] '${e.value.title}' by [${e.value.artists.join(', ')}] (${e.value.duration})").join('\n')}",
    );

    _logTrackMatching(
      "[TrackMatching] Applying rankResults() for query: '${query.name}'",
    );
    videoResults.addAll(rankResults(searchResults, query));

    return videoResults.toSet().toList();
  }

  Future<SourcedTrack> copyWithSibling() async {
    if (siblings.isNotEmpty) {
      return this;
    }
    final fetchedSiblings = await fetchSiblings(ref: ref, query: query);

    return SourcedTrack(
      ref: ref,
      siblings: fetchedSiblings.where((s) => s.id != info.id).toList(),
      source: source,
      sources: sources,
      info: info,
      query: query,
    );
  }

  Future<SourcedTrack?> swapWithSibling(
    SpotubeAudioSourceMatchObject sibling,
  ) async {
    if (sibling.id == info.id) {
      return null;
    }

    final audioSource = await ref.read(audioSourcePluginProvider.future);
    final audioSourceConfig = await ref.read(metadataPluginsProvider
        .selectAsync((data) => data.defaultAudioSourcePluginConfig));
    if (audioSource == null || audioSourceConfig == null) {
      throw MetadataPluginException.noDefaultAudioSourcePlugin();
    }

    // a sibling source that was fetched from the search results
    final isStepSibling = siblings.none((s) => s.id == sibling.id);

    final newSourceInfo = isStepSibling
        ? sibling
        : siblings.firstWhere((s) => s.id == sibling.id);

    final newSiblings = siblings.where((s) => s.id != sibling.id).toList()
      ..insert(0, info);

    final manifest = await audioSource.audioSource.streams(newSourceInfo);

    final database = ref.read(databaseProvider);

    // Delete the old Entry
    await (database.sourceMatchTable.delete()
          ..where(
            (table) =>
                table.trackId.equals(query.id) &
                table.sourceType.equals(audioSourceConfig.slug),
          ))
        .go();

    await database.into(database.sourceMatchTable).insert(
          SourceMatchTableCompanion.insert(
            trackId: query.id,
            sourceInfo: Value(jsonEncode(sibling)),
            sourceType: audioSourceConfig.slug,
            createdAt: Value(DateTime.now()),
          ),
          mode: InsertMode.replace,
        );

    return SourcedTrack(
      ref: ref,
      source: source,
      siblings: newSiblings,
      sources: manifest,
      info: newSourceInfo,
      query: query,
    );
  }

  Future<SourcedTrack?> swapWithSiblingOfIndex(int index) {
    return swapWithSibling(siblings[index]);
  }

  Future<SourcedTrack> refreshStream() async {
    final audioSource = await ref.read(audioSourcePluginProvider.future);
    final audioSourceConfig = await ref.read(metadataPluginsProvider
        .selectAsync((data) => data.defaultAudioSourcePluginConfig));
    if (audioSource == null || audioSourceConfig == null) {
      throw MetadataPluginException.noDefaultAudioSourcePlugin();
    }

    List<SpotubeAudioSourceStreamObject> validStreams = [];

    final stringBuffer = StringBuffer();
    for (final source in sources) {
      final res = await globalDio.head(
        source.url,
        options:
            Options(validateStatus: (status) => status != null && status < 500),
      );

      stringBuffer.writeln(
        "[${query.id}] ${res.statusCode} ${source.container} ${source.codec} ${source.bitrate}",
      );

      if (res.statusCode! < 400) {
        validStreams.add(source);
      }
    }

    AppLogger.log.d(stringBuffer.toString());

    if (validStreams.isEmpty) {
      validStreams = await audioSource.audioSource.streams(info);
    }

    final sourcedTrack = SourcedTrack(
      ref: ref,
      siblings: siblings,
      source: source,
      sources: validStreams,
      info: info,
      query: query,
    );

    AppLogger.log.i("Refreshing ${query.name}: ${sourcedTrack.url}");

    return sourcedTrack;
  }

  String? get url {
    final preferences = ref.read(audioSourcePresetsProvider);

    return getUrlOfQuality(
      preferences.presets[preferences.selectedStreamingContainerIndex],
      preferences.selectedStreamingQualityIndex,
    );
  }

  /// Returns the URL of the track based on the codec and quality preferences.
  /// If an exact match is not found, it will return the closest match based on
  /// the user's audio quality preference.
  ///
  /// If no sources match the codec, it will return the first or last source
  /// based on the user's audio quality preference.
  SpotubeAudioSourceStreamObject? getStreamOfQuality(
    SpotubeAudioSourceContainerPreset preset,
    int qualityIndex,
  ) {
    if (sources.isEmpty) return null;

    final quality = preset.qualities[qualityIndex];

    final exactMatch = sources.firstWhereOrNull(
      (source) {
        if (source.container != preset.name) return false;

        if (quality case SpotubeAudioLosslessContainerQuality()) {
          return source.sampleRate == quality.sampleRate &&
              source.bitDepth == quality.bitDepth;
        } else {
          return source.bitrate ==
              (quality as SpotubeAudioLossyContainerQuality).bitrate;
        }
      },
    );

    if (exactMatch != null) {
      return exactMatch;
    }

    // Find the preset with closest quality to the supplied quality
    return sources.where((source) {
      return source.container == preset.name;
    }).reduce((prev, curr) {
      if (quality is SpotubeAudioLosslessContainerQuality) {
        final prevDiff = ((prev.sampleRate ?? 0) - quality.sampleRate).abs() +
            ((prev.bitDepth ?? 0) - quality.bitDepth).abs();
        final currDiff = ((curr.sampleRate ?? 0) - quality.sampleRate).abs() +
            ((curr.bitDepth ?? 0) - quality.bitDepth).abs();
        return currDiff < prevDiff ? curr : prev;
      } else {
        final prevDiff = ((prev.bitrate ?? 0) -
                (quality as SpotubeAudioLossyContainerQuality).bitrate)
            .abs();
        final currDiff = ((curr.bitrate ?? 0) - quality.bitrate).abs();
        return currDiff < prevDiff ? curr : prev;
      }
    });
  }

  String? getUrlOfQuality(
    SpotubeAudioSourceContainerPreset preset,
    int qualityIndex,
  ) {
    return getStreamOfQuality(preset, qualityIndex)?.url;
  }

  SpotubeAudioSourceContainerPreset? get qualityPreset {
    final presetState = ref.read(audioSourcePresetsProvider);
    return presetState.presets
        .elementAtOrNull(presetState.selectedStreamingContainerIndex);
  }
}
