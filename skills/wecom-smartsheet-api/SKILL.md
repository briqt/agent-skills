---
name: wecom-smartsheet-api
description: 通过后端 HTTP 接口直接读取企业微信智能表格数据，无需浏览器 JS 内存操作。Cookie 从已登录浏览器自动提取或手动提供。使用场景：(1) 脱离浏览器读取表格数据 (2) 批量导出 (3) 定时任务抓取 (4) 与其他系统集成。触发词：企微API、smartsheet api、后端接口、直接请求、批量导出。前置条件：需要企微文档的 Cookie（从已登录浏览器提取或手动提供）。
---

# 企业微信智能表格 — 后端 API（只读）

通过 `dop-api/opendoc` 接口直接获取智能表格数据，不依赖浏览器 JS 内存。

## Cookie 获取

优先级：自动提取 > 环境变量 > 命令行参数

### 方式一：从浏览器自动提取（推荐）

前提：浏览器已登录企微文档（任意一个企微文档页面打开即可）。

```javascript
// 在 browser evaluate 中执行
() => document.cookie
```

### 方式二：环境变量

```bash
export WECOM_COOKIE="utype=ww; TOK=xxx; wedoc_sid=xxx; wedoc_skey=xxx; wedoc_ticket=xxx; ..."
```

### 方式三：命令行参数

```bash
node scripts/fetch-smartsheet.mjs <url> "<cookie-string>"
```

### 方式四：用户手动提供

引导用户在浏览器中获取 Cookie：

1. 用浏览器打开任意企微文档页面（如智能表格）
2. 按 F12 打开开发者工具
3. 切换到「控制台 / Console」标签
4. 输入 `document.cookie` 回车
5. 复制输出的整段文字

或者通过「网络 / Network」面板：
1. 打开开发者工具 → Network 标签
2. 刷新页面
3. 点击任意一个 `doc.weixin.qq.com` 的请求
4. 在 Headers 中找到 `Cookie` 字段，复制完整值

### 关键 Cookie 字段

| 字段 | 用途 | 必需 |
|------|------|------|
| `wedoc_sid` | 会话 ID | ✅ |
| `wedoc_skey` | 会话密钥 | ✅ |
| `wedoc_ticket` | 认证票据 | ✅ |
| `TOK` | XSRF token | ✅ |
| `tdoc_uid` | 用户 ID | ✅ |
| `utype` | 用户类型（ww=企业微信） | 建议 |
| `wedoc_sids` | 多会话标识 | 建议 |

最简单的做法是复制完整的 `document.cookie` 输出，不需要手动挑选字段。

Cookie 有效期取决于企微登录态，通常数小时到数天。过期表现为接口返回登录页或 403。

## 使用

```bash
# 读取表格（自动分页）
node scripts/fetch-smartsheet.mjs <smartsheet-url>

# 只读前 10 行
WECOM_ENDROW=10 node scripts/fetch-smartsheet.mjs <url>

# 调试模式（输出原始 JSON）
DEBUG=1 node scripts/fetch-smartsheet.mjs <url>
```

### 环境变量

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `WECOM_COOKIE` | - | Cookie 字符串 |
| `WECOM_STARTROW` | 0 | 起始行 |
| `WECOM_ENDROW` | - | 结束行（设置后只请求单页） |
| `WECOM_PAGE_SIZE` | 500 | 自动分页大小 |

## 接口细节

核心接口：`GET https://doc.weixin.qq.com/dop-api/opendoc`

数据格式详见 [references/snapshot-format.md](references/snapshot-format.md)。
