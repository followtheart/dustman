# v0.4.0 发版 checklist 与灰度计划

> M6 收尾。本文档列出从「代码完成」到「公开发布」之间的全部步骤。

---

## 1. 发版前 24h 必做

### 1.1 代码冻结

- [ ] dustman main 分支 freeze（仅接受 P0 bugfix）
- [ ] dustman-cloud main 分支 freeze
- [ ] tag `v0.4.0-rc1`（双仓库同步）

### 1.2 双仓库自检

dustman：
- [ ] `flutter analyze` 0 error / 0 warning
- [ ] `flutter test` 全绿
- [ ] Community release build 通过 CI strings 检查（37/37 字串缺席）
- [ ] Pro release build 含全部 FileClaw 字串

dustman-cloud：
- [ ] `pytest` 全绿（≥ 81 tests）
- [ ] `ruff check . && ruff format --check .` 全绿
- [ ] `alembic upgrade head --sql` 离线 SQL 渲染无异常
- [ ] docker image 体积 < 200 MB

### 1.3 文档与协议

- [ ] [V0_4_PLAN.md](V0_4_PLAN.md) 各里程碑勾选完成
- [ ] [SECURITY_AUDIT_V0_4.md](SECURITY_AUDIT_V0_4.md) P0 项无 ❌
- [ ] [DEPLOY.md](../../dustman-cloud/docs/DEPLOY.md) §3 必填 checklist 已 review
- [ ] README 双版本说明 + Pro 功能介绍可读
- [ ] 隐私政策（不在本期，但内测期临时贴一份「v0.4 beta，数据不外传，可联系作者注销」）

### 1.4 配置与密钥

云侧生产环境 `.env`：
- [ ] `JWT_SECRET` 已生成强随机串（≥ 64 字符 urlsafe）
- [ ] `APP_ENV=production`
- [ ] `DATABASE_URL` 指向独立 postgres，密码 ≥ 24 位
- [ ] `FILECLAW_PUBLIC_BASE_URL` = 实际域名
- [ ] SMTP（腾讯云 / 阿里云 SES）已配置，发测试邮件确认
- [ ] 阿里云短信签名 + 模板审核通过
- [ ] 微信 / 支付宝商户号若已签约则配置；未签约则 P0：在 production 模式下 stub provider 拒绝下单（待补代码）

---

## 2. 内测灰度计划

### 2.1 时间线

| 阶段 | 时长 | 用户量 | 准入 |
|---|---|---|---|
| **Alpha**（内部） | 3 天 | 5 人（项目组） | 直接邀请 |
| **Beta**（封闭） | 1 周 | 50 人 | 微信群定向邀请 + 临时邀请码 |
| **Gamma**（开放） | 1 周 | 200 人 | QQ 群 + 官网公开 + 限注册量 |
| **GA** | — | 全量 | 上述全部通过后 |

### 2.2 Alpha 阶段验收

每位内测者跑完以下流程并填问卷：

- [ ] 用邮箱注册 → 收码 → 激活
- [ ] 用手机号注册 → 收 SMS → 激活
- [ ] 用 SMS OTP 登录（无密码路径）
- [ ] 找回密码（任一身份）
- [ ] 6 个 ✦ 入口各点一次，确认 stub LLM 返回；带写工具的点 1 次拒绝 + 1 次允许
- [ ] 开通 ¥0.01 Pro 月付（stub 模式 5s 自动 paid）
- [ ] 余额耗尽场景（手动 SQL 把 used 改大）→ 创建 session 返 402
- [ ] 退出登录 → 重新登录 → 余额 / 套餐保留
- [ ] 切换 Community 二进制 → 账户 / 会员侧栏项消失、所有 ✦ 消失

### 2.3 Beta 阶段验收

Alpha 全过 + 加：

- [ ] 5 人同时支付 → 订单互不串号
- [ ] LLM 真实调用（开 ANTHROPIC_API_KEY） 走 10 次会话验质量
- [ ] 短信发送量监控（防 SDK 漏配置烧钱）
- [ ] 日活留存 D1 / D3 / D7 数据足够支撑公开

### 2.4 Gamma 阶段验收

Beta 全过 + 加：

- [ ] 微信支付沙箱 / 生产真扫码联调 ≥ 5 笔
- [ ] 支付宝沙箱 / 生产真扫码联调 ≥ 5 笔
- [ ] webhook 验签实际触发并 mark paid 路径走通
- [ ] 渗透测试（OWASP ZAP / Burp Suite 扫一遍 /auth /billing /ai 路由）
- [ ] 压测（locust 模拟 100 并发持续 10 min，p99 < 500ms）

---

## 3. 发版操作 SOP

### 3.1 双仓库发版顺序

**必须云侧先发**：客户端依赖云侧接口；云侧先升级，老客户端依然能工作（接口兼容）。

```
T-0       云侧 docker compose up -d --build  → 短暂下线（< 30s）
T+5min    验证 /health 正常 + 抽样测试 1 个完整流程
T+10min   端侧上传 Community + Pro 安装包到 GitHub Releases
T+15min   发布公告（QQ 群、Twitter、用户邮件）
T+30min   开始监控告警面板，紧盯异常
```

### 3.2 端侧产物

`tag v0.4.0` 后 CI 自动产出：
- `dustman-community-v0.4.0-windows-x64.zip`
- `dustman-pro-v0.4.0-windows-x64.zip`
- （未来）MSIX 安装包

zip 内目录结构：
```
dustman-{edition}/
├── dustman.exe
├── flutter_windows.dll
└── data/
    ├── app.so
    ├── flutter_assets/
    └── icudtl.dat
```

绿色版用户：直接解压 + 同目录建 `portable.flag` 空文件。
普通用户：未来上 MSIX，本期先 zip。

### 3.3 GitHub Release 文案模板

```markdown
# Dustman v0.4.0

## 重要：从本版本起分两个发行版次

- **Community**（推荐多数用户）：v0.3 全部能力，默认不联网、无需注册
- **Pro**：在 Community 基础上叠加 FileClaw AI 操作建议、账户、会员

## 新增

- FileClaw AI 操作建议（Pro 版）：6 个功能页都接入了 ✦ 按钮…
- 双轨账户身份（邮箱 + 手机号）（Pro 版）
- 测试期会员套餐 ¥0.01（Pro 版）
- 命令行 / GUI 一致性增强

## 已知问题

…

## 安装

直接下载下方对应版本的 zip 文件，解压即用。
```

---

## 4. 回滚 SOP

### 4.1 端侧回滚

老版本下载链接（GitHub Releases v0.3.0）保持可访问。用户重装即可降级。**Pro 版本回到 Community 版，账户文件 auth.bin 会被忽略，不影响其它设置。**

### 4.2 云侧回滚

按 [DEPLOY.md §8](../../dustman-cloud/docs/DEPLOY.md) 操作：
1. `git checkout v0.3.x` （v0.3 时云侧不存在，所以实际是停服）
2. 若 schema 不兼容老端，端侧也降级（按 4.1）

### 4.3 紧急停服

```bash
docker compose down   # 立即停服
```

云侧停服后，Pro 端侧自动进入离线降级：v0.3 全部功能照常使用，仅 AI ✦ 入口提示「云端不可用」。

---

## 5. 内测期紧急联系方式

- 项目组 oncall（本期由作者一人轮值）
- QQ 群（参见 README 底部二维码）
- GitHub Issues（公开）

报障流程：用户在 QQ 群 / Issues 报障 → 作者 30 分钟内响应 → 6 小时内定位 → 24 小时内修复或回滚。
