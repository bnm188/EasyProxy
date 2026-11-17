# ISSUE-004 dae 的 tar.xz 在无 xz 固件上解压失败，且未回落到 ipk

- 状态：待修复（未改代码）
- 发现时间：2026-11-18
- 发现方式：真机共存安装（Kwrt 25.12-SNAPSHOT / x86_64）全程输出
- 严重度：中（dae 标记"开发中"，失败不阻塞 sing-box；但会拖垮整个一键安装的退出码）

## 现象

```
dae: downloading dae-linux-x86_64.tar.xz
dae sha256 ok: dae-linux-x86_64.tar.xz
dae: install failed: cannot extract dae-linux-x86_64.tar.xz (this firmware may lack xz support); the release kernel ipk avoids xz
...
dae        not installed  (/usr/bin/dae)  [adapter 开发中]
error: EasyProxy is installed but these kernels are not: dae
```

## 取证

| 项 | 结果 |
|---|---|
| 下载与校验 | `dae sha256 ok: dae-linux-x86_64.tar.xz`（校验通过，说明包本身没问题） |
| 解压 | `cannot extract ... (this firmware may lack xz support)` |
| 脚本自己的提示 | `the release kernel ipk avoids xz` —— **它知道有 ipk 这条路** |
| 实际走向 | 先下载 tar.xz → 解压失败 → 直接放弃，**没有回落 ipk** |
| 最终结果 | `dae not installed (/usr/bin/dae)`，并让整个安装以 `error:` 退出 |

## 根因

执行顺序是「先试 tar.xz」，且**解压失败后没有回落到 ipk 渠道**。脚本的提示语已经承认 ipk 能绕开 xz，说明 ipk 资产是存在的，实现上只是缺了 fallback。

现场固件确实不具备 xz 解压能力（`tar.xz` 打不开），但这台设备本来就不该走 tar.xz 分支。

## 影响面

- 所有带 dae 的安装/升级，在无 xz 固件上都会出现这一段失败
- 因此一键安装**整体以 error 退出**（rc 非 0），哪怕面板和 sing-box 都正常 —— 与 ISSUE-003 叠加后，用户看到的是"全面失败"
- 与归档里早前那条「dae ipk 被 opkg 判 Malformed」是**两个不同的问题**：那条是 ipk 格式不被 opkg 接受，这条是 tar.xz 无法解压且不回落。两条都要各自处理

## 修复方向（未实施，仅记录）

1. 安装前探测 xz 能力（`command -v xz` / busybox 是否支持 `.xz`），不支持则**直接走 ipk**，不下载 tar.xz
2. 无论哪条路径失败，都必须尝试另一条路径再判定失败
3. 补断言：模拟"无 xz"环境，断言安装器选择 ipk 分支而非 tar.xz

## 关联

- 与 ISSUE-003 在同一次安装中共同造成非 0 退出
- 与「dae ipk Malformed」是不同缺陷，不可合并修
