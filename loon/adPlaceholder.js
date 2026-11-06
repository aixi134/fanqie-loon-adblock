/*
 * 番茄小说 —— 广告内容改写成占位提示
 *
 * 不打 REJECT：请求照常发、照常回，阅读器照常排版，
 * 只把广告条目的文案字段换成「广告位已屏蔽」。
 *
 * 为什么只改文案不动素材：
 *   广告卡片由 Lynx 运行时渲染，删物料/改结构会导致卡片渲染成空白甚至崩溃；
 *   改字符串只影响文字节点，布局保持不变。
 *
 * 已核对二进制里的字段名（analysis/reading_strings.txt）：
 *   ad_title / adTitle / title / brand_name / brandName / app_name / appName
 *   button_text / buttonText / ad_buttonText / cta_text / ctaText
 *   sellingTag / marketTag / recommend_reason / recommend_text
 */

const MAIN = "广告位已屏蔽";
const SUB  = "（Loon 替换）";

const TITLE_KEYS = new Set([
  "ad_title", "adtile", "adtitle", "title", "brand_name", "brandname",
  "app_name", "appname", "app_title", "apptitle", "advertiser_name",
]);

const SUB_KEYS = new Set([
  "sub_title", "subtitle", "desc", "description", "ad_description",
  "slogan", "ad_slogan", "sellingtag", "selling_tag", "markettag",
  "market_tag", "recommend_reason", "recommend_text", "ad_source",
]);

const BUTTON_KEYS = new Set([
  "button_text", "buttontext", "ad_buttontext", "cta_text", "ctatext",
  "download_text", "action_text",
]);

function classify(key) {
  const k = key.toLowerCase();
  if (TITLE_KEYS.has(k)) return "title";
  if (BUTTON_KEYS.has(k)) return "button";
  if (SUB_KEYS.has(k)) return "sub";
  return null;
}

function walk(node, depth) {
  if (depth > 14 || node === null || typeof node !== "object") return;
  if (Array.isArray(node)) {
    for (const item of node) walk(item, depth + 1);
    return;
  }
  for (const key of Object.keys(node)) {
    const val = node[key];
    if (typeof val === "string") {
      const kind = classify(key);
      if (!kind) continue;
      if (!val.trim()) continue;
      if (val === MAIN || val === SUB || val === "查看") continue;
      node[key] = kind === "title" ? MAIN : kind === "button" ? "查看" : SUB;
    } else {
      walk(val, depth + 1);
    }
  }
}

const body = $response.body;
if (!body) {
  $done({});
} else {
  try {
    const json = JSON.parse(body);
    walk(json, 0);
    $done({ body: JSON.stringify(json) });
  } catch (e) {
    $done({});
  }
}
