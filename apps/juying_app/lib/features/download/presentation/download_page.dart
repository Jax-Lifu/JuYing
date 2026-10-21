import 'dart:io';
import 'package:flutter/material.dart';
import 'package:juying/app/theme/app_theme.dart';
import 'package:juying/app/theme/app_theme_colors.dart';
import 'package:juying/core/i18n/app_strings.dart';
import 'package:juying/core/models/playback_candidate.dart';
import 'package:juying/features/download/services/offline_download_manager.dart';
import 'package:juying/features/player/presentation/video_player_page.dart';
import 'package:juying/shared/tv_focus/tv_focus_wrapper.dart';

/// Full-featured Offline Download Management Page.
///
/// **What**: Displays active downloading segments, progress bars, pause/resume actions,
/// and instant local offline playback for completed episodes.
///
/// **Why**: Offline download management gives mobile and portable device users complete autonomy
/// over media caching and storage management without relying on live network connectivity.
class DownloadPage extends StatefulWidget {
  const DownloadPage({super.key});

  @override
  State<DownloadPage> createState() => _DownloadPageState();
}

class _DownloadPageState extends State<DownloadPage> {
  final OfflineDownloadManager _downloadManager =
      OfflineDownloadManager.instance;

  void _playLocalVideo(DownloadTask task) {
    if (task.outputFilePath == null ||
        !File(task.outputFilePath!).existsSync()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⚠️ 离线文件不存在或仍在重封装中')),
      );
      return;
    }

    final candidate = PlaybackCandidate(
      sourceKey: 'offline_local_${task.id}',
      sourceName: '💾 本地离线缓存',
      lineName: '无损离线播放',
      resolution: '本地原画',
      episodes: <PlaybackEpisode>[
        PlaybackEpisode(
          name: task.episodeName,
          url: task.outputFilePath!,
          sortIndex: 1,
          badge: '本地离线',
        ),
      ],
    );

    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (context) => VideoPlayerPage(
          title: task.title,
          currentEpisode: candidate.episodes.first,
          candidate: candidate,
          allCandidates: <PlaybackCandidate>[candidate],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Scaffold(
      backgroundColor: colors.backgroundDeep,
      appBar: AppBar(
        backgroundColor: colors.surfaceCard,
        elevation: 0,
        title: Text(
          '离线缓存管理 (Offline Downloads)',
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: colors.textPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: StreamBuilder<List<DownloadTask>>(
        stream: _downloadManager.tasksStream,
        initialData: _downloadManager.tasks,
        builder: (context, snapshot) {
          final tasks = snapshot.data ?? <DownloadTask>[];

          if (tasks.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Icon(Icons.download_done,
                      size: 64, color: colors.textTertiary),
                  const SizedBox(height: 16),
                  Text(
                    '暂无离线缓存任务',
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '在视频详情页点击“缓存下载”即可将剧集下载至本地',
                    style: TextStyle(
                      color: colors.textTertiary,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(20),
            itemCount: tasks.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final task = tasks[index];
              return _buildTaskCard(colors, task);
            },
          );
        },
      ),
    );
  }

  Widget _buildTaskCard(AppThemeColors colors, DownloadTask task) {
    final percent = (task.progress * 100).toStringAsFixed(1);
    final isCompleted = task.status == DownloadTaskStatus.completed;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surfaceCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.surfaceElevation),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                isCompleted
                    ? Icons.check_circle
                    : (task.status == DownloadTaskStatus.downloading
                        ? Icons.downloading
                        : Icons.pause_circle_outline),
                color: isCompleted
                    ? const Color(0xFF00FF66)
                    : (task.status == DownloadTaskStatus.downloading
                        ? colors.brandAccent
                        : colors.textTertiary),
                size: 24,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      '${task.title} · ${task.episodeName}',
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isCompleted
                          ? '✅ 缓存完成 (${task.totalSegments} 切片无损重封装)'
                          : (task.status == DownloadTaskStatus.downloading
                              ? '⬇️ 正在下载: $percent% (${task.downloadedSegments}/${task.totalSegments} 切片)'
                              : (task.status == DownloadTaskStatus.paused
                                  ? '⏸️ 已暂停 ($percent%)'
                                  : task.failureReason ==
                                          'unsupported_hls_layout'
                                      ? context
                                          .tr('download_unsupported_hls_layout')
                                      : '❌ 下载失败')),
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              if (isCompleted)
                TvFocusWrapper(
                  onTap: () => _playLocalVideo(task),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: colors.brandPrimary,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Row(
                      children: <Widget>[
                        Icon(Icons.play_arrow, color: Colors.white, size: 16),
                        SizedBox(width: 4),
                        Text('播放',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 12)),
                      ],
                    ),
                  ),
                )
              else if (task.status == DownloadTaskStatus.downloading)
                TvFocusWrapper(
                  onTap: () => _downloadManager.pauseTask(task.id),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: colors.surfaceElevation,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text('暂停',
                        style: TextStyle(
                            color: colors.textSecondary, fontSize: 12)),
                  ),
                )
              else if (task.status == DownloadTaskStatus.paused)
                TvFocusWrapper(
                  onTap: () => _downloadManager.resumeTask(task.id),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: colors.brandPrimary,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text('继续',
                        style: TextStyle(color: Colors.white, fontSize: 12)),
                  ),
                ),
              const SizedBox(width: 8),
              IconButton(
                icon: Icon(Icons.delete_outline,
                    color: colors.textTertiary, size: 20),
                onPressed: () => _downloadManager.deleteTask(task.id),
              ),
            ],
          ),
          if (!isCompleted &&
              task.status == DownloadTaskStatus.downloading) ...<Widget>[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: task.progress,
                backgroundColor: colors.surfaceElevation,
                valueColor: AlwaysStoppedAnimation<Color>(colors.brandPrimary),
                minHeight: 4,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
