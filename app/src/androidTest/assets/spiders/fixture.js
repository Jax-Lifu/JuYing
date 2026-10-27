import { video } from './video.js';
let base;
export default {
    init(ext) { base = ext; },
    async homeContent() {
        const response = await fetch(base + 'categories');
        return response.json();
    },
    categoryContent(tid, pg) { return video('JS ' + tid + ' ' + pg); },
    detailContent(ids) {
        if (ids[0] !== 'movie') throw new Error('Wrong item routing');
        return video('JS 详情');
    },
    searchContent(key) { return video(key); },
    playerContent(flag, id) {
        if (id !== 'episode') throw new Error('Wrong episode routing');
        return { parse: 0, url: base + 'video.mp4', header: { Referer: base } };
    },
};
