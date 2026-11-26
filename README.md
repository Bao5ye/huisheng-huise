# 绘声绘色 · Huisheng Huise

**儿童 AI 绘本工坊 · AI Picture-Book Workshop for Children**

[中文](#中文说明) · [English](#english)

---

## 中文说明

面向公共图书馆儿童阅读推广的多智能体 AI 绘本生成应用。“绘”是 AI 绘制的插画，“声”是真人感的故事朗读。它为不同读者提供分层分众的界面，也能以较低成本用于图书馆的亲子阅读活动。

### 四类使用者

| 角色 | 界面特点 |
|---|---|
| 图书馆员 | 专业模式，可细调年龄分级、主题、画风、色调、镜头与人物一致性 |
| 父母 | 简洁向导，几步生成亲子共读绘本 |
| 爷爷奶奶 | 大字、高对比、语音提示与慢速朗读的适老设计 |
| 孩子 | 图画按钮加语音，不识字也能用 |

### 创作流程

选择身份 → 需求采集 → 故事策划梗概 → 完整故事（由使用者确认）→ 角色设定与分镜插画 → 阅读、朗读与导读问题

### 智能体与模型

- **文字**：DeepSeek，负责策划、写作、文学编辑、审校、分镜导演和共读导读
- **插画**：火山方舟 Seedream（5.0 Flash / 5.5 / 4.0）或 MiniMax。先生成角色三视图，再以三视图和第 1 页作为参考图，保持各页人物一致
- **朗读**：腾讯云超自然大模型 2.0 音色，提供讲故事、童声、方言等多种音色；没有后台服务时，退回设备自带语音

### 三种部署方式

| 目录 | 说明 |
|---|---|
| `windows/` | Windows 11 本地版。双击 `Install.bat` 安装，密钥经 Windows DPAPI 加密保存在本机 |
| `static/` | 腾讯云静态网站托管版。`static-site/` 上传到静态托管，`cloud-function/thf-proxy/` 部署为云函数代理 |
| `node-server/` | Node.js 服务端版（可用 Docker），通过环境变量配置密钥 |

三个目录里的 `index.html` 是同一份页面，打开后会按运行环境自动识别模式。各目录内有详细的使用说明。

### 密钥安全

仓库中不包含任何 API 密钥。请在本地版的“设置”里填写密钥，或将其配置为服务器、云函数的环境变量。腾讯云 SecretKey 每次请求都要用来签名，切勿放进网页。

### 授权协议

本项目采用 **[PolyForm Noncommercial License 1.0.0](LICENSE.md)**。这是源码可见的非商业许可，不属于 OSI 认定的开源协议。

- ✅ 个人学习、研究、测试、兴趣项目等非商业用途
- ✅ 公益组织、教育机构、公共研究机构、公共图书馆、政府机构使用，不论经费来源
- ✅ 在非商业用途内修改和再分发，须保留 `LICENSE.md` 与 `NOTICE` 中的声明
- ❌ 任何商业用途，包括出售本软件、用于收费产品或服务、以营利为目的的运营

如需商业授权，请通过 GitHub 与版权人 [Bao5ye](https://github.com/Bao5ye) 联系。

生成的文字与插图由人工智能完成，用于阅读推广前请由馆员或家长审阅。

---

## English

A multi-agent AI picture-book generator built for children's reading promotion in public libraries. *Huisheng Huise* (绘声绘色, "vivid in picture and sound") pairs AI-drawn illustrations with natural-sounding narration. It offers interfaces tailored to different readers and is designed for low-cost use in library family-reading programs.

### Four kinds of users

| Role | Interface |
|---|---|
| Librarians | Professional mode with fine control over age level, theme, art style, palette, camera framing and character consistency |
| Parents | A simple guided flow that produces a book for shared reading in a few steps |
| Grandparents | Senior-friendly design: large type, high contrast, voice prompts and slower narration |
| Children | Picture buttons and voice, usable before a child can read |

### Workflow

Choose a role → describe what you want → story outline → full story (confirmed by the user) → character sheet and illustrated pages → reading, narration and discussion questions

### Agents and models

- **Text**: DeepSeek, for planning, writing, literary editing, review, page direction and reading guides
- **Illustration**: Volcano Engine Seedream (5.0 Flash / 5.5 / 4.0) or MiniMax. A character turnaround sheet is drawn first, then the sheet and page 1 serve as references so characters stay consistent across pages
- **Narration**: Tencent Cloud natural-voice 2.0 TTS with storytelling, child and dialect voices; falls back to the device's built-in voice when no backend is available

### Three ways to deploy

| Folder | Description |
|---|---|
| `windows/` | Windows 11 local app. Double-click `Install.bat`; API keys are encrypted with Windows DPAPI and stored on the machine |
| `static/` | Tencent Cloud static website hosting. Upload `static-site/` to static hosting and deploy `cloud-function/thf-proxy/` as the proxy function |
| `node-server/` | Node.js server (Docker supported); keys are set as environment variables |

The `index.html` in all three folders is the same page; it detects its environment and switches mode automatically. Each folder has its own instructions (in Chinese).

### Key security

This repository contains no API keys. Enter keys in the local app's Settings, or set them as server or cloud-function environment variables. The Tencent Cloud SecretKey signs every request and must never be placed in a web page.

### License

Licensed under the **[PolyForm Noncommercial License 1.0.0](LICENSE.md)**, a source-available noncommercial license (not an OSI-approved open-source license).

- ✅ Personal study, research, testing, hobby projects and other noncommercial purposes
- ✅ Use by charitable organizations, educational institutions, public research organizations, public libraries and government institutions, regardless of funding source
- ✅ Modification and redistribution for noncommercial purposes, keeping the notices in `LICENSE.md` and `NOTICE`
- ❌ Any commercial use, including selling the software, using it in paid products or services, or for-profit operation

For commercial licensing, please contact the copyright holder, [Bao5ye](https://github.com/Bao5ye), via GitHub.

Text and illustrations are AI-generated; please have a librarian or parent review them before use with children.

---

Copyright (c) 2026 [Bao5ye](https://github.com/Bao5ye)
