# 团队平台第一阶段实现（开发预览）

> 状态：**仅用于开发联调，不可投产**。本文描述新增的最小纵向切片，而非完整团队平台。

## 已接通的边界

- 服务端保持旧 `/frameworks` 查询接口；新 `/api/v1` 默认关闭。开启后禁用旧上传和删除接口，防止绕开受管发布单。
- 发布单按 `{name, version}` 唯一预留同一个源码 Git SHA；任务可领取两分钟租约、续租、输出事件。代理提交源码和二进制 spec 的提交 SHA、上传暂存 ZIP，并以 SHA-256 再验证后将发布单标记为 `active`。服务端不自行核验远端 Git 仓库；目前这两个 SHA 是**代理声明**，不是生产证明。
- 暂存 ZIP 不进入旧 `/frameworks` 列表，也不能从新下载接口读取；只有 `active` 发布单可从受保护的新接口下载。失败版本保留以便排查，可重试同一发布单，不自动删除 Git Tag/spec。
- 平台策略是按工程、target 保存的不可变快照；只有已激活的组件版本可加入。启用策略需要带上此前的 `expectedRevision`，冲突返回 409。
- Ruby `pod bin sync <project> --revision=<uuid>` 将策略下载到工程本地 `.imy-bin-policy.json`，Podfile 在对应 target 内调用 `imy_bin_dependencies 'Target', project: 'project'`。本地 `.imy-bin-modes.yml` 覆盖团队模式；`CI=true` 时忽略覆盖、要求 `IMY_BIN_POLICY_REVISION`，并在 `pod bin install/update` 后核对 Lockfile 的版本和 spec 仓库。两种本地文件都不应提交。
- macOS App 的“工程依赖”页展示本地快照并调用现有 CLI 同步或切换；不会保存平台令牌。

## 开发联调配置

只有 `NODE_ENV` 非 `production` 且显式设置下列变量，服务端才挂载新 API：

```text
PLATFORM_API_ENABLED=true
PLATFORM_API_TOKEN=<独立的至少 32 字符开发令牌>
PLATFORM_AGENT_TOKEN=<另一个至少 32 字符开发令牌>
```

`PLATFORM_API_TOKEN` 只用于开发预览的操作/读取端，`PLATFORM_AGENT_TOKEN` 只用于代理端。不得将它们放入 Podfile、日志、命令参数或仓库。Ruby CLI 从 `IMY_BIN_PLATFORM_URL` 与 `IMY_BIN_PLATFORM_TOKEN` 读取服务地址和令牌。CI 还必须设置 `IMY_BIN_POLICY_REVISION`，先执行 `pod bin sync` 再安装。非 CI 本地开发仅在网络连接失败时可显式告警并使用之前验证过的快照。

关键接口：`POST /api/v1/releases`、`POST /api/v1/jobs/claim`、`POST /api/v1/jobs/:id/heartbeat|events|finish`、`POST /api/v1/releases/:id/artifact|steps|retry`、`GET /api/v1/artifacts/:name/:version/zip`、`POST /api/v1/projects/:key/policies`、`POST /api/v1/projects/:key/policies/activate`、`GET /api/v1/projects/:key/policies/active|:revision`。代理请求必须携带有效租约；下载和策略读取需要操作端令牌。

## 正式投入前的阻断项

1. 企业 OIDC/SSO、项目级 RBAC、独立审批人与防篡改审计尚未接入；因此 **生产环境配置会直接拒绝启用新 API**。
2. 受控 macOS 代理、真实 Git 提交/Tag/spec 推送核验及 iOS XCFramework 构建尚未完成；本阶段测试用替身模拟代理结果。
3. 制品仍在本地文件目录，不是 S3 兼容对象存储；新受保护的下载 URL 也尚未与 CocoaPods 的二进制 podspec 下载鉴权打通。
4. 没有独立 Web 后台、任务持久历史 UI、项目审批流、对象存储备份恢复及真实 MongoDB + 私有 spec 仓库端到端验收。不要将开发预览端点暴露到外网。
