# Dustman v0.4.0 规划 — FileClaw 端云架构

> 对应 [REQUIREMENTS.md §3.4](REQUIREMENTS.md) v0.4 阶段。
> 本期引入"端云协同"的 AI 能力子系统 **FileClaw**：云侧负责任务编排与计费，
> 端侧负责工具执行与本地数据访问。沿用 [ARCHITECTURE.md](ARCHITECTURE.md)
> 三层结构，FileClaw 作为 data 层的一个新模块加入，并在 presentation 层新增
> "AI 分析" 入口与"账户/会员"入口。

---

## 1. 目标与非目标

### 1.1 目标
- 在不破坏 v0.3 "默认离线、无注册" 体验的前提下，为愿意付费的用户提供
  **AI 辅助分析与操作建议**能力（解释注册表项含义、判断文件是否可删、解读启动项归属等）。
- 端侧任何 AI 入口都是**可选**的：未登录用户继续使用全部既有功能。
- 云侧只接收"经过用户确认的最小必要上下文"（路径、键名、元数据），
  **不上传文件内容**，符合 [REQUIREMENTS.md §5](REQUIREMENTS.md) 非目标承诺。
- 端云分离明确：云侧无文件系统/注册表访问能力，所有"动作"由端侧本地执行；
  云侧只产出**"建议 + 调用计划"，不做"代执行"**——所有删除/修改类工具都需端侧用户二次确认。
- **双版本发行**：社区版（Community）保持 v0.3 全部能力、不含 FileClaw 代码；
  付费版（Pro）增量包含 FileClaw 与账户/会员入口。

### 1.2 非目标（本期不做）
- 不做端侧自主联网爬虫；所有联网调用收敛到 FileClaw API。
- 不做"云端代清理"——清理动作永远在用户机器本地完成。
- 不引入第三方 SaaS 鉴权（Auth0/Clerk/Supabase 等），自建轻量账户系统即可
  （理由：避免把账号绑定到外部服务，便于自部署）。
- 不做团队/组织账户，本期仅个人账号 + 会员订阅。
- 不做移动端 / Web 端 FileClaw 客户端，仍只服务 Windows 桌面客户端。
- **不接入 Stripe / PayPal 等海外支付**：本期仅微信 + 支付宝，覆盖国内场景；
  海外用户场景在 v0.5+ 评估。

---

## 2. 总体架构

```
                ┌────────────────────────────────────────┐
                │              云侧 (FileClaw Cloud)     │
                │                                        │
   HTTPS/SSE    │  ┌──────────┐   ┌──────────────────┐   │
  ────────────►│  │ Gateway  │──►│  Orchestrator    │   │
                │  │ (FastAPI)│   │  LangGraph+ReAct │   │
                │  └────┬─────┘   └─────────┬────────┘   │
                │       │                   │            │
                │  ┌────▼─────┐   ┌─────────▼────────┐   │
                │  │ Auth /   │   │  Token Meter /   │   │
                │  │ Billing  │   │  LLM Provider    │   │
                │  └────┬─────┘   └─────────┬────────┘   │
                │       │                   │            │
                │  ┌────▼───────────────────▼────────┐   │
                │  │  PostgreSQL  +  Redis           │   │
                │  └─────────────────────────────────┘   │
                └────────────────────────────────────────┘
                                  ▲
                                  │  HTTPS + SSE (JSON)
                                  │  双向：Cloud→Client 下发 tool_call
                                  │        Client→Cloud 回传 tool_result
                                  ▼
                ┌────────────────────────────────────────┐
                │           端侧 (Dustman Desktop)        │
                │                                        │
                │  presentation/                         │
                │   ├── AI 分析入口（注册表/文件/启动项） │
                │   └── 账户/会员页（登录/找回/付费二维码）│
                │                                        │
                │  data/fileclaw/                        │
                │   ├── CloudClient (HTTP+SSE)           │
                │   ├── AuthStore (token 持久化)         │
                │   └── ToolRuntime (本地工具执行)        │
                │        ├── filemcp/                    │
                │        │   ├── list_dir / stat / hash  │
                │        │   ├── read_text_head          │
                │        │   └── safe_delete (走回收站)   │
                │        ├── regmcp/                     │
                │        │   ├── read_key / list_subkeys │
                │        │   └── export_reg / delete_key │
                │        └── procmcp/                    │
                │            ├── list_startup_items      │
                │            └── disable_startup_item    │
                └────────────────────────────────────────┘
```

