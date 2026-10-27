// 本应用自行实现的 TVBox 调用桥，不加载远端引导代码。
globalThis.req = (url, options = {}) => JSON.parse(__http(url, JSON.stringify(options)));
globalThis.request = req;
globalThis.fetch = async (url, options = {}) => {
    const result = JSON.parse(await __httpAsync(url, JSON.stringify(options)));
    return {
        status: result.code,
        ok: result.code >= 200 && result.code < 300,
        headers: result.headers,
        text: async () => result.content,
        json: async () => JSON.parse(result.content),
    };
};
globalThis.console = { log() {}, info() {}, warn() {}, error() {}, debug() {} };
globalThis.log = () => {}; // 脚本日志可能包含授权数据，不转发到系统日志。
globalThis.page = (items, current, size) => {
    const number = Math.max(1, Number(current));
    if (!(size > 0)) throw new Error('分页大小必须大于零');
    return {
        list: items.slice((number - 1) * size, number * size),
        page: number, pagecount: Math.ceil(items.length / size), limit: size, total: items.length,
    };
};
globalThis.__invokeSpider = async (name, legacyName, args) => {
    const modern = typeof __spider[name] === 'function';
    const method = modern ? __spider[name] : __spider[legacyName];
    if (typeof method !== 'function') throw new Error('Spider 缺少方法: ' + name);
    if (!modern && legacyName === 'detail') args = [args[0][0]];
    const value = await method.apply(__spider, args);
    return typeof value === 'string' ? value : JSON.stringify(value);
};
