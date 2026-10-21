import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:juying/app/theme/app_theme.dart';
import 'package:juying/core/i18n/app_strings.dart';
import 'package:juying/core/models/media_item.dart';
import 'package:juying/core/models/playback_candidate.dart';
import 'package:juying/features/detail/presentation/video_detail_page.dart';
import 'package:juying/features/search/services/federated_search_service.dart';
import 'package:juying/features/tvbox/models/tvbox_site.dart';
import 'package:juying/features/tvbox/providers/tvbox_provider.dart';
import 'package:juying/features/tvbox/services/tvbox_spider_engine.dart';
import 'package:juying/shared/tv_focus/tv_focus_wrapper.dart';

/// Federated multi-source search page with on-screen TV keypad, history, and concurrent CCTV/TVBox queries.
///
/// **What**: Provides an on-screen alphabet key matrix for TV remotes, 300ms debounced search,
/// search history tags, hot search chips, and concurrent federated retrieval across all CCTV and TVBox sites.
///
/// **Why**: Media aggregation clients need unified federated search that hits CCTV Official and all
/// third-party spider lines simultaneously, aggregating results without duplicate cards.
class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key, this.searchService, this.spiderEngine});

  /// 可注入数据服务，以验证多源请求乱序返回时的页面状态。
  final FederatedSearchService? searchService;
  final TvBoxSpiderEngine? spiderEngine;

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  final TextEditingController _controller = TextEditingController();
  late final FederatedSearchService _federatedSearchService =
      widget.searchService ?? FederatedSearchService();
  late final TvBoxSpiderEngine _spiderEngine =
      widget.spiderEngine ?? TvBoxSpiderEngine();
  Timer? _debounceTimer;
  int _searchGeneration = 0;

  List<MediaItem> _results = <MediaItem>[];
  final Map<String, List<PlaybackCandidate>> _candidatesMap =
      <String, List<PlaybackCandidate>>{};
  bool _isSearching = false;
  List<String> _searchHistory = <String>[];

  final List<String> _hotKeywords = const <String>[
    '小小围棋少年',
    '雪中悍刀行',
    '庆余年',
    '繁花',
    '三体',
    '狂飙',
    '大决战',
    '西游记',
  ];

  final List<String> _alphabetKeys = const <String>[
    'A',
    'B',
    'C',
    'D',
    'E',
    'F',
    'G',
    'H',
    'I',
    'J',
    'K',
    'L',
    'M',
    'N',
    'O',
    'P',
    'Q',
    'R',
    'S',
    'T',
    'U',
    'V',
    'W',
    'X',
    'Y',
    'Z',
    '1',
    '2',
    '3',
    '4',
    '5',
    '6',
    '7',
    '8',
    '9',
    '0',
    '清空',
    '退格',
  ];

  @override
  void initState() {
    super.initState();
    _loadSearchHistory();
    _performFederatedSearch('围棋');
  }

  Future<void> _loadSearchHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final history = prefs.getStringList('juying_search_history') ?? <String>[];
    if (mounted) {
      setState(() {
        _searchHistory = history;
      });
    }
  }

  Future<void> _saveSearchKeyword(String keyword) async {
    if (keyword.trim().isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final history = prefs.getStringList('juying_search_history') ?? <String>[];
    history.remove(keyword);
    history.insert(0, keyword);
    if (history.length > 15) history.removeRange(15, history.length);
    await prefs.setStringList('juying_search_history', history);
    if (mounted) {
      setState(() {
        _searchHistory = history;
      });
    }
  }

  Future<void> _clearSearchHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('juying_search_history');
    if (mounted) {
      setState(() {
        _searchHistory = <String>[];
      });
    }
  }

  void _onQueryChanged(String val) {
    _debounceTimer?.cancel();
    // 页面世代覆盖 CCTV 和站点查询，也覆盖输入清空及防抖等待窗口。
    ++_searchGeneration;
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      if (val.trim().isNotEmpty) {
        _performFederatedSearch(val.trim());
      } else {
        setState(() {
          _results = <MediaItem>[];
          _candidatesMap.clear();
          _isSearching = false;
        });
      }
    });
  }

  Future<void> _performFederatedSearch(String keyword) async {
    final generation = ++_searchGeneration;
    setState(() => _isSearching = true);
    await _saveSearchKeyword(keyword);
    if (!mounted || generation != _searchGeneration) return;

    final activeSite = ref.read(activeTvBoxSiteProvider);
    final resultMap = <String, MediaItem>{};
    final candidatesMap = <String, List<PlaybackCandidate>>{};

    // 1. Query CCTV official catalog
    await _federatedSearchService.executeSearch(
      keyword,
      onUpdate: (aggResults, epoch) {
        for (final r in aggResults) {
          resultMap[r.item.id] = r.item;
          candidatesMap[r.item.id] = r.candidates;
        }
      },
    );
    if (!mounted || generation != _searchGeneration) return;

    // 2. 查询当前选中的 TVBox 站点，确保详情页仍绑定同一来源身份。
    // 跨站只返回 MediaItem 会丢失 siteKey，可能用另一个源的 vod_id 请求详情。
    try {
      final spiderResults = await _spiderEngine.federatedSearch(
        <TvBoxSite>[activeSite],
        keyword,
      );
      for (final item in spiderResults) {
        resultMap[item.id] = item;
      }
    } catch (e) {
      debugPrint('[Search] Spider query error: $e');
    }

    if (mounted && generation == _searchGeneration) {
      setState(() {
        _results = resultMap.values.toList();
        _candidatesMap
          ..clear()
          ..addAll(candidatesMap);
        _isSearching = false;
      });
    }
  }

  void _onKeyPress(String key) {
    if (key == '清空') {
      _controller.clear();
      _onQueryChanged('');
    } else if (key == '退格') {
      if (_controller.text.isNotEmpty) {
        _controller.text =
            _controller.text.substring(0, _controller.text.length - 1);
        _onQueryChanged(_controller.text);
      }
    } else {
      _controller.text += key;
      _onQueryChanged(_controller.text);
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _federatedSearchService.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Scaffold(
      backgroundColor: colors.backgroundDeep,
      body: Row(
        children: <Widget>[
          // Left Virtual Keypad & Hot Tags
          Container(
            width: 320,
            decoration: BoxDecoration(
              color: colors.surfaceCard,
              border: Border(
                right: BorderSide(
                  color: colors.surfaceElevation,
                ),
              ),
            ),
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '🔍 ${context.tr("nav_search")}',
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),

                // Search Input Field
                TextField(
                  controller: _controller,
                  onChanged: _onQueryChanged,
                  style: TextStyle(color: colors.textPrimary),
                  decoration: InputDecoration(
                    hintText: context.tr('search_hint'),
                    hintStyle:
                        TextStyle(color: colors.textTertiary, fontSize: 11),
                    filled: true,
                    fillColor: colors.surfaceElevation,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // On-screen Alphabet Keypad Grid
                Expanded(
                  child: GridView.builder(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 6,
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                      childAspectRatio: 1.1,
                    ),
                    itemCount: _alphabetKeys.length,
                    itemBuilder: (context, index) {
                      final key = _alphabetKeys[index];
                      return TvFocusWrapper(
                        onTap: () => _onKeyPress(key),
                        child: Container(
                          decoration: BoxDecoration(
                            color: colors.surfaceElevation,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Center(
                            child: Text(
                              key,
                              style: TextStyle(
                                color: key == '清空' || key == '退格'
                                    ? colors.brandAccent
                                    : colors.textPrimary,
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),

          // Right Search Results Panel
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  // Search History Tags
                  if (_searchHistory.isNotEmpty) ...<Widget>[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: <Widget>[
                        Text(
                          '🕒 搜索历史',
                          style: TextStyle(
                            color: colors.textSecondary,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        InkWell(
                          onTap: _clearSearchHistory,
                          child: Text(
                            '清空历史',
                            style: TextStyle(
                                color: colors.textTertiary, fontSize: 11),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: <Widget>[
                        for (final historyWord in _searchHistory)
                          TvFocusWrapper(
                            onTap: () {
                              _controller.text = historyWord;
                              _onQueryChanged(historyWord);
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: colors.surfaceElevation,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                historyWord,
                                style: TextStyle(
                                  color: colors.textPrimary,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Hot Keyword Chips
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: <Widget>[
                      Text(
                        context.tr('search_hot_keywords'),
                        style: TextStyle(
                          color: colors.textSecondary,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      for (final tag in _hotKeywords)
                        TvFocusWrapper(
                          onTap: () {
                            _controller.text = tag;
                            _onQueryChanged(tag);
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: colors.surfaceElevation,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Text(
                              tag,
                              style: TextStyle(
                                color: colors.textPrimary,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Result List
                  Expanded(
                    child: _isSearching
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                const CircularProgressIndicator(),
                                const SizedBox(height: 12),
                                Text(
                                  context.tr('search_searching'),
                                  style: TextStyle(
                                      color: colors.textSecondary,
                                      fontSize: 13),
                                ),
                              ],
                            ),
                          )
                        : _results.isEmpty
                            ? Center(
                                child: Text(
                                  context.tr('search_no_results'),
                                  style: TextStyle(
                                    color: colors.textTertiary,
                                    fontSize: 14,
                                  ),
                                ),
                              )
                            : ListView.separated(
                                itemCount: _results.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 10),
                                itemBuilder: (context, index) {
                                  final item = _results[index];
                                  final candidates = _candidatesMap[item.id] ??
                                      <PlaybackCandidate>[];

                                  return TvFocusWrapper(
                                    onTap: () {
                                      Navigator.of(context, rootNavigator: true)
                                          .push(
                                        MaterialPageRoute<void>(
                                          fullscreenDialog: true,
                                          builder: (context) => VideoDetailPage(
                                            mediaItem: item,
                                            candidates: candidates,
                                          ),
                                        ),
                                      );
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.all(14),
                                      decoration: BoxDecoration(
                                        color: colors.surfaceCard,
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Row(
                                        children: <Widget>[
                                          ClipRRect(
                                            borderRadius:
                                                BorderRadius.circular(6),
                                            child: Container(
                                              width: 50,
                                              height: 70,
                                              color: colors.surfaceElevation,
                                              child: item.posterUrl != null
                                                  ? Image.network(
                                                      item.posterUrl!,
                                                      fit: BoxFit.cover,
                                                      errorBuilder:
                                                          (_, __, ___) => Icon(
                                                        Icons
                                                            .movie_creation_outlined,
                                                        color:
                                                            colors.textTertiary,
                                                      ),
                                                    )
                                                  : Icon(
                                                      Icons
                                                          .movie_creation_outlined,
                                                      color:
                                                          colors.textTertiary,
                                                    ),
                                            ),
                                          ),
                                          const SizedBox(width: 14),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: <Widget>[
                                                Text(
                                                  item.title,
                                                  style: TextStyle(
                                                    color: colors.textPrimary,
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                                const SizedBox(height: 6),
                                                Text(
                                                  item.overview ?? '',
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    color: colors.textSecondary,
                                                    fontSize: 12,
                                                  ),
                                                ),
                                                const SizedBox(height: 6),
                                                Row(
                                                  children: <Widget>[
                                                    Container(
                                                      padding: const EdgeInsets
                                                          .symmetric(
                                                          horizontal: 6,
                                                          vertical: 2),
                                                      decoration: BoxDecoration(
                                                        color: colors
                                                            .brandPrimary
                                                            .withAlpha(50),
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(4),
                                                      ),
                                                      child: Text(
                                                        item.id.startsWith(
                                                                'cctv_')
                                                            ? '🏛️ 央视官方 4K'
                                                            : '📺 TVBox 聚合源',
                                                        style: TextStyle(
                                                          color: colors
                                                              .focusBorder,
                                                          fontSize: 10,
                                                          fontWeight:
                                                              FontWeight.w600,
                                                        ),
                                                      ),
                                                    ),
                                                    if (item.rating !=
                                                        null) ...<Widget>[
                                                      const SizedBox(width: 8),
                                                      Text(
                                                        '⭐ ${item.rating}',
                                                        style: TextStyle(
                                                          color: colors
                                                              .brandAccent,
                                                          fontSize: 11,
                                                          fontWeight:
                                                              FontWeight.w600,
                                                        ),
                                                      ),
                                                    ],
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
