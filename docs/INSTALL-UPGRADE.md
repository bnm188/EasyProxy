# 安装与升级

适用：OpenWrt / ImmortalWrt / Kwrt，当前主线 `0.8.14-30`，已实测架构 x86_64。

## 一、安装前确认

- 路由器可 SSH 登录，有 root 权限
- 已装好引擎内核（mihomo 或 sing-box）；面板包只带面板与 CLI，内核由引擎包提供
- 架构与 ipk 匹配：`uname -m` 看是 `x86_64` / `aarch64` / `mips` / `mipsel`

## 二、安装

把 ipk 传到路由器 `/tmp` 后执行：

```sh
opkg install --force-reinstall /tmp/easyproxy_0.8.14-30_x86_64.ipk
```

安装完成后面板监听 `8090`，浏览器访问：

```
http://<路由器IP>:8090
```

首次进入要求设置管理密码（6 位以上）。密码哈希存在 `/etc/easyproxy/panel.pw`，权限 600；会话文件在 `/tmp/easyproxy-sessions`，重启清空。

## 三、目录与文件对照

| 路径 | 说明 |
|---|---|
| `/usr/sbin/easyproxy` | CLI，面板与脚本都通过它读写配置 |
| `/www/easyproxy/` | 面板前端（`index.html` / `panel.js` / `panel.css`） |
| `/www/easyproxy/cgi-bin/api.sh` | 旧 CGI 后端，保留为回退路径 |
| `/etc/config/easyproxy` | uci 配置 |
| `/etc/lighttpd-easyproxy.conf` | 面板 lighttpd 配置 |
| `/etc/init.d/easyproxy` | 引擎服务 |
| `/etc/init.d/easyproxy-panel` | 面板服务 |
| `/var/log/easyproxy.log` | 运行日志 |

## 四、升级

直接用新 ipk 覆盖安装：

```sh
opkg install --force-reinstall /tmp/<新包>.ipk
/etc/init.d/easyproxy-panel restart
```

升级行为：

- `/etc/config/easyproxy` 是 conffile，**已修改的配置不会被覆盖**；若新包默认配置有差异，会落到 `/etc/config/easyproxy-opkg`，需要时手动合并
- 面板前端、CLI、LuCI 视图随包覆盖更新
- 密码与已启用节点配置保留

### 建议的备份（升级前）

```sh
cp -a /www/easyproxy /tmp/bk-www
cp /etc/config/easyproxy /tmp/bk-uci
```

## 五、回退

1. 安装上一版 ipk：
   ```sh
   opkg install --force-reinstall /tmp/easyproxy_<旧版本>_x86_64.ipk
   ```
2. 前端回退：
   ```sh
   cp -a /tmp/bk-www/. /www/easyproxy/
   ```
3. 配置回退：
   ```sh
   cp /tmp/bk-uci /etc/config/easyproxy
   /etc/init.d/easyproxy-panel restart
   ```

## 六、卸载

```sh
opkg remove easyproxy
```

卸载不会自动删除 `/etc/config/easyproxy` 与已导入节点；需要彻底清理时另行备份后删除。

## 七、自检与日志

```sh
easyproxy doctor          # 运行自检
tail -n 120 /var/log/easyproxy.log
```

面板「系统 → 运行自检」与 CLI `doctor` 等价。
