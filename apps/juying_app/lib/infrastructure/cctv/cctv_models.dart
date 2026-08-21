/// CCTV 公开目录的来源专有字段。不得越过该适配器进入通用界面或领域模型。
enum CctvCatalogCategory {
  animation('动画片', 'CHAL1460955899450127'),
  drama('电视剧', 'CHAL1460955853485115'),
  documentary('纪录片', 'CHAL1460955924871139'),
  special('特别节目', 'CHAL1460955953877151');

  const CctvCatalogCategory(this.label, this.channelId);

  final String label;
  final String channelId;
}

class CctvProgram {
  const CctvProgram({
    required this.id,
    required this.title,
    required this.officialPageUrl,
    required this.episodePageUrl,
    required this.category,
    this.episodeTitle,
    this.imageUrl,
    this.brief,
    this.year,
    this.area,
    this.channel,
    this.subcategory,
    this.episodeCount,
  });

  final String id;
  final String title;
  final Uri officialPageUrl;
  final Uri episodePageUrl;
  final CctvCatalogCategory category;
  final String? episodeTitle;
  final Uri? imageUrl;
  final String? brief;
  final String? year;
  final String? area;
  final String? channel;
  final String? subcategory;
  final int? episodeCount;
}

class CctvEpisode {
  const CctvEpisode({
    required this.id,
    required this.title,
    required this.officialPageUrl,
    this.imageUrl,
    this.brief,
    this.number,
  });

  final String id;
  final String title;
  final Uri officialPageUrl;
  final Uri? imageUrl;
  final String? brief;
  final int? number;
}

class CctvCatalogResult {
  const CctvCatalogResult({
    required this.items,
    required this.page,
    required this.total,
  });

  final List<CctvProgram> items;
  final int page;
  final int total;
}
