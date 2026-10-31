# 紫微斗数开源排盘 · 本地部署

上游项目：[Renhuai123/ziwei-doushu](https://github.com/Renhuai123/ziwei-doushu)（Next.js 16 + TypeScript，代码 MIT 协议）

本目录提供：

| 文件 | 用途 |
|---|---|
| `ziwei.sh` | macOS / Linux 一键部署 + 后台运行管理脚本（克隆、安装、构建、启动、停止、更新、日志） |
| `README.md` | 本说明，含 Windows 手动步骤 |

---

## 一、先看清楚：开源版能做什么、不能做什么

| ✅ 能用（纯浏览器计算，不需要任何 API Key） | ❌ 没有（上游不开源） |
|---|---|
| 排盘：十四主星、辅星、四化、大限 / 流年切换 | **断语解读**：`db-analysis.ts` 是占位实现 |
| 真太阳时校正（按出生城市经度）、夏令时判定 | **AI 解读**：`/api/interpret` 接口不存在，页面会提示「开源版不含该接口」 |
| 古籍阅读 + 全文搜索（骨髓赋、全集、全书） | **合盘 AI 分析**：`/api/heming` 同上 |
| 命理百科（14 主星 × 12 宫位）、合盘起盘 | 登录、会员、分享卡片等线上功能 |

一句话：**本地版能把盘排出来、能查古籍，但不会给你"解读"。** 要解读只能用上游的线上站，或自己接大模型实现 `/api/interpret`。

---

## 二、环境要求

- **Node.js ≥ 20.9**（推荐 22 LTS：<https://nodejs.org/zh-cn>）
- **git**（没有也行：在 GitHub 项目页点 Code → Download ZIP，解压后使用）
- 磁盘约 **600 MB**（依赖约 430 MB + 构建产物约 75 MB）
- 不需要数据库，不需要 API Key

---

## 三、macOS / Linux：一条命令

```bash
bash ziwei.sh
```

首次运行会自动：克隆代码到 `~/ziwei-doushu` → `npm ci` 安装锁定版本依赖 → `next build` 生产构建 → 后台启动。
看到 `启动成功 → http://localhost:3000` 后，用浏览器打开即可。关掉终端，服务也会继续在后台运行。

### 常用命令

| 命令 | 作用 |
|---|---|
| `bash ziwei.sh` | 一键部署并后台启动（已在运行则只显示状态） |
| `bash ziwei.sh status` | 是否在运行、首页是否正常 |
| `bash ziwei.sh stop` | 停止 |
| `bash ziwei.sh restart` | 重启 |
| `bash ziwei.sh logs` / `logs -f` | 看日志 / 持续跟踪日志 |
| `bash ziwei.sh update` | 拉取上游最新代码 → 重新安装构建 → 重启 |
| `bash ziwei.sh check` | 跑上游自带的类型检查 + 排盘回归测试 |
| `bash ziwei.sh help` | 帮助 |

### 可选环境变量（写在命令前面）

| 变量 | 默认值 | 说明 |
|---|---|---|
| `ZIWEI_DIR` | `~/ziwei-doushu` | 代码目录 |
| `PORT` | `3000` | 端口，被占用时换一个，如 `PORT=3001 bash ziwei.sh` |
| `HOST` | `127.0.0.1` | 只允许本机访问；改成 `0.0.0.0` 允许同一 Wi-Fi 的手机访问 |
| `NPM_REGISTRY` | 官方源 | 国内下载慢可用 `https://registry.npmmirror.com` |
| `REPO_URL` / `BRANCH` | 上游官方仓库 / `main` | 一般不用改 |

PID 和日志保存在 `~/ziwei-doushu/.run/`（已加入 git 本地忽略，不影响后续 `update`）。

---

## 四、Windows：在「命令提示符（cmd）」里复制执行

> 用 **cmd**，不要用 PowerShell：PowerShell 默认的执行策略经常会拦截 `npm`（报"禁止运行脚本"）。
> 以下是标准的 Node.js 命令，但**没有在 Windows 实机上验证过**，遇到报错把报错原文贴回来即可。

**首次部署**（逐行执行）：

```bat
cd /d %USERPROFILE%
git clone --depth 1 https://github.com/Renhuai123/ziwei-doushu.git
cd ziwei-doushu
set NEXT_TELEMETRY_DISABLED=1
npm ci --no-audit --no-fund
npm run build
start "ziwei" /min cmd /c "npm start -- -H 127.0.0.1 > server.log 2>&1"
timeout /t 5 >nul & start http://localhost:3000
```

- 服务在任务栏里一个**最小化的 "ziwei" 窗口**中运行；**关掉这个窗口 = 停止服务**。
- 以后再启动，只需执行：

  ```bat
  cd /d %USERPROFILE%\ziwei-doushu
  start "ziwei" /min cmd /c "npm start -- -H 127.0.0.1 > server.log 2>&1"
  ```

- 国内下载慢：把 `npm ci ...` 换成 `npm ci --no-audit --no-fund --registry=https://registry.npmmirror.com`
- 更新：先关掉 "ziwei" 窗口，再执行 `git pull`、`npm ci --no-audit --no-fund`、`npm run build`，然后按上面的方式启动。

---

## 五、常见问题

| 现象 | 原因 / 处理 |
|---|---|
| `端口 3000 已被占用` | 换端口：`PORT=3001 bash ziwei.sh` |
| `git clone` 失败 / 很慢 | 访问 GitHub 的网络问题。改用 Download ZIP，解压到 `~/ziwei-doushu`（保证该目录下**直接**就是 `package.json`），再运行 `bash ziwei.sh` |
| `npm ci` 很慢或超时 | `NPM_REGISTRY=https://registry.npmmirror.com bash ziwei.sh update` |
| 首页弹出「致正在使用这个平台的你」 | 上游自带的公告弹窗，点「我知道了」即可 |
| 解读区显示「开源版不含 AI 解读接口」 | 正常，见第一节：上游开源版就没有解读 |
| 浏览器控制台有 `/_vercel/insights/script.js` 404 | Vercel 的统计脚本，只在部署到 Vercel 时存在，不影响使用 |

---

## 六、验证记录（2026-10-31，云端 Linux 容器）

| 项目 | 结果 |
|---|---|
| 上游版本 | commit `495b79e`（main） |
| 运行环境 | Node.js 22.23.4 / npm 10.9.9 / Next.js 16.3.8 |
| `npm ci` | ✅ 184 个包，依赖全部来自 registry.npmjs.org |
| `npm run typecheck` | ✅ 通过 |
| `npm test`（10 组排盘回归） | ✅ 全部通过 |
| `next build` | ✅ 37 个页面 |
| 路由检查 | ✅ `/` `/chart` `/heming` `/knowledge` `/library` `/library/search` 等均 200，未知路径 404 |
| 浏览器实测 | ✅ 1990-06-15 12:00、江西南昌、女 → 起盘成功（命宫戊子：武曲化权 + 天府），无前端运行时错误 |
| 脚本测试 | ✅ 全新目录一键部署（约 35 秒）、start / stop / restart / status / logs / update、端口占用拦截、目录冲突拦截、`HOST=0.0.0.0` 局域网访问 |
