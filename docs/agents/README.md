# MyWallpaperX Agent Docs

> 这是 `MyWallpaperX` 当前多 Agent 协作体系的总入口。
> 如果你刚进入这个目录，先看这份文档，再决定去哪个角色文件。

---

## 1. 这套文档是干什么的

这里不是“随便放几份提示词”的目录。

这里承载的是一套用于管理 `MyWallpaperX` 开发协作的机器人团队体系，包括：

- 角色分工
- 目录职责
- 公共协议边界
- 团队协作与升级机制
- 任务派发方式
- 审查标准

它的目标不是让机器人各自发挥，而是让它们在统一架构下稳定协作。

---

## 2. 当前协作主流程

默认流程：

`Explorer -> Architect -> Protocol Steward / Module Agent -> Integrator -> Verifier -> Gatekeeper`

如果任务是明显的 macOS 原生 UI 设计问题，可以在 Architect 判责后引入：

`macOS26 System UI Designer`

所有 Agent 的协作、转交、上报规则，统一见：

- [collaboration-protocol.md](/Users/songziqiang/Documents/Development/MyWallpaperX/docs/agents/collaboration-protocol.md)

### 默认主流程角色

- `Architect`
- `Explorer`
- `Protocol Steward`
- `Integrator / Rollout Manager`
- `Verifier / QA Agent`
- `Gatekeeper`

### 扩展 Agent

这些角色不默认进入主执行链路，但在任务类型明确匹配时必须可发现、可引入：

- [macos26-ui-designer/AGENTS.md](/Users/songziqiang/Documents/Development/MyWallpaperX/docs/agents/macos26-ui-designer/AGENTS.md)
- [steam-web-compat-auditor/AGENTS.md](/Users/songziqiang/Documents/Development/MyWallpaperX/docs/agents/steam-web-compat-auditor/AGENTS.md)
- [web-development-expert-agent/AGENTS.md](/Users/songziqiang/Documents/Development/MyWallpaperX/docs/agents/web-development-expert-agent/AGENTS.md)
- [functional-logic-check-agent/AGENTS.md](/Users/songziqiang/Documents/Development/MyWallpaperX/docs/agents/functional-logic-check-agent/AGENTS.md)
- [code-health-split-agent/AGENTS.md](/Users/songziqiang/Documents/Development/MyWallpaperX/docs/agents/code-health-split-agent/AGENTS.md)
- [redundancy-cleanup-agent/AGENTS.md](/Users/songziqiang/Documents/Development/MyWallpaperX/docs/agents/redundancy-cleanup-agent/AGENTS.md)
- [status-menu-monitor-agent/AGENTS.md](/Users/songziqiang/Documents/Development/MyWallpaperX/docs/agents/status-menu-monitor-agent/AGENTS.md)

---

## 3. 先看哪份文档

### 如果你想知道“谁负责什么”

先看：

- [../../AGENTS.md](/Users/songziqiang/Documents/Development/MyWallpaperX/AGENTS.md)

这是仓库级团队说明文件，描述：

- 当前有哪些 Agent
- 各目录归谁
- 遇到任务时大概该先找谁

### 如果你想进入真正的 Architect 角色

看：

- [Architect/AGENTS.md](/Users/songziqiang/Documents/Development/MyWallpaperX/docs/agents/Architect/AGENTS.md)

这是当前实际使用中的 `Architect` 身份文件。

### 如果你想先扫代码、建立上下文

看：

- [explorer/AGENTS.md](/Users/songziqiang/Documents/Development/MyWallpaperX/docs/agents/explorer/AGENTS.md)

### 如果你要处理公共协议

看：

- [protocol-steward/AGENTS.md](/Users/songziqiang/Documents/Development/MyWallpaperX/docs/agents/protocol-steward/AGENTS.md)

适用任务：

- 路由
- Notification
- 菜单
- 工具栏模式
- 焦点接管
- `InspectorHost`
- 架构文档同步

### 如果你要收口多角色交付

看：

- [integrator/AGENTS.md](/Users/songziqiang/Documents/Development/MyWallpaperX/docs/agents/integrator/AGENTS.md)

适用任务：

- 一个需求拆成了公共层补丁和模块补丁
- 需要明确当前谁完成了、谁没完成
- 需要把多个 Agent 的输出拼成一次完整交付

### 如果你要验证是否真的达标

看：

