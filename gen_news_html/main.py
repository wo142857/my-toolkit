#!/usr/bin/env python3
# -*- coding: UTF-8 -*-

"""
date: 2021-10-26
author: Liu

将新闻内容生成静态网页，方便CDN部署
生成两个文件
1. 详情页（按故事区分）
2. Json 配置文件
    {
        "categorys": [],
        "all_list": [
            {
                "title": "xxx",
                "icon": "xxx",
                "description": "xxx",
                "index": "xxx"
            }
        ]
    }
    {
        "categorys": [],
        "data": {
            "BUZZ": {
                "count": 10,
                "items": [
                    {
                        "id": "xxx",
                        "title": "xxx",
                        "category": "BUZZ",
                        "description": "xxx",
                        "count": 100,
                        "icon": "xxx",
                        "index": "xxx"
                    }
                ]
            }
        }
    }
"""

import os, redis, json, random
from bottle import template

center_ads = """
    <div class='ai-viewports ai-viewport-3'style="float:none;margin:3px 0 3px 0;text-align:center;">
        <div class="quads-ad-label">Advertisement</div>
        {{!detailArticleCenter}}
    </div>
"""

bottom_ads = """
<div class="quads-location quads-ad8" id="quads-ad8" style="float:none;margin:3px 0 3px 0;text-align:center;">
    <div class="quads-ad-label">Advertisement</div>
    {{!detailBottom}}
</div>
"""

next_html = """
<div class="mpp-page-link page-link">
    <a href="{{next_url}}" id="next-page-link" style="width: 100%">
        NEXT PAGE
    </a>
</div>
"""

prev_next_html = """
<div class="mpp-page-link page-link">
    <a href="{{prev_url}}" id="previous-page-link">
        PREV
    </a>
    <a href="{{next_url}}" id="next-page-link">
        NEXT PAGE
    </a>
</div>
"""

prev_html = """
<div class="mpp-page-link page-link">
    <a href="{{prev_url}}" id="previous-page-link" style="width: 100%">
        PREV
    </a>
</div>
"""


template_file = "template/detail.html"
with open(template_file, "r") as f:
    template_demo = f.read()


def add_category(ret, category):
    if category not in ret["categorys"]:
        ret["categorys"].append({
            "category": category,
            "index": "{0}{1}/{2}/category.html?c={3}".format(ret["scheme"], ret["domain"], ret["chid"], category)
        })
        ret["data"][category] = {
            "count": 0,
            "items": []
        }


def generate_html(page_file, data, ads):
    html = template(template_demo, {
        "title": data["title"],
        "url": data["url"],
        "description": "",
        "content": data["content"],
        "prev_link": data["prev_link"],
        "next_link": data["next_link"],
        "gaCode": ads["gaCode"],
        "detail_header": ads["detail_header"],
        "detailTop": ads["detailTop"],
        "detailBottom": data["detailBottom"],
        "pn_html": data["pn_html"],
        "sidebar_1": "",
        "sidebar_2": ""
    })
    with open(page_file, "w") as f:
        f.write(html)


def get_story_length(content):
    cnt = 0
    for c in content:
        if c.startswith("<h3"):
            cnt = cnt + 1

    if cnt % 2 == 0:
        return cnt // 2
    else:
        return cnt // 2 + 1