**关键交互**：端侧发起一次 "分析" 请求 → 云侧 Orchestrator 用 ReAct 循环
推理 → 通过 SSE 下发 `tool_call`（如 `read_key("HKCU\\...\\Run")`）→
端侧 `ToolRuntime` 执行后回传 `tool_result` → 循环直至云侧产出最终建议
→ 端侧渲染。所有工具调用、token 消耗都在云侧记录用于计费与审计。

### 2.1 为什么端云分离

| 选项 | 缺点 |
|---|---|
| 全本地：内嵌小模型 | 端侧分发体积膨胀（几 GB），首次推理慢，且小模型对"注册表项含义"这类长尾知识效果差 |
| 全云端：把文件 / 注册表传到云上 | 违反 [REQUIREMENTS.md §5](REQUIREMENTS.md)，用户隐私不可接受 |
| **端云分离（本方案）** | 工程复杂度上升、首次需要登录；但隐私边界清晰、模型可持续迭代 |

---

## 3. 云侧设计

### 3.1 技术栈（建议）

| 组件 | 选型 | 备注 |
|---|---|---|
| 语言 | Python 3.12 | LangGraph 生态最佳 |
| Web 框架 | FastAPI | 异步、原生 SSE、OpenAPI 自动生成 |
| 编排 | LangGraph + ReAct agent | 节点 = 工具调用/LLM 推理；状态机持久化到 Redis |
| LLM Provider | Claude (Anthropic) 为主，OpenAI 为备 | 通过适配层屏蔽，便于切换 |
| DB | PostgreSQL 16 | 账户、订单、token 流水 |
| 缓存 / 会话 | Redis 7 | 会话状态、限流计数、SSE 心跳 |
| 鉴权 | JWT (access 15min) + Refresh Token (30d，DB 存储可吊销) | 自研，不依赖外部 IdP |
| 支付 | 微信支付 Native（二维码） + 支付宝当面付（二维码） | 端侧扫码即用，无需打开浏览器 |
| 部署 | Docker Compose（单机起步） → K8s（用户量上来再迁） | |
| 邮件 | 腾讯云 SES / AWS SES | 用于找回密码、订单凭证 |

> **决策：云侧使用独立仓库 `dustman-cloud`**，与桌面端 `dustman` 分离。
> 理由：CI/CD 节奏不同、部署生命周期不同、避免把云端密钥误混入桌面端发布物，
> 且便于云侧未来引入团队协作者而不暴露桌面端发布权限。

### 3.2 用户认证模块

#### 3.2.1 注册流程
- 邮箱 + 密码注册，邮件验证码 6 位、5 分钟有效；
- 密码用 Argon2id 哈希（不要 bcrypt，参数：m=64MB, t=3, p=4）；
- 注册成功送 **N 免费 token**（建议 50k，约一次中等分析的额度）用于试用；
- 端侧注册入口：账户页内嵌注册表单，不跳浏览器，避免 OAuth redirect 在桌面端的别扭体验。

#### 3.2.2 登录流程
- 用户名/邮箱 + 密码 → 返回 access_token + refresh_token；
- access_token 放内存，refresh_token 用 Windows DPAPI 加密后落
  `<AppData>\Dustman\auth.bin`（绿色版落 `<exe_dir>\data\auth.bin`）；
- 端侧自动续期：access 过期 → 静默用 refresh 换新；refresh 过期 → 提示重新登录。

#### 3.2.3 找回密码
- 输入注册邮箱 → 发送 6 位数字验证码 → 验证通过后允许重置；
- 重置后**吊销所有 refresh_token**，强制其他设备重新登录。

#### 3.2.4 会员开通（二维码支付）
- 端侧点"开通会员" → 调云侧 `POST /billing/orders` 创建订单 →
  云侧返回 `qrcode_url`（指向二维码图片或 base64）→ 端侧弹窗显示二维码；
- 端侧打开 SSE `/billing/orders/{id}/events` 监听支付状态变化；
- 用户扫码支付 → 第三方支付回调云侧 → 云侧推送 `paid` 事件 → 端侧自动刷新会员状态并关闭弹窗。

