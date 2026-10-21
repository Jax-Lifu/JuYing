/// Unified VOD (Video on Demand) Domain Export (Section 6.1 features/vod).
///
/// **What**: Consolidates categories, federated search, media details, and episode
/// selection into a cohesive VOD domain layer.
///
/// **Why**: Section 6.1 unites TVBox sources, official CCTV catalogs, federated search,
/// and video details under the `vod/` domain.
library;

export 'package:juying/features/cctv/presentation/cctv_page.dart';
export 'package:juying/features/detail/presentation/video_detail_page.dart';
export 'package:juying/features/search/presentation/search_page.dart';
export 'package:juying/features/tvbox/models/tvbox_site.dart';
export 'package:juying/features/tvbox/services/tvbox_spider_engine.dart';