def gen_html(ret, detail):
    # 生成文章目录
    article_path = "ret/" + detail["id"]
    os.mkdir(article_path)

    story_len = get_story_length(detail["content"])

    # 生成静态页，两个故事生成一个详情页
    page, h3 = 1, 0
    content, stop = [], {}
    for line in detail["content"]:
        _url = "{0}{1}/{2}/{3}/".format(ret["scheme"], ret["domain"], ret["chid"], detail["id"])
        prev_url = _url + str(page - 1) + ".html"
        next_url = _url + str(page + 1) + ".html"
        page_url = _url + str(page) + ".html"
        page_file = article_path + "/" + str(page) + ".html"

        prev_link = '<link rel="prev" href="' + prev_url + '" />'
        next_link = '<link rel="next" href="' + next_url + '" />'

        pn_html = ""
        if page == 1 and page < story_len:
            pn_html = template(next_html, next_url=next_url)
            prev_link = ""
        elif page > 1 and page == story_len:
            pn_html = template(prev_html, prev_url=prev_url)
            next_link = ""
        elif page > 1 and page < story_len:
            pn_html = template(prev_next_html, prev_url=prev_url, next_url=next_url)

        if line.startswith("<h3"):
            h3 = h3 + 1

            if h3 == page * 2:
                content.append(template(center_ads, detailArticleCenter=ret["ads"]["detailArticleCenter"]))
                content.append(pn_html)
            elif h3 == page * 2 + 1:
                # 写入html
                generate_html(page_file, {
                    "title": detail["title"],
                    #"description": detail["description"],
                    "url": page_url,
                    "prev_link": prev_link,
                    "next_link": next_link,
                    "detailBottom": template(bottom_ads, detailBottom=ret["ads"]["detailBottom"]),
                    "pn_html": pn_html,
                    "content": "\n".join(content)
                }, ret["ads"])

                page = page + 1
                content = []

        content.append(line)
        stop = {
            "title": detail["title"],
            #"description": detail["description"],
            "url": next_url,
            "content": "\n".join(content),
            "detailBottom": template(bottom_ads, detailBottom=ret["ads"]["detailBottom"]),
            "pn_html": template(prev_html, prev_url=page_url),
            "page_file": article_path + "/" + str(page) + ".html",
            "prev_link": '<link rel="prev" href="' + page_url + '" />',
            "next_link": ""
        }

    generate_html(stop["page_file"], stop, ret["ads"])


def add_item(ret, category, detail):
    item = {
        "id": detail["id"],
        "title": detail["title"],
        "category": category,
        "icon": detail["pre_img"],
        "index": "{0}{1}/{2}/{3}/1.html".format(ret["scheme"], ret["domain"], ret["chid"], detail["id"])
    }

    if category == "BUZZ":
        item["count"] = get_story_length(detail["content"])
    else:
        item["count"] = 1

    ret["data"][category]["items"].append(item)
    ret["data"][category]["count"]+=1

    ret["all_list"].append({
        "title": detail["title"],
        "icon": detail["pre_img"],
        "category": category,
        "index": item["index"]
    })


def get_content(ret):
    r = redis.Redis(host="127.0.0.1", port=6379, db=12)

    # 内容分类标识
    redis_keys = ["buzz","cosmetic","plastic-surgery","skin-care","anti-aging","IT"]
    for k in redis_keys:
        category = k.upper()
        add_category(ret, category)

        ids_k = "NewsList:" + k
        ids = r.lrange(ids_k, 0, -1)

        for id in ids:
            id_k = "NewsDetail:" + id.decode("utf-8")
            detail = r.get(id_k)

            detail = json.loads(detail)
            detail["id"] = str(detail["id"])

            add_item(ret, category, detail)
            gen_html(ret, detail)


def write_json(data, path):
    with open(path, "w") as f:
        json.dump(data, f)

def get_ads(ret):
    r = redis.Redis(host="127.0.0.1", port=6379, db=4)

    hkey = "ads:news.{0}:{1}".format(ret["domain"], ret["tmid"])
    ads = r.hget(hkey, "{:0>3d}".format(int(ret["chid"])))

    ret["ads"] = json.loads(ads)


def main():
    ret = {
        "domain": "detergame.com",       # 域名，配置参数
        "tmid": "template2",             # 模板，配置参数
        "chid": "3",                     # 渠道，配置参数
        "scheme": "http://",             # http or https
        "categorys": [],    # 分类列表
        "all_list": [],     # 全部内容列表
        "data": {},         # 按分类内容列表
        "ads": {}           # 广告数据
    }

    # 读取配置广告
    get_ads(ret)

    # 读取内容
    get_content(ret)

    random.shuffle(ret["all_list"])

    # 写入Json
    write_json({
        "category": ret["categorys"],
        "all_list": ret["all_list"]
    }, "ret/list.json")
    
    write_json({
        "category": ret["categorys"],
        "data": ret["data"]
    }, "ret/data.json")
    
    


if __name__ == '__main__':
    main()