| 套餐 | 价格（测试定价） | 月配额 | 说明 |
|---|---|---|---|
| Free | ¥0 | 50k token | 注册即得，仅一次 |
| Pro Monthly | **¥0.01** | 2M token | 个人月付，测试定价 |
| Pro Annual | **¥0.01** | 30M token | 测试定价 |
| Token Pack | **¥0.01** | 1M token | 一次性加油包，测试定价 |

> **价格策略**：v0.4 采用 ¥0.01 测试定价以验证支付通路、用户付费意愿与配额是否合理，
> 不以收入为目标。后续根据 LLM 实际成本与留存数据再定正式价格（v0.5）。
> 所有套餐在订单详情页明确标注 "测试期定价，正式价格待调整"。

### 3.3 Token 计量

- 每次 LLM 调用记录：`user_id, session_id, model, input_tokens, output_tokens, cost_credits, ts`；
- `cost_credits = ceil(input_tokens * IN_RATE + output_tokens * OUT_RATE)`，
  IN/OUT_RATE 按模型在 `provider_rates` 表中维护，便于换模型不改业务代码；
- 用户配额表：`user_quota(user_id, period, allowance, used, reset_at)`；
- 计费 hook 在 LangGraph 的 `on_llm_end` 回调里调用，避免业务代码到处插入；
- 用户余额不足时：
  1. 当前正在运行的任务允许跑完（避免半截结果），
  2. 但禁止新建任务，端侧提示 "本月额度用尽，开通会员或购买加油包"。

### 3.4 任务编排（LangGraph + ReAct）

#### 3.4.1 状态机
```
START → PlanNode → ToolNode ⇄ ReasonNode → FinalizeNode → END
                       ▲           │
                       └───────────┘   (ReAct 循环，最多 N=10 轮)
```

- **PlanNode**：把端侧的 "意图 + 初始上下文" 转成首轮工具调用计划；
- **ToolNode**：把工具调用通过 SSE 推给端侧，等回执（超时 30s）；
- **ReasonNode**：把工具结果喂给 LLM，决定下一步（继续调工具 / 给最终答案）；
- **FinalizeNode**：产出结构化建议（JSON schema，便于端侧渲染卡片）。

#### 3.4.2 工具协议（Cloud→Client）
LangGraph 的 ToolNode 不直接执行，而是把 `ToolCall` 序列化通过 SSE 下推：

```json
{
  "type": "tool_call",
  "call_id": "c_01H...",
  "tool": "regmcp.read_key",
  "args": { "key": "HKCU\\Software\\Foo" },
  "needs_user_consent": false
}
```

端侧执行后回传：
```json
{
  "type": "tool_result",
  "call_id": "c_01H...",
  "ok": true,
  "data": { "values": [...], "subkeys": [...] }
}
```

`needs_user_consent=true` 用于写操作（如 `safe_delete` / `delete_key`），
端侧必须先弹确认对话框，用户拒绝则回 `{"ok": false, "reason": "user_declined"}`。

#### 3.4.3 ReAct 循环安全
- 工具调用次数硬上限（默认 10）防止无限循环；
- 单次会话总 token 硬上限（默认 50k）防止失控烧钱；
- 工具白名单：云侧只允许调用预注册的工具名，端侧也只暴露白名单内的工具；
- 写操作的 `consent` 由端侧二次校验，云侧 `needs_user_consent` 字段仅作 hint。

### 3.5 数据模型（PostgreSQL）

| 表 | 关键字段 |
|---|---|
| `users` | id, email(unique), password_hash, created_at, email_verified_at, status |
| `refresh_tokens` | id, user_id, token_hash, device_label, revoked_at, expires_at |
| `email_codes` | email, code_hash, purpose(register/reset), expires_at, used_at |
| `orders` | id, user_id, sku, amount, currency, status, paid_at, provider_txn_id |
| `subscriptions` | user_id, plan, current_period_start/end, auto_renew, canceled_at |
| `user_quota` | user_id, period(YYYY-MM), allowance, used, reset_at |
| `ai_sessions` | id, user_id, intent, status, tokens_in, tokens_out, started_at, ended_at |
| `ai_tool_calls` | session_id, seq, tool, args_hash, ok, latency_ms |
| `provider_rates` | model, in_rate, out_rate, effective_from |
| `audit_logs` | actor, action, target, ip, ua, ts |

> `ai_tool_calls.args_hash` 而非 args 本身——参数里可能有路径，做哈希入库即可
> 满足审计需求又避免敏感信息长期留存（详见 §6）。

