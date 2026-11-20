include $(TOPDIR)/rules.mk

PKG_NAME:=easyproxy
PKG_VERSION:=0.8.15
PKG_RELEASE:=1

PKG_LICENSE:=MIT
PKG_MAINTAINER:=EasyProxy Contributors

include $(INCLUDE_DIR)/package.mk

define Package/easyproxy
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=EasyProxy proxy manager
  DEPENDS:=+uci +luci-base +sing-box +lighttpd
  PKGARCH:=all
endef

define Package/easyproxy/description
 Modular proxy management framework for ImmortalWrt with a multi-page
 Chinese LuCI panel (dark theme): overview, nodes, subscription, split,
 engines, DNS, rules, logs, backup and settings.
 Stage 5 generates a split-routing sing-box config with local rule sets and
 can capture LAN traffic through an nftables tproxy table (fully reversible).
 Stage 6 keeps LAN traffic direct and makes fail_closed real: when the CN rule
 sets are missing nothing is proxied instead of silently going full-tunnel.
 IPv6 is never captured silently: it is explicit `direct` or `block`.
 0.8.8 hands a machine over already reporting: installing with a diagnostic
 target switches the schedule on (every 15 days at 03:17, not nightly), so
 nobody has to run a second command and the 1 GB monthly upload quota stays
 almost entirely unused.
 0.8.7 keeps the WebDAV account out of uci and off the install command: one 600
 file (`/etc/easyproxy/diag.conf`) carries URL, account and password, and
 `--diag-config` configures a delivered machine with a single file path -
 nothing sensitive is typed, logged, or readable from `/etc/config/easyproxy`.
 0.8.6 sends the diagnostic bundle to the operator's own cloud over WebDAV
 (Nutstore, Nextcloud, Synology) as an alternative to a GitHub repository: the
 app password lives in a 600 file and reaches curl through netrc, so it never
 shows up in `ps`, and the per-customer folder is created with MKCOL first.
 0.8.5 makes a released package installable again: the installer accepted only
 the `ar` container while every published ipk is a gzip-tar, so a fresh install
 aborted with "is not an ipk archive" before opkg ever ran. It now accepts both
 containers, passes `install --rootfs` through the entry script instead of
 swallowing it, and reads the newest version from the releases.atom feed so a
 rate-limited api.github.com no longer blocks "check for updates".
 0.8.3 adds panel-driven self update (check/apply/rollback with a SHA256 gate),
 log files that are actually written (0600, rotated), a diag bundle filed under
 a per-customer number and uploaded daily, and an installer that adopts an
 existing sing-box and warns about a conflicting proxy stack.
 0.8.2 adds the entry bypass: China IPv4 destinations are released in nft
 before tproxy, so domestic traffic never enters the sing-box process.
endef

define Package/easyproxy/conffiles
/etc/config/easyproxy
/etc/lighttpd-easyproxy.conf
endef

# The standalone panel runs its own lighttpd on 8090 so it cannot disturb LuCI
# on 80. Started here so a fresh install has a UI without a reboot; skipped
# during image builds, where IPKG_INSTROOT points at a staging root.
define Package/easyproxy/postinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] && exit 0
/etc/init.d/easyproxy-panel enable >/dev/null 2>&1
/etc/init.d/easyproxy-panel restart >/dev/null 2>&1
exit 0
endef

define Build/Compile
endef

