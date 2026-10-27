export function video(title) {
    return { list: [{ vod_id: 'movie', vod_name: title,
        vod_play_from: '原生', vod_play_url: '第一集$episode' }] };
}