### 3.6 API 概览

| Method | Path | 说明 |
|---|---|---|
| POST | `/auth/register` | 邮箱注册，返回 verify 待处理 |
| POST | `/auth/verify-email` | 提交验证码激活 |
| POST | `/auth/login` | 返回 access + refresh |
| POST | `/auth/refresh` | refresh → 新 access |
| POST | `/auth/logout` | 吊销当前 refresh |
| POST | `/auth/password/forgot` | 发送重置验证码 |
| POST | `/auth/password/reset` | 凭验证码重置 |
| GET  | `/me` | 当前用户 + 会员 + 余额 |
| POST | `/billing/orders` | 创建订单，返回 qrcode |
| GET  | `/billing/orders/{id}` (SSE) | 监听订单状态 |
| POST | `/billing/webhook/{provider}` | 第三方支付回调 |
| POST | `/ai/sessions` | 创建分析会话（intent + 初始 ctx） |
| GET  | `/ai/sessions/{id}/stream` (SSE) | 双向：下发 tool_call / 推送 chunk |
| POST | `/ai/sessions/{id}/tool-result` | 上报工具执行结果 |
| POST | `/ai/sessions/{id}/abort` | 用户主动终止 |

---

## 4. 端侧设计

### 4.1 新增模块

```
lib/
├── data/
│   └── fileclaw/
│       ├── cloud_client.dart          # HTTP + SSE
│       ├── auth_store.dart            # DPAPI 加密的 refresh_token
│       ├── auth_repository.dart       # 登录/注册/找回的 use case 封装
│       ├── billing_repository.dart    # 订单 / 二维码 / 会员状态
│       ├── ai_session.dart            # 单次 AI 会话生命周期
│       └── tool_runtime/
│           ├── tool_registry.dart     # 白名单注册
│           ├── filemcp.dart           # 文件系统工具
│           ├── regmcp.dart            # 注册表工具（win32 包）
│           └── procmcp.dart           # 启动项 / 进程工具
└── presentation/
    ├── providers/
    │   ├── auth_provider.dart         # 登录态、会员、配额
    │   └── ai_provider.dart           # 当前 AI 会话状态机
    └── screens/
        ├── account_screen.dart        # 登录 / 注册 / 找回入口
        ├── membership_screen.dart     # 套餐展示 + 扫码支付
        └── ai_analysis_panel.dart     # 通用 AI 分析卡片（被各页面嵌入）
```

### 4.2 AI 分析入口（需求 §2 端侧要求）

每个 v0.3 已有的功能页注入"问 FileClaw"按钮，行为统一：

| 功能页 | 入口位置 | intent | 初始 ctx |
|---|---|---|---|
| 注册表残留 (`UninstallResidueScreen`) | 每行尾部 ✦ 图标 | `analyze_registry_residue` | `{ key, values_summary }` |
| 启动项管理 (`StartupManagerScreen`) | 每行尾部 ✦ 图标 | `explain_startup_item` | `{ name, command, location }` |
| 大文件 (`LargeFileScreen`) | 选中后工具栏"AI 解读" | `classify_large_file` | `{ path, size, ext, mtime }` |
| 重复文件 (`DuplicateFilesScreen`) | 同上 | `pick_dup_to_delete` | `{ group: [paths] }` |
| 磁盘分析 (`DiskAnalysisScreen`) | 当前目录右上 | `summarize_dir` | `{ dir, top_children }` |
| 已安装程序 (`InstalledProgramsScreen`) | 每行 ✦ | `is_safe_to_uninstall` | `{ display_name, publisher }` |

未登录点击 → 弹账户登录引导；已登录但会员到期/配额不足 → 引导到会员页。
**默认 ctx 不含文件内容，仅含路径与元数据**；若 ReAct 循环中云侧需要文件头部内容，
通过 `filemcp.read_text_head(path, max_bytes=4096)` 调用，端侧弹一次性授权确认。

### 4.3 账户与会员入口

- 主侧栏新增 "账户" 项，未登录时显示 "登录/注册"，已登录显示头像+用户名+剩余 token；
- "开通会员" 页签：
  - 套餐卡片（Free / Pro Monthly / Pro Annual / Token Pack）；
  - 点击 "立即开通" → 弹窗显示二维码 + 倒计时；
  - SSE 监听支付完成 → 自动关闭弹窗 + Snackbar 提示 + 刷新 `/me`。
