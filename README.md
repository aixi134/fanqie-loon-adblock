# 番茄小说 iOS 广告分析 + Loon 去广告方案

对番茄小说 iOS 7.4.1（`com.dragon.read`）的阅读页广告链路做的逆向分析，以及在**不改 App**的前提下用 Loon 做广告干预的落地方案。

> 结论：自签/重签这条路走不通（正文会加载失败）；Loon 网络层方案可用，且不会破坏正文。

---

## 阅读页广告是什么形态

阅读页的广告**不是网页广告位**，而是阅读器 SDK 在分页阶段把**整页广告卡片插进正文序列**，加上穿山甲联盟的真实物料。

| 广告位 | 触发点 |
|---|---|
| 阅读流插页广告（主形态） | `SSReadingAdManager(Mannor) mannorReaderFeedAd…` |
| 底部 Banner | `SSReadingAdManager(BottomBannerMannor)` |
| 章末商品卡/游戏卡 | `SSReadingAdManager(ChapterEndAd)` |
| 章前品牌广告 | `SSReadingAdManager(ChapterFront)` / `(BrandTopView)` |
| Sati 程序化插页 | `SSReadingAdManager(SatiAdInsert)` |
| 上下滑模式吸顶广告 | `SSReadingAdManager(ScrollAd)` |
| 段中内嵌广告 | `SSReaderAttachmentAdManager`（`inline_trigger_ad`） |
| 离线假广告页 | `SSReadingAdManager(defaultAd)` |

广告请求路径：

```
ad.zijieapi.com/api/ad/v1/banner/          阅读流 banner
ad.zijieapi.com/api/ad/v1/inspire/         激励广告
ad.zijieapi.com/api/ad/v1/recall_ads/      联盟召回
reading.snssdk.com/reading/commerceapi/chapter_end/resource   章末卡
reading.snssdk.com/reading/reader/banner/mget                 底部 banner
reading.snssdk.com/reading/reader/recommend/*                 书末推荐
```

详细分析见 [分析报告.md](分析报告.md)。

---

## 为什么域名级 hosts / adblock 不管用

1. 广告和业务共用 `ad.zijieapi.com` / `reading.snssdk.com` / `is.snssdk.com`
2. TTNet 内置 **HTTPDNS + QUIC**，不走系统 DNS，hosts 拦不到
3. 阅读页广告是原生 Lynx 渲染，WebView 的 adblock 规则（App 自带 `adblock_rulelist.json`）完全不适用
4. 拦了广告请求，SDK 会走 `defaultAd` 兜底，出现空白/假广告页

---

## 走过的弯路：自签

详细的失败记录：

- [证书与重签评估.md](证书与重签评估.md) —— 企业证书可用性评估
- [自签操作手册.md](自签操作手册.md) —— 重签流程
- [自签失败结论.md](自签失败结论.md) —— 对照组实验结论
- [正文失败定位.md](正文失败定位.md) —— 根因分析

**核心结论**：重签改了 Bundle ID / Team 并丢掉 App Groups 之后，正文接口 `/api/novel/book/reader/content/v1`
拿不到解密 key（`/reading/crypt/registerkey`），正文永远是空白。
书架、评论正常，只有正文失败——这是正文独有的加密链路造成的。

`tweak/` 里的工具仍可用于其他场景，但用在番茄上不可行。

---

## 推荐方案：Loon

两个插件，二选一：

| 插件 | 做法 | 特点 |
|---|---|---|
| [loon/番茄小说去广告.plugin](loon/番茄小说去广告.plugin) | 按路径 REJECT | 广告位彻底消失，可能触发兜底空白 |
| [loon/番茄占位.plugin](loon/番茄占位.plugin) | 改写返回文案 | 广告位保留，显示「广告位已屏蔽」，零风险 |

说明文档：

- [loon/说明.md](loon/说明.md) —— REJECT 版安装与验证
- [loon/占位方案说明.md](loon/占位方案说明.md) —— 占位版与字段说明

### 安装要点

1. 手机装**官方版**（App Store），不要用自签版
2. Loon 装根证书 → **设置 → 通用 → 关于本机 → 证书信任设置** 打开开关
3. 导入插件，确认 `[MITM] hostname` 含 `ad.zijieapi.com, reading.snssdk.com`
4. 打开 App 翻页验证

### 拦不到的部分

| 广告位 | 原因 |
|---|---|
| 段中内嵌广告（`inline_trigger_ad`） | 物料随正文一起下发，无独立请求 |
| 离线假广告页 | 纯本地行为 |
| 部分底部 banner | SSR 预取进正文 ADM 缓存 |
| QUIC 流量 | TTNet 走 UDP/443，MitM 支持有限 |

---

## 仓库结构

```
.
├── 分析报告.md              阅读页广告形态与链路
├── 正文失败定位.md          自签后正文失败根因
├── 自签失败结论.md          对照组实验结论
├── 自签操作手册.md          重签流程（存档）
├── 证书与重签评估.md        企业证书评估（存档）
├── loon/
│   ├── 番茄小说去广告.plugin  REJECT 版
│   ├── 番茄占位.plugin        占位版
│   ├── adPlaceholder.js       占位改写脚本
│   ├── 说明.md
│   └── 占位方案说明.md
└── tweak/                   重签工具链（存档，不建议用于番茄）
    ├── NoAd.m / NoAd.dylib
    ├── patch_loadcmd.py
    ├── patch_bundles.py
    ├── gen_entitlements.py
    ├── resign.sh
    ├── selfsign_personal.sh
    ├── renew.sh
    └── build_signed.sh
```

---

## 说明

- 本仓库不含任何 App 二进制、证书、描述文件或账号凭据
- 分析基于 `strings` 与 `otool` 对未加壳 arm64 二进制的静态读取
- 所有结论都可复现：见各文档中标注的行号（对应本地 `reading_strings.txt`）
- 仅供个人学习与本地网络调试使用