define Package/easyproxy/install
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./files/etc/config/easyproxy $(1)/etc/config/easyproxy
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/etc/init.d/easyproxy $(1)/etc/init.d/easyproxy
	$(INSTALL_DIR) $(1)/etc/hotplug.d/iface
	$(INSTALL_BIN) ./files/etc/hotplug.d/iface/95-easyproxy $(1)/etc/hotplug.d/iface/95-easyproxy
	$(INSTALL_DIR) $(1)/usr/sbin
	$(INSTALL_BIN) ./files/usr/sbin/easyproxy $(1)/usr/sbin/easyproxy
	$(INSTALL_DIR) $(1)/usr/lib/easyproxy/adapters
	$(INSTALL_DATA) ./files/usr/lib/easyproxy/common.sh $(1)/usr/lib/easyproxy/common.sh
	$(INSTALL_DATA) ./files/usr/lib/easyproxy/config.sh $(1)/usr/lib/easyproxy/config.sh
	$(INSTALL_DATA) ./files/usr/lib/easyproxy/transparent.sh $(1)/usr/lib/easyproxy/transparent.sh
	$(INSTALL_DATA) ./files/usr/lib/easyproxy/bypass.sh $(1)/usr/lib/easyproxy/bypass.sh
	$(INSTALL_DATA) ./files/usr/lib/easyproxy/node.sh $(1)/usr/lib/easyproxy/node.sh
	$(INSTALL_DATA) ./files/usr/lib/easyproxy/maint.sh $(1)/usr/lib/easyproxy/maint.sh
	$(INSTALL_DATA) ./files/usr/lib/easyproxy/traffic.sh $(1)/usr/lib/easyproxy/traffic.sh
	$(INSTALL_DATA) ./files/usr/lib/easyproxy/subscribe.sh $(1)/usr/lib/easyproxy/subscribe.sh
	$(INSTALL_DATA) ./files/usr/lib/easyproxy/clash.sh $(1)/usr/lib/easyproxy/clash.sh
	$(INSTALL_DATA) ./files/usr/lib/easyproxy/mihomo.sh $(1)/usr/lib/easyproxy/mihomo.sh
	$(INSTALL_DATA) ./files/usr/lib/easyproxy/policy.sh $(1)/usr/lib/easyproxy/policy.sh
	$(INSTALL_DATA) ./files/usr/lib/easyproxy/stats.sh $(1)/usr/lib/easyproxy/stats.sh
	$(INSTALL_DATA) ./files/usr/lib/easyproxy/adapters/dae.sh $(1)/usr/lib/easyproxy/adapters/dae.sh
	$(INSTALL_DATA) ./files/usr/lib/easyproxy/adapters/sing-box.sh $(1)/usr/lib/easyproxy/adapters/sing-box.sh
	$(INSTALL_DATA) ./files/usr/lib/easyproxy/adapters/mihomo.sh $(1)/usr/lib/easyproxy/adapters/mihomo.sh
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) ./files/usr/bin/easyproxy-api $(1)/usr/bin/easyproxy-api
	$(INSTALL_DIR) $(1)/usr/share/easyproxy
	$(INSTALL_DATA) ./files/usr/share/easyproxy/easyproxy.default $(1)/usr/share/easyproxy/easyproxy.default
	$(INSTALL_DIR) $(1)/www/luci-static/resources/easyproxy
	$(INSTALL_DATA) ./files/www/luci-static/resources/easyproxy/app.js $(1)/www/luci-static/resources/easyproxy/app.js
	$(INSTALL_DATA) ./files/www/luci-static/resources/easyproxy/ubus.js $(1)/www/luci-static/resources/easyproxy/ubus.js
	$(INSTALL_DIR) $(1)/www/luci-static/resources/view/easyproxy
	$(INSTALL_DATA) ./files/www/luci-static/resources/view/easyproxy/overview.js $(1)/www/luci-static/resources/view/easyproxy/overview.js
	$(INSTALL_DATA) ./files/www/luci-static/resources/view/easyproxy/split.js $(1)/www/luci-static/resources/view/easyproxy/split.js
	$(INSTALL_DATA) ./files/www/luci-static/resources/view/easyproxy/nodes.js $(1)/www/luci-static/resources/view/easyproxy/nodes.js
	$(INSTALL_DATA) ./files/www/luci-static/resources/view/easyproxy/kernel.js $(1)/www/luci-static/resources/view/easyproxy/kernel.js
	$(INSTALL_DATA) ./files/www/luci-static/resources/view/easyproxy/dnsnet.js $(1)/www/luci-static/resources/view/easyproxy/dnsnet.js
	$(INSTALL_DATA) ./files/www/luci-static/resources/view/easyproxy/monitor.js $(1)/www/luci-static/resources/view/easyproxy/monitor.js
	$(INSTALL_DATA) ./files/www/luci-static/resources/view/easyproxy/settings.js $(1)/www/luci-static/resources/view/easyproxy/settings.js
	$(INSTALL_DATA) ./files/www/luci-static/resources/view/easyproxy/update.js $(1)/www/luci-static/resources/view/easyproxy/update.js
	$(INSTALL_DIR) $(1)/usr/share/luci/menu.d
	$(INSTALL_DATA) ./files/usr/share/luci/menu.d/luci-app-easyproxy.json $(1)/usr/share/luci/menu.d/luci-app-easyproxy.json
	$(INSTALL_DIR) $(1)/usr/share/rpcd/acl.d
	$(INSTALL_DATA) ./files/usr/share/rpcd/acl.d/luci-app-easyproxy.json $(1)/usr/share/rpcd/acl.d/luci-app-easyproxy.json
	$(INSTALL_DIR) $(1)/usr/share/rpcd/ucode
	$(INSTALL_DATA) ./files/usr/share/rpcd/ucode/luci.easyproxy.uc $(1)/usr/share/rpcd/ucode/luci.easyproxy.uc
	$(INSTALL_DIR) $(1)/www/easyproxy/cgi-bin
	$(INSTALL_DATA) ./files/www/easyproxy/index.html $(1)/www/easyproxy/index.html
	$(INSTALL_DATA) ./files/www/easyproxy/panel.js $(1)/www/easyproxy/panel.js
	$(INSTALL_DATA) ./files/www/easyproxy/panel.css $(1)/www/easyproxy/panel.css
	$(INSTALL_BIN) ./files/www/easyproxy/cgi-bin/api.sh $(1)/www/easyproxy/cgi-bin/api.sh
	$(INSTALL_CONF) ./files/etc/lighttpd-easyproxy.conf $(1)/etc/lighttpd-easyproxy.conf
	$(INSTALL_BIN) ./files/etc/init.d/easyproxy-panel $(1)/etc/init.d/easyproxy-panel
	$(INSTALL_DIR) $(1)/etc/easyproxy/ruleset
endef

$(eval $(call BuildPackage,easyproxy))
