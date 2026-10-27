from base.spider import Spider as BaseSpider


class Spider(BaseSpider):
    def init(self, extend=''):
        self.base = extend

    def homeContent(self, filter):
        # Exercises the actual HTTP bridge plus bundled requests and lxml.
        title = self.html(self.fetch(self.base + 'title').text).xpath('//h1/text()')[0]
        return {'class': [{'type_id': 'films', 'type_name': title}]}

    def video(self, title):
        return {'list': [{'vod_id': 'movie', 'vod_name': title,
                         'vod_play_from': '原生', 'vod_play_url': '第一集$episode'}]}

    def categoryContent(self, tid, pg, filter, extend):
        return self.video('Python ' + tid + ' ' + pg)

    def detailContent(self, ids):
        assert ids == ['movie']
        return self.video('Python 详情')

    def searchContent(self, key, quick):
        return self.video(key)

    def playerContent(self, flag, id, vipFlags):
        assert id == 'episode'
        return {'parse': 0, 'url': self.base + 'video.mp4', 'header': {'Referer': self.base}}