- 所有账户/会员请求都通过 `CloudClient` 统一接入，便于离线检测与错误处理。

### 4.4 工具执行运行时（ToolRuntime）

- 复用 v0.3 已有的扫描器：`regmcp.read_key` 直接复用 `RegistryResidueScanner`
  的注册表读取代码；`procmcp.list_startup_items` 复用 `StartupItemScanner`；
- **不复用 `SafetyGuard` 之外的删除逻辑**——AI 触发的删除必须走 `safe_delete`
  且强制 `FOF_ALLOWUNDO`（回收站），即便 AI 在 args 里要求 "彻底删除" 也忽略；
- 工具执行串行（每会话一个执行队列），避免并发删/读冲突；
- 每次工具执行写入端侧日志 `<AppData>\Dustman\logs\fileclaw-YYYY-MM-DD.log`，
  字段：`session_id, call_id, tool, args, ok, latency, error`。

### 4.5 离线降级

- 启动时 `CloudClient.health()` 失败 → 隐藏所有 ✦ 按钮，账户页显示 "离线"，
  其他功能（v0.3 全部能力）正常使用；
- 已登录用户处于离线状态，不阻塞本地操作，只是 AI 入口暂时灰掉。

---

## 5. 端云通信协议细节

### 5.1 传输
- **HTTPS 1.1**（强制 TLS 1.2+），证书可换自签（自部署场景）；
- **SSE** 而非 WebSocket：穿透代理更好、单向流足够（双向通过 SSE 下发 + 端侧
  额外 POST `/tool-result` 解决），实现也比 WebSocket 简单。

### 5.2 鉴权
- 所有 `/ai/*` 与 `/billing/*` 请求带 `Authorization: Bearer <access_token>`；
- SSE 不支持自定义 header → token 通过 query string `?t=<access_token>`，
  云侧只接受短期 access_token，避免 query 泄露到日志的风险（access 15min 即过期）。

### 5.3 重连
- SSE 断线 → 端侧带 `Last-Event-ID` 自动重连，云侧从 Redis 中恢复会话状态；
- 重连次数硬上限 3 次，失败则把会话标记 `aborted`，UI 提示用户重试。

### 5.4 协议版本
- 端云握手第一帧 `{"type":"hello","protocol":"fileclaw/0.4"}`；
- 不匹配 → 端侧提示 "请升级 Dustman 客户端"，强制升级路径见 §8。

---

## 6. 安全与隐私

| 风险 | 缓解 |
|---|---|
| AI 误导用户删除关键文件 | 写操作必须 `needs_user_consent=true` 弹端侧确认；删除强制走回收站；`SafetyGuard` 白名单优先级高于 AI 指令 |
| 路径泄露到云日志 | 工具参数入库前做 SHA256（`args_hash`）；明文参数只保留在 Redis 会话状态中，会话结束 24h 后清理 |
| refresh_token 被窃 | DPAPI 加密 + 用户级密钥，跨用户/跨机器无法解；服务端按设备 label 列出，可远程吊销 |
| 暴力撞库 | 登录 + 验证码接口按 IP / 邮箱双维度限流（10/min, 60/h），失败 5 次进 15min 冷却 |
| 第三方支付回调伪造 | 校验签名 + IP 白名单 + 订单状态机（pending→paid 不可逆，重放无效） |
| 越权工具调用 | 工具白名单由端侧持有，云侧请求未注册工具一律拒绝；写工具强制二次确认 |
| 离线场景 token 长期不回收 | refresh_token 30 天过期；access 15min；服务端检测异常使用模式（短时多 IP）自动吊销 |
| 用户数据导出 / 注销 | 提供 `/me/export` 与 `/me/delete` 满足合规（GDPR / 个保法） |

---

## 7. 里程碑与任务拆解

> 建议把 v0.4 拆为 **v0.4.0-alpha**（云侧骨架 + 登录） → **v0.4.0-beta**（AI 注册表分析单点） → **v0.4.0** （全量入口 + 付费）。

### M1 云侧骨架 (alpha) — 约 2 周
- [ ] 仓库初始化 `dustman-cloud`，FastAPI + PostgreSQL + Redis docker-compose
- [ ] users / refresh_tokens / email_codes 表 + 迁移工具（alembic）
- [ ] `/auth/*` 全套接口 + 邮件验证码（先用 SMTP 占位）
- [ ] JWT 中间件 + 限流中间件
- [ ] OpenAPI 文档可访问 `/docs`

