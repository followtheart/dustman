# v0.4 安全自查

> 对照 [V0_4_PLAN.md §6 安全与隐私](V0_4_PLAN.md#6-安全与隐私) 风险表逐项核实代码现状。
> 状态：✅ 完成 / ⚠️ 部分 / ❌ 缺失 / 📝 文档说明

| # | 风险 | 状态 | 实现细节 / 缺口 |
|---|---|---|---|
| R1 | AI 误导用户删除关键文件 | ✅ | 三层防御：① 工具 schema 上 `is_write=True` 触发 SSE 帧 `needs_user_consent=true`；② 端侧 `AiSessionClient` 调 `consentResolver`，无解析器或拒绝 → 自动回 `user_declined`；③ `filemcp.safe_delete` 内部仍调 `SafetyGuard.isSafeToDelete` 硬拦截（AI 即便绕过 consent 也删不了 System32），删除强制 `FOF_ALLOWUNDO` 走回收站 |
| R2 | 路径泄露到云日志 | ✅ | DB 比设计更严：`token_usage` 表只存 `intent / model / tokens_in/out`，**不存 args**（连哈希都不存）；会话内 `messages`（含明文 args）仅存进程内存 `SessionRegistry`，会话结束后 dict 自然释放。端侧 `fileclaw-*.log` 含明文 args 但只落用户机器本地，不上传 |
| R3 | refresh_token 被窃 | ⚠️ | DPAPI 加密落 `auth.bin`（用户级密钥，跨用户/跨机器无法解）；`/auth/logout` 单条吊销 ✅；按 device 列表 + 远程吊销其它设备 端点 ❌（gap，M6+ 补） |
| R4 | 暴力撞库 | ✅ | slowapi 限流：register 5/min·30/h；login 10/min·60/h；sms 3/min·30/h；forgot 3/min·10/h；验证码失败次数 `attempts ≥ 5` → 429（`VERIFICATION_MAX_ATTEMPTS=5`）。登录密码错误次数靠 IP rate limit 兜底，未单独跟踪 |
| R5 | 第三方支付回调伪造 | ⚠️ | 签名校验 ✅（M4.5：微信 v3 SDK callback 自动 AES-GCM 解密 + Wechatpay-Signature 验签；支付宝 SDK verify RSA2）；订单状态机不可逆 ✅（`mark_paid_by_id` 只接受 `pending → paid`）；IP 白名单 ❌（依赖反代层 nginx allow，docker compose 没做） |
| R6 | 越权工具调用 | ✅ | 工具白名单端侧持有（`ToolRegistry`），云侧 `tools_for_intent` 按 intent 过滤再下发；云侧 AiSession 收到 LLM 想调用的工具会校验 `name in self.tools` 否则直接 emit error；写工具二次确认链强制（R1 描述） |
| R7 | 离线场景 token 长期不回收 | ⚠️ | access TTL 15 min ✅；refresh TTL 30 天 ✅；异常使用模式检测（短时间多 IP） ❌（gap） |
| R8 | 用户数据导出 / 注销 | ❌ | `/me/export` 与 `/me/delete` 端点未实现；模型层有 `UserStatus.DELETED` 软删除态 ✅；M6+ 单独里程碑做合规模块 |

## 额外发现（设计文档未列）

| # | 风险 | 状态 | 详情 |
|---|---|---|---|
| X1 | `Settings.jwt_secret` 默认 `dev-only-change-me` | 📝 | 启动期未强制校验非默认；`docker-compose.yml` / `.env.example` 已提示。**生产部署 checklist 必填项** |
| X2 | Stub 渠道任意人可下单自动 paid | 📝 | StubPaymentClient 由 `provider=stub` 显式触发；生产环境只允许 wechat_native / alipay_face；建议生产配置文件移除 stub 选项（或在路由层用 `if not settings.is_production` 拒绝） |
| X3 | 端侧 access_token 通过 `Authorization: Bearer` 头传输 | ✅ | 内存持有，不落盘；refresh 才落 DPAPI 加密文件 |
| X4 | SSE 不带 `Authorization` 头（浏览器 EventSource 限制） | 📝 | M3 端侧用 `http.send()` 自己解析 SSE，能带 header；当前实现已带 `Authorization: Bearer`；纯浏览器场景未来需走 query string 短 token |
| X5 | webhook 路由对未知 provider 直接 400 | ✅ | M4.5 已加 |
| X6 | 工具超时 30s 后 AI 会话自动 emit error 并退出 | ✅ | M3 `TOOL_TIMEOUT_SECONDS=30` |
| X7 | 工具调用轮数 + token 预算双上限 | ✅ | `max_tool_rounds=6` + `max_total_tokens=50_000` per intent |
| X8 | 端云协议版本字段 | ⚠️ | hello 帧含 `protocol: fileclaw/0.4`；端侧未校验，未来破坏性变更要补 |

## 端侧专项

| # | 风险 | 状态 | 详情 |
|---|---|---|---|
| C1 | SafetyGuard 硬拦截受保护路径 | ✅ | `SafetyGuard.isSafeToDelete` 黑名单含 `System32` / `SysWOW64` / 用户 `Documents` 等；filemcp.safe_delete / 既有清理 service 都过这道关 |
| C2 | DPAPI 文件跨用户解密 | ✅ | `CryptProtectData` 默认用户级 entropy；非本用户读 → `_dpapiUnprotect` 返回 null → AuthStore.load() 返回 null → 视为未登录 |
| C3 | Community 二进制中混入 FileClaw 代码 | ✅ | 5 次 release build 验证：Community app.so 6.25 MB **一字未变**；37/37 字串全部缺席。CI [build.yml](../.github/workflows/build.yml) 自动卡这一关 |
| C4 | fileclaw 审计日志含敏感路径 | 📝 | 日志只落用户机器本地（`<dataDir>/logs/fileclaw-*.log`），不上传；用户主导清理 / 备份 |
| C5 | 离线场景 ✦ 按钮误操作 | ✅ | `CloudClient.health()` 失败时 AuthProvider 处于 unauthenticated，✦ 调 `runAiAnalysis` 会因 access_token 为空被 401 拒绝，用户看到 "未登录" 文案 |

## 待办清单（M6+）

按优先级：

1. **P0** Settings 启动期校验：`jwt_secret == 'dev-only-change-me' and app_env == 'production'` → 立刻拒绝启动
2. **P0** 生产环境禁用 stub 支付：`provider=stub` 在 `app_env=production` 下返回 400
3. **P1** `/auth/me/devices` 列表 + `/auth/me/devices/{id}/revoke` 吊销其它设备
4. **P1** webhook IP 白名单（nginx 层）+ 文档说明微信 / 支付宝官方 IP 段
5. **P2** `/me/export`（JSON 全量导出）+ `/me/delete`（软删除 + 异步硬删除任务，含 30 天 grace 期）
6. **P2** 登录密码错误次数单独跟踪（5 次 → 锁 15 分钟）
7. **P2** access_token 异常 IP 检测（首次出现陌生 IP → 邮件 / 短信告警，可选自动吊销）
8. **P3** 端侧协议版本不匹配 → 强制升级提示
