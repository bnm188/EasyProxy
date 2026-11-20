# 更新日志

版本号格式：`PKG_VERSION-PKG_RELEASE`，当前基线 `0.8.14-30`。
未归档到具体版本的早期条目见仓库 `git log`。

---

## 0.8.14-30（面板信息架构重排）

### 面板
- 一级导航由 9 项收敛为 6 项：概览 / 分流 / 节点 / 网络 / 内核 / 系统
- 「分流」页内分三段：业务组 9 个（Netflix / YouTube / TikTok / AI / Disney+ / Google / Telegram / Apple / Games）、通用组 2 个（国外 / 其他）、特殊组 2 个（Speed / 国内）
- 空分组弱化为一行灰卡（未分配节点 · 兜底 · 规则数），有成员的组白卡展开成员与延迟占位
- 旧 hash 链接保留别名映射：`groups→routing`、`dns/monitor→network`、`settings/update→system`，旧书签不 404
- 「系统」页合并原设置与更新：管理密码、运行参数、运行自检
- 「网络」页合并 DNS 配置、网络与端口、连接与日志

### 工程
- 回归套件 1071 通过 / 0 失败
- Go 后端 `easyproxy-api` 骨架完成（鉴权、会话、静态托管、系统指标），尚未进 ipk，旧 lighttpd + CGI 保持为默认与回退路径

---

## 0.8.14 开发线

### 引擎与内核
- 新增 mihomo 作为第二引擎，与 sing-box 并列；引擎拆为独立 ipk，附带 geodata
- mihomo 尊重平台开关与自定义规则，汇总里上报 split 路由模式
- 节点出站自带 `domain_resolver`，解除 DoH（`detour=proxy`）拨号死锁
- 去掉对 `/opt/open-box` 内核路径的软件依赖

### 节点与分流
- 节点导入保留每个 proxy 块原文，原样交给 mihomo
- 按地区生成 url-test 组，挂在统一的 PROXY selector 后，面板可切换
- 节点命名模板 + 场景组体系 + 选择持久化
- `node list --json` 带出机场名；修复机场名前缀错位与地区误判
- 地区判定在名称无果时按服务器国家码兜底

### 面板
- 全局顶栏：主开关；节点行使用开关与溢出菜单
- Clash API 实时连接接入面板
- 概览按十项口径重排：运行状态条 + 4 KPI + 实时速率 + 内核状态

### 修复
- 探测时钟改为 `/proc/uptime` 毫秒精度
- `subscribe` / `diag` 补 JSON 输出

---

## 已知未归档

早期 0.8.5–0.8.13 的逐条变更尚未按版本分节，可在仓库用 `git log --oneline` 回溯；后续发版前补齐。
