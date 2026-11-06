/*
 * 番茄小说 —— 广告内容改写成占位提示（Loon 版）
 *
 * 不打 REJECT：请求照常发、照常回，阅读器照常排版，
 * 只把广告条目里的文案字段换成「广告位已屏蔽」。
 *
 * 为什么不删物料：广告卡片由 Lynx 运行时渲染，
 * 删字段/改结构会导致卡片渲染空白甚至崩溃；改字符串只影响文字节点。
 */
const MAIN = "广告位已屏蔽";
const SUB  = "（Loon 替换）";

const TITLE_KEYS = [
  "ad_title", "adtitle", "title", "brand_name", "brandname",
  "app_name", "appname", "app_title", "apptitle", "advertiser_name"
];

const SUB_KEYS = [
  "sub_title", "subtitle", "desc", "description", "ad_description",
  "slogan", "ad_slogan", "sellingtag", "selling_tag", "markettag",
  "market_tag", "recommend_reason", "recommend_text", "ad_source"
];

const BUTTON_KEYS = [
  "button_text", "buttontext", "ad_buttontext", "cta_text", "ctatext",
  "download_text", "action_text"
];

function kindOf(key) {
  var k = key.toLowerCase();
  if (TITLE_KEYS.indexOf(k) >= 0) return "title";
  if (BUTTON_KEYS.indexOf(k) >= 0) return "button";
  if (SUB_KEYS.indexOf(k) >= 0) return "sub";
  return null;
}

function walk(node, depth) {
  if (depth > 14 || node === null || typeof node !== "object") return;
  if (Array.isArray(node)) {
    for (var i = 0; i < node.length; i++) walk(node[i], depth + 1);
    return;
  }
  var keys = Object.keys(node);
  for (var j = 0; j < keys.length; j++) {
    var key = keys[j];
    var val = node[key];
    if (typeof val === "string") {
      var kind = kindOf(key);
      if (!kind) continue;
      if (!val.trim()) continue;
      if (val === MAIN || val === SUB || val === "查看") continue;
      node[key] = kind === "title" ? MAIN : (kind === "button" ? "查看" : SUB);
    } else {
      walk(val, depth + 1);
    }
  }
}

var body = $response.body;
if (!body) {
  $done({});
} else {
  try {
    var json = JSON.parse(body);
    walk(json, 0);
    $done({ body: JSON.stringify(json) });
  } catch (e) {
    $done({});
  }
}
