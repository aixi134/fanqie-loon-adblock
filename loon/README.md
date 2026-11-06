# Loon 插件 · 直接订阅使用

两个插件都已把脚本指向 GitHub raw 地址，**导入即可用，不需要手动传 js 文件**。

---

## 订阅地址

### 占位版（推荐先试）

```
https://raw.githubusercontent.com/aixi134/fanqie-loon-adblock/main/loon/%E7%95%AA%E8%8C%84%E5%8D%A0%E4%BD%8D.plugin
```

解码后是 `loon/番茄占位.plugin`。广告位保留，文案变成「广告位已屏蔽」。

### REJECT 版

```
https://raw.githubusercontent.com/aixi134/fanqie-loon-adblock/main/loon/%E7%95%AA%E8%8C%84%E5%B0%8F%E8%AF%B4%E5%8E%BB%E5%B9%BF%E5%91%8A.plugin
```

解码后是 `loon/番茄小说去广告.plugin`。广告请求直接拒绝，广告位消失。

### 脚本（插件已自动引用，无需单独导入）

```
https://raw.githubusercontent.com/aixi134/fanqie-loon-adblock/main/loon/adPlaceholder.js
```

---

## 导入步骤

### 1. 装并信任 Loon 根证书

```
Loon → 配置 → 证书管理 → 生成新的 CA 证书 → 安装证书
→ 设置 → 通用 → VPN与设备管理 → 安装描述文件
→ 设置 → 通用 → 关于本机 → 证书信任设置 → 打开 Loon CA 开关
```

### 2. 导入插件

```
Loon → 配置 → 插件 → 右上角 + → 输入上面的订阅地址
→ 确认 → 打开插件开关
```

### 3. 确认 MITM

```
Loon → 配置 → 全局 → MITM 打开
→ 主机名列表应包含：
   ad.zijieapi.com
   reading.snssdk.com
   ib.snssdk.com
```

插件里的 `%APPEND%` 会自动追加这三个，无需手工维护。

### 4. 验证

杀掉番茄小说进程 → 重新打开 → 进书架 → 打开一本书 → 连翻 10 页以上。

打开 Loon 日志，应该能看到 `ad.zijieapi.com` 的请求被标记为「脚本」处理。

---

## 两个版本怎么选

| | 占位版 | REJECT 版 |
|---|---|---|
| 广告位 | 保留，显示「广告位已屏蔽」 | 消失 |
| 出现空白页的可能 | 无 | 有（SDK 兜底分支） |
| 建议 | 先装这个确认链路通 | 占位版验证成功后换这个 |

---

## 想自己改字段

改 GitHub 上的 `loon/adPlaceholder.js`，提交后插件下次加载会自动拿到新版本（Loon 有脚本缓存，必要时在「脚本」页手动刷新缓存）。

要改的常量在文件顶部：

```js
const MAIN = "广告位已屏蔽";   // 标题
const SUB  = "（Loon 替换）";   // 描述
```

字段列表：

- `TITLE_KEYS` —— 会被替换成 `MAIN` 的字段名
- `SUB_KEYS` —— 会被替换成 `SUB`
- `BUTTON_KEYS` —— 会被替换成「查看」

---

## 拦不到的部分

| 广告位 | 原因 |
|---|---|
| 段中内嵌广告（`inline_trigger_ad`） | 物料随正文响应一起下发，没有独立请求 |
| 离线假广告页 | 纯本地行为（`defaultAd`） |
| 部分底部 banner | SSR 预取进正文缓存 |
| QUIC 流量 | TTNet 的 UDP/443 不走 MitM |

正文接口 `/api/novel/book/reader/content/v1`、`/reading/reader/full`、`/reading/reader/batch_full`
**完全不在任何规则和 MITM 主机名里**，不会被影响。
