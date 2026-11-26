# 绘声绘色 网页版 部署说明

网页版和 Windows 本地版使用**同一个页面**，功能完全一致；区别只在于密钥放在哪里：

| | Windows 本地版 | 网页版 |
|---|---|---|
| 适合场景 | 馆员电脑、活动现场一体机 | 读者用手机或平板扫码使用、多台设备共用 |
| 密钥 | 用户在页面里填写，加密存在本机 | 管理员写在服务器环境变量里，读者看不到 |
| 访问控制 | 只有本机能访问 | 可设访问码，按 IP 限流 |

> 注意：网页版需要一个能运行程序的服务器（例如腾讯云**云托管**）。纯静态托管无法隐藏密钥，不能用来部署网页版。

## 一、腾讯云云托管（推荐）

1. 把本文件夹整体上传（或推送到代码仓库），云托管会自动识别 `Dockerfile`。
2. 服务端口填 `8080`。
3. 在“环境变量”里填写：

| 变量 | 是否必填 | 说明 |
|---|---|---|
| `DEEPSEEK_API_KEY` | 必填 | DeepSeek 密钥，在 platform.deepseek.com 创建 |
| `ARK_API_KEY` | 推荐 | 火山方舟 API Key，用 Seedream 画图（默认 5.0 Flash，页面设置里可改选 5.5 或其他编号），角色一致性更好 |
| `MINIMAX_API_KEY` | 可选 | MiniMax 按量付费密钥；与 `ARK_API_KEY` 至少填一个 |
| `TENCENT_SECRET_ID` / `TENCENT_SECRET_KEY` | 可选 | 腾讯云语音合成，用于朗读；可用赛珍珠讲解机器人的语音子账号 |
| `DEEPSEEK_WRITE_MODEL` | 可选 | 写故事用的模型，默认 `deepseek-v4-pro` |
| `ACCESS_CODE` | 建议填 | 访问码。读者打开网页需先输入，防止陌生人消耗额度 |
| `RATE_LIMIT_PER_HOUR` | 可选 | 每个 IP 每小时最多请求次数，默认 600（一本 8 页绘本约 20 次） |
| `DEEPSEEK_MODEL` | 可选 | 默认文字模型，默认 `deepseek-v4-flash` |

4. 部署完成后访问分配的域名即可。健康检查路径：`/healthz`。

## 二、任意一台装有 Node.js 18+ 的服务器

```bash
cd web
DEEPSEEK_API_KEY=sk-xxx MINIMAX_API_KEY=xxx ACCESS_CODE=reading2026 node server.js
```

Windows 服务器上（PowerShell）：

```powershell
$env:DEEPSEEK_API_KEY="sk-xxx"; $env:MINIMAX_API_KEY="xxx"; $env:ACCESS_CODE="reading2026"; node server.js
```

默认端口 8080，可用 `PORT` 改。正式对外服务请在前面加 HTTPS（云托管自带）。浏览器的语音输入只在 HTTPS 或 localhost 下可用。

## 三、更新页面

只需替换 `public/index.html`，重启服务即可。Windows 版里的 `app/web/index.html` 是同一个文件。

## 接口说明（供维护参考）

| 路径 | 作用 |
|---|---|
| `GET /api/status` | 返回模式、两把密钥是否已配置、是否需要访问码 |
| `POST /api/deepseek/chat/completions` | 转发到 DeepSeek，模型只允许白名单内的 |
| `POST /api/minimax/image_generation` | 转发到 MiniMax，固定 `image-01`、每次 1 张 |
| `GET /api/test` | 测试 DeepSeek 密钥 |