- [verifier/AGENTS.md](/Users/songziqiang/Documents/Development/MyWallpaperX/docs/agents/verifier/AGENTS.md)

适用任务：

- 需要对照验收标准检查是否闭环
- 需要区分“代码已写”与“用户路径真的可用”
- 需要在放行前补一层验证

### 如果你要审查补丁

看：

- [gatekeeper/AGENTS.md](/Users/songziqiang/Documents/Development/MyWallpaperX/docs/agents/gatekeeper/AGENTS.md)

### 如果你要做 macOS 26 原生 UI 设计

看：

- [macos26-ui-designer/AGENTS.md](/Users/songziqiang/Documents/Development/MyWallpaperX/docs/agents/macos26-ui-designer/AGENTS.md)

### 如果你要直接发任务

看：

- [Architect/task-dispatch-templates.md](/Users/songziqiang/Documents/Development/MyWallpaperX/docs/agents/Architect/task-dispatch-templates.md)

### 如果你要做审查或自查

看：

- [Architect/review-checklists.md](/Users/songziqiang/Documents/Development/MyWallpaperX/docs/agents/Architect/review-checklists.md)

### 如果你想知道团队成员之间怎么协作、何时转交、何时上报

看：

- [collaboration-protocol.md](/Users/songziqiang/Documents/Development/MyWallpaperX/docs/agents/collaboration-protocol.md)

---

## 4. 当前这套体系的关键边界

所有 Agent 默认都应遵守：

1. 禁止跨模块直接调用
2. 所有跨模块行为必须走 Notification
3. 不允许随意修改 `Core/` 或 `Shared/`
4. 不允许在 `Shell` 写业务逻辑
5. 所有修改必须使用 diff patch 输出
6. 修改必须是最小变更

当前项目中的重点公共协作面包括：

- 路由：`SelectedItem`、`DetailView`、`syncManagerSelection`
- 菜单：`MainWindowCoordinator` + `AppDelegate.validateMenuItem(_:)`
- 焦点：`moduleDidBecomeActive` + `ModuleFocusable`
- 工具栏：`VideoLibraryToolbarController`
- 侧边栏：`SidebarViews`
- 统一详情宿主：
  - `InspectorHost`
  - `InspectorHostBridge`
  - `InspectorHostActions`

只要任务触达这些区域，就不应被简单视为“普通模块内小改动”。

---

## 5. 模块边界

模块不维护独立 `AGENTS.md`。现行任务边界以仓库根目录 [AGENTS.md](/Users/songziqiang/Documents/Development/MyWallpaperX/AGENTS.md)、对应源码目录和当前测试为准。

---

## 6. 推荐阅读顺序

如果是第一次接触这套体系，建议按这个顺序看：

1. [../../AGENTS.md](/Users/songziqiang/Documents/Development/MyWallpaperX/AGENTS.md)
2. [Architect/AGENTS.md](/Users/songziqiang/Documents/Development/MyWallpaperX/docs/agents/Architect/AGENTS.md)
3. [Architect/task-dispatch-templates.md](/Users/songziqiang/Documents/Development/MyWallpaperX/docs/agents/Architect/task-dispatch-templates.md)
4. [Architect/review-checklists.md](/Users/songziqiang/Documents/Development/MyWallpaperX/docs/agents/Architect/review-checklists.md)
5. [collaboration-protocol.md](/Users/songziqiang/Documents/Development/MyWallpaperX/docs/agents/collaboration-protocol.md)
6. [integrator/AGENTS.md](/Users/songziqiang/Documents/Development/MyWallpaperX/docs/agents/integrator/AGENTS.md)
7. [verifier/AGENTS.md](/Users/songziqiang/Documents/Development/MyWallpaperX/docs/agents/verifier/AGENTS.md)
8. [../web/README.md](/Users/songziqiang/Documents/Development/MyWallpaperX/docs/web/README.md)
9. 再进入你需要的具体角色文件

---

## 7. 这个目录以后怎么维护

维护原则：

- 新增角色时，在这里补入口说明
- 角色职责变化时，先更新对应 `AGENTS.md`
- 任务模板或审查方法变化时，更新辅助文档
- 如果公共协议变化，确保：
  - 本目录文档
  - 各角色文档
  - `docs/architecture/framework-architecture-memo.md`
  三者一致

---

## 8. 一句话总结

如果你不知道该看哪份文档，就从这里开始；
如果你不知道该把任务交给谁，就先走 `Explorer -> Architect`。