### M2 端侧账户 (alpha) — 约 1 周
- [ ] `CloudClient` + `AuthStore`（DPAPI）
- [ ] AccountScreen 登录 / 注册 / 找回密码
- [ ] 侧栏接入登录状态显示
- [ ] 离线检测 + 降级

### M3 AI 编排骨架 (beta) — 约 2 周
- [ ] LangGraph 状态机 + ReAct 节点
- [ ] `/ai/sessions` + SSE
- [ ] 工具协议序列化 / 反序列化
- [ ] 端侧 `ToolRuntime` + `regmcp.read_key` / `read_values` 两个只读工具
- [ ] UninstallResidueScreen 接入 ✦ 按钮 + AnalysisPanel UI

### M4 计费 — 约 1.5 周
- [ ] orders / subscriptions / user_quota 表
- [ ] 微信 Native + 支付宝当面付接入
- [ ] `/billing/*` + webhook
- [ ] MembershipScreen 二维码 + SSE 监听
- [ ] token 计量 LangGraph hook + 配额校验

### M5 全量 AI 入口 — 约 1.5 周
- [ ] filemcp / procmcp 工具实现
- [ ] 6 个 AI 入口接入（§4.2 表格）
- [ ] AI 写操作（`safe_delete` / `disable_startup_item`）+ 端侧二次确认
- [ ] 端侧 fileclaw 日志

### M6 双版本构建与发布 — 约 1 周
- [ ] `lib/core/edition.dart` + 编译期 `--dart-define=DUSTMAN_EDITION`
- [ ] GitHub Actions 矩阵：同时产出 Community / Pro 两套二进制 + MSIX
- [ ] 验证社区版二进制中**确实不含**任何 fileclaw / billing / 云端 endpoint 字符串
  （`strings dustman.exe | grep -i fileclaw` 应为空）
- [ ] 安全自查（§6 全项）
- [ ] 文档：用户使用说明 + 自部署说明 + 版本对照
- [ ] 灰度：先放 100 名内测用户用 Pro 版，跑 1 周再公开发布两个版本

> 累计预估 **9 周** 工程量（单人全栈节奏）。若云侧 / 端侧并行可压缩到 6 周。

---

## 8. 客户端版本兼容与升级

- 端侧每次请求带 `X-Dustman-Version: 0.4.0`；
- 云侧维护 `min_supported_version`，低于此版本一律返回 426 Upgrade Required；
- 升级提示在端侧统一弹窗，附下载链接（指向 GitHub Releases）；
- 协议字段做加法式演进，不删字段、不改语义；破坏性变更 → 协议版本号 +1 + 端侧兼容期 ≥ 2 个客户端版本。

---

## 9. 风险与开放问题

### 9.1 已决策

| # | 议题 | 决策 |
|---|---|---|
| R1 | 云侧仓库独立 vs monorepo | **独立仓库 `dustman-cloud`**；不在主仓建 `cloud/` 目录，e2e 测试通过端侧 mock + 云侧契约测试覆盖 |
| R3 | 海外支付通道 | **本期不接入 Stripe**；仅微信 Native + 支付宝当面付，海外场景 v0.5+ 评估 |
| R4 | 价格 / 套餐 | **测试定价 ¥0.01**；用于验证支付通路、付费意愿与配额是否合理，不以收入为目标 |
| R9 | 自部署 / 社区版策略 | **双版本发行**（详见 §10.5）：社区版不含 FileClaw 任何代码；付费版包含 FileClaw 与账户/会员入口 |

### 9.2 待决策

| # | 议题 | 当前倾向 |
|---|---|---|
| R2 | LLM 主选 Claude vs OpenAI | Claude 为主，OpenAI 适配层在 §3.4 ToolNode 抽象内预留，但 v0.4 不实际接入 |
| R5 | 客户端崩溃后已扣 token 是否回退 | 会话 5min 无活动自动 abort；已消耗 token 不退；首次发生时人工兜底 |
| R6 | 端侧本地小模型作为离线兜底 | v0.4 不做，v0.5+ 评估 Ollama / Phi-3 / Qwen2-1.5B |
| R7 | 订阅取消 / 退款流程 | 本期仅"下个周期不续费"；退款先走人工邮件，量大再引入工单系统 |
| R8 | 协议加密层（TLS 之外） | 不额外加密；自部署用户在公司内网用自签证书即可 |
| R10 | `SafetyGuard` 与 AI 写工具优先级冲突 | SafetyGuard 硬拦截优先；不提供降权开关 |

