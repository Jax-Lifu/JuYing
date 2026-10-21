import 'package:flutter/foundation.dart';
import 'package:juying/core/models/media_item.dart';

/// Represents an official CCTV album, column, or program series.
@immutable
class CctvAlbum {
  const CctvAlbum({
    required this.id,
    required this.title,
    required this.posterUrl,
    required this.overview,
    required this.category,
    this.year = '2026',
    this.rating = 9.0,
    this.totalEpisodes = 1,
    this.channelName = 'CCTV官方',
    this.actors = '',
    this.area = '',
    this.vsetId,
    this.firstGuid,
  });

  /// Unique CCTV album ID (e.g. `VIDA8lgsyrdD1LuVvEdkr2Fd260625`).
  final String id;

  /// Display title of the program/album.
  final String title;

  /// High-definition poster or banner image URI.
  final String posterUrl;

  /// Storyline summary and program background description.
  final String overview;

  /// Primary category classification.
  final String category;

  /// Release or broadcasting year.
  final String year;

  /// Official critical reception rating score (0.0 to 10.0).
  final double rating;

  /// Estimated total episodes in the album.
  final int totalEpisodes;

  /// Broadcasting CCTV channel label (e.g. `CCTV-1 综合`, `CCTV-14 少儿`).
  final String channelName;

  /// Cast / Actors list (e.g. `张若昀, 李庚希, 胡军`).
  final String actors;

  /// Region origin (e.g. `内地（大陆）`).
  final String area;

  /// Video Set identifier.
  final String? vsetId;

  /// First episode media GUID for instant playback.
  final String? firstGuid;

  /// 用分集接口的权威总数替换列表接口可能返回的占位数量。
  CctvAlbum withTotalEpisodes(int value) {
    return CctvAlbum(
      id: id,
      title: title,
      posterUrl: posterUrl,
      overview: overview,
      category: category,
      year: year,
      rating: rating,
      totalEpisodes: value,
      channelName: channelName,
      actors: actors,
      area: area,
      vsetId: vsetId,
      firstGuid: firstGuid,
    );
  }

  /// Converts this CCTV album to the app-wide unified [MediaItem] domain representation.
  MediaItem toMediaItem() {
    return MediaItem(
      id: 'cctv_album_$id',
      title: title,
      posterUrl: posterUrl,
      backdropUrl: posterUrl,
      overview: overview,
      year: year,
      rating: rating,
      genres: <String>[
        '央视官方',
        category,
        if (channelName.isNotEmpty) channelName,
        if (area.isNotEmpty) area,
      ],
      cast: actors.isNotEmpty
          ? actors.split(',').map((e) => e.trim()).toList()
          : const <String>[],
      totalEpisodes: totalEpisodes,
    );
  }
}
