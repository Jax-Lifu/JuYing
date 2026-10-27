"""Execute only the user-configured Spider in the disposable worker process."""
import inspect
import json
import types


def load(source, filename, extend, http):
    module = types.ModuleType("user_spider")
    module.__file__ = filename
    exec(compile(source, filename, "exec"), module.__dict__)
    spider = module.Spider()
    spider._http = http
    spider.init(extend)
    return spider


def invoke(spider, method, args_json):
    args = json.loads(args_json)
    target = getattr(spider, method)
    if method == "searchContent":
        signature = inspect.signature(target)
        try:
            signature.bind(*args)
        except TypeError:
            signature.bind(*args[:2])
            if str(args[2]) != "1":
                return '{"list":[]}'
            args = args[:2]
    result = target(*args)
    return result if isinstance(result, str) else json.dumps(result, ensure_ascii=False)


def destroy(spider):
    spider.destroy()