---

## 10. 与 v0.3 既有功能的关系

- v0.3 全部功能保持**离线可用、无注册可用**；FileClaw 是"叠加"而非替换；
- `SafetyGuard` / `CleanerService` / 既有 Scanner 不动，AI 写工具只是这些服务的
  新 caller；
- CLI 模式 (`dustman.exe scan/clean`) 本期**不接入 FileClaw**，保持纯本地确定性，
  适合 CI / 脚本场景。

---

## 10.5 双版本发行（Community / Pro）

### 10.5.1 版本差异

| 能力 | Community（社区版） | Pro（付费版） |
|---|:-:|:-:|
| v0.3 全部清理 / 扫描 / TreeMap / CLI / 绿色版 | ✓ | ✓ |
| 主题、i18n、清理计划提醒 | ✓ | ✓ |
| FileClaw 账户登录 / 注册 / 找回密码 | ✗ | ✓ |
| FileClaw AI 分析入口（注册表/文件/启动项等 6 处 ✦） | ✗ | ✓ |
| FileClaw AI 操作建议（写工具仍需用户二次确认） | ✗ | ✓ |
| 会员订阅与扫码支付 | ✗ | ✓ |

社区版**完全不包含**任何 FileClaw / 账户 / 支付相关代码与 UI：
- 不显示 "账户" 与 "会员" 侧栏项；
- 6 个功能页不渲染 ✦ 按钮；
- 不携带任何云侧 endpoint 字符串、密钥占位、SSE 客户端代码。

> 设计原则：用户能直接审计社区版二进制确认 "无任何联网行为"，
> 与 [REQUIREMENTS.md §4.3](REQUIREMENTS.md) "默认不联网" 承诺一致。

### 10.5.2 实现机制

采用 **Dart 编译期条件** + **目录隔离**，避免运行时 feature flag 带来的代码混入：

```yaml
# 构建命令
flutter build windows --release --dart-define=DUSTMAN_EDITION=community
flutter build windows --release --dart-define=DUSTMAN_EDITION=pro
```

- 新增 `lib/core/edition.dart`：`const kEdition = String.fromEnvironment('DUSTMAN_EDITION', defaultValue: 'community')`；
- FileClaw 代码全部放在 `lib/data/fileclaw/`、`lib/presentation/screens/account_*`、
  `lib/presentation/screens/membership_*`、`lib/presentation/providers/auth_provider.dart`、
  `lib/presentation/providers/ai_provider.dart`；
- **关键**：FileClaw 入口（`app.dart` 的 Provider 装配、`home_screen.dart` 的侧栏、
  各功能页的 ✦ 按钮）都通过 `if (kEdition == 'pro') ...` 条件构建；
- 由于 `String.fromEnvironment` 是编译期常量，Dart 编译器会**树摇（tree-shake）**
  掉社区版分支引用的 FileClaw 代码，社区版二进制中不会包含云客户端实现。

### 10.5.3 CI / 发布

- GitHub Actions 矩阵构建两份产物：
  - `dustman-community-v0.4.0.zip` / `.msix`
  - `dustman-pro-v0.4.0.zip` / `.msix`
- 关于命名与下载入口：README 顶部清晰列出两个版本与各自适用场景；
- 自动更新（若引入）按版本通道分别推送；
- 社区版的 `--version` 输出标注 `Dustman 0.4.0 (Community)`，Pro 版同理。

### 10.5.4 跨版本迁移

- 社区版用户切换到 Pro 版：直接安装 Pro 版到同一目录或新目录均可，
  设置 / 计划 / 日志兼容读取（schema 一致）；
- Pro 版用户切换回社区版：Pro 版独有的 `auth.bin` 在社区版下被忽略，
  不影响其他设置。

---

## 11. 后续 (v0.5+) 展望

- 端侧本地小模型作为离线兜底（Phi-3 / Qwen2-1.5B via ONNX）；
- 团队/企业账户 + 集中策略下发；
- FileClaw 工具集开放给第三方插件（受限白名单）；
- macOS / Linux 端侧适配（云侧不需要改动）。
