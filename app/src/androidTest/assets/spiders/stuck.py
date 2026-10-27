from base.spider import Spider as BaseSpider


class Spider(BaseSpider):
    def init(self, extend=''):
        self.base = extend

    def homeContent(self, filter):
        self.fetch(self.base + 'started')
        while True:
            pass
