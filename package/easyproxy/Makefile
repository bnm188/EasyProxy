include $(TOPDIR)/rules.mk

PKG_NAME:=easyproxy
PKG_VERSION:=0.6.0
PKG_RELEASE:=1

PKG_LICENSE:=MIT
PKG_MAINTAINER:=EasyProxy Contributors

include $(INCLUDE_DIR)/package.mk

define Package/easyproxy
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=EasyProxy proxy manager
  DEPENDS:=+uci +luci-base
  PKGARCH:=all
endef

define Package/easyproxy/description
 Modular proxy management framework for ImmortalWrt.
 Stage 5 generates a split-routing sing-box config with local rule sets,
 can capture LAN traffic through an nftables tproxy table (fully reversible),
 supervises the runtime through procd and shows live state in the panel.
 Stage 6 keeps LAN traffic direct and makes fail_closed real: when the CN rule
 sets are missing nothing is proxied instead of silently going full-tunnel.
 IPv6 is never captured silently: it is explicit `direct` or `block`.
endef

define Package/easyproxy/conffiles
/etc/config/easyproxy
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
	$(INSTALL_DATA) ./files/usr/lib/easyproxy/node.sh $(1)/usr/lib/easyproxy/node.sh
	$(INSTALL_DATA) ./files/usr/lib/easyproxy/maint.sh $(1)/usr/lib/easyproxy/maint.sh
	$(INSTALL_DATA) ./files/usr/lib/easyproxy/adapters/dae.sh $(1)/usr/lib/easyproxy/adapters/dae.sh
	$(INSTALL_DATA) ./files/usr/lib/easyproxy/adapters/sing-box.sh $(1)/usr/lib/easyproxy/adapters/sing-box.sh
	$(INSTALL_DIR) $(1)/usr/share/easyproxy
	$(INSTALL_DATA) ./files/usr/share/easyproxy/easyproxy.default $(1)/usr/share/easyproxy/easyproxy.default
	$(INSTALL_DIR) $(1)/www/luci-static/resources/view/easyproxy
	$(INSTALL_DATA) ./files/www/luci-static/resources/view/easyproxy/overview.js $(1)/www/luci-static/resources/view/easyproxy/overview.js
	$(INSTALL_DIR) $(1)/usr/share/luci/menu.d
	$(INSTALL_DATA) ./files/usr/share/luci/menu.d/luci-app-easyproxy.json $(1)/usr/share/luci/menu.d/luci-app-easyproxy.json
	$(INSTALL_DIR) $(1)/usr/share/rpcd/acl.d
	$(INSTALL_DATA) ./files/usr/share/rpcd/acl.d/luci-app-easyproxy.json $(1)/usr/share/rpcd/acl.d/luci-app-easyproxy.json
	$(INSTALL_DIR) $(1)/etc/easyproxy/ruleset
endef

$(eval $(call BuildPackage,easyproxy))
