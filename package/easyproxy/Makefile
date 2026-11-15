include $(TOPDIR)/rules.mk

PKG_NAME:=easyproxy
PKG_VERSION:=0.1.0
PKG_RELEASE:=1

PKG_LICENSE:=MIT
PKG_MAINTAINER:=EasyProxy Contributors

include $(INCLUDE_DIR)/package.mk

define Package/easyproxy
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=EasyProxy proxy manager
  DEPENDS:=+uci
  PKGARCH:=all
endef

define Package/easyproxy/description
 Modular proxy management framework for ImmortalWrt.
 Stage 1 provides configuration, validation and guarded service interfaces.
endef

define Build/Compile
endef

define Package/easyproxy/install
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./files/etc/config/easyproxy $(1)/etc/config/easyproxy
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/etc/init.d/easyproxy $(1)/etc/init.d/easyproxy
	$(INSTALL_DIR) $(1)/usr/sbin
	$(INSTALL_BIN) ./files/usr/sbin/easyproxy $(1)/usr/sbin/easyproxy
	$(INSTALL_DIR) $(1)/usr/lib/easyproxy/adapters
	$(INSTALL_DATA) ./files/usr/lib/easyproxy/common.sh $(1)/usr/lib/easyproxy/common.sh
	$(INSTALL_DATA) ./files/usr/lib/easyproxy/adapters/dae.sh $(1)/usr/lib/easyproxy/adapters/dae.sh
	$(INSTALL_DATA) ./files/usr/lib/easyproxy/adapters/sing-box.sh $(1)/usr/lib/easyproxy/adapters/sing-box.sh
endef

$(eval $(call BuildPackage,easyproxy))
