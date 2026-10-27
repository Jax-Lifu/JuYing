var base;
var video = title => JSON.stringify({ list: [{ vod_id: 'movie', vod_name: title,
    vod_play_from: '原生', vod_play_url: '第一集$episode' }] });
var __jsEvalReturn = {
    init(config) { base = config.ext; },
    home() { return req(base + 'categories').content; },
    category(tid, pg) { return video('Legacy ' + tid + ' ' + pg); },
    detail(id) {
        if (id !== 'movie') throw new Error('Legacy detail needs a string ID');
        return video('Legacy 详情');
    },
    search(key) { return video(key); },
    play(flag, id) {
        return JSON.stringify({ parse: 0, url: base + 'video.mp4', header: { Referer: base } });
    },
};
