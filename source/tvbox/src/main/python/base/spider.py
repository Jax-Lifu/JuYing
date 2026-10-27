"""Small TVBox base contract. Network data stays bounded and in memory."""
import json
import requests
from lxml import etree


class Spider:
    def init(self, extend=""):
        pass

    def destroy(self):
        pass

    def fetch(self, url, params=None, cookies=None, headers=None, **kwargs):
        return self._request("GET", url, params=params, cookies=cookies, headers=headers)

    def post(self, url, data=None, json=None, cookies=None, headers=None, **kwargs):
        return self._request("POST", url, data=data, json=json, cookies=cookies, headers=headers)

    def _request(self, method, url, **kwargs):
        request = requests.Request(method, url, **kwargs).prepare()
        body = request.body or ""
        if isinstance(body, bytes):
            body = body.decode("utf-8")
        result = json.loads(str(self._http.request(request.url, json.dumps({
            "method": method, "headers": dict(request.headers), "body": body,
        }))))
        response = requests.Response()
        response.status_code = result["code"]
        response.headers.update(result["headers"])
        response._content = result["content"].encode("utf-8")
        response.encoding = "utf-8"
        response.url = request.url
        return response

    def html(self, content):
        return etree.HTML(content)

    def getName(self):
        return self.__class__.__name__

    def page(self, items, current, size):
        current, size = max(1, int(current)), int(size)
        if size <= 0:
            raise ValueError("分页大小必须大于零")
        return {
            "list": items[(current - 1) * size:current * size],
            "page": current, "pagecount": (len(items) + size - 1) // size,
            "limit": size, "total": len(items),
        }

    def log(self, message):
        # 第三方日志可能包含密码、Cookie 或 Token，不写入系统日志。
        pass
