include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-wifi-ac
PKG_VERSION:=1.0
PKG_RELEASE:=1

PKG_LICENSE:=MIT
PKG_MAINTAINER:=liyinghao2009 <liyinghao2009@163.com>
URL:=https://github.com/liyinghao2009/luci-app-wifi-ac.git
PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)

LUCI_TITLE:=LuCI Support for WiFi AC Controller
LUCI_PKGARCH:=all

LUCI_DEPENDS:=+luci \
	+luci-base \
	+luci-lib-jsonc \
	+luci-lib-nixio \
	+libuci \
	+luci-lib-ip \
	+libnl \
	+luci-lib-httpclient \
	+luci-lib-fs \
	+libubus \
	+uhttpd \
	+uhttpd-mod-ubus \
	+iwinfo \
	+jsonfilter \
	+coreutils \
	+coreutils-base64 \
	+coreutils-stat \
	+coreutils-sort \
	+coreutils-sha256sum \
	+busybox \
	+logrotate \
	+opkg \
	+libubox \
	+libuci \
	+libjson-c \
	+libnl-tiny \
	+libopenssl \
	+ca-bundle \
	+ca-certificates \
	+dnsmasq \
	+odhcpd-ipv6only \
	+iptables \
	+ip-full \
	+ipset

LUCI_DEPENDS+= \
	+sqlite3-cli \
	+libsqlite3 \
	+curl \
	+wget \
	+bash \
	+libinotifytools \
	+lua-cjson \
	+luasocket

# 三方/调试/高级功能可选依赖（如需启用请取消注释）
# LUCI_DEPENDS+= \
#	+netcat \
#	+jq \
#	+python3

# 三方/外部依赖（OpenWrt 源不自带，需手动集成或前端CDN引入，供文档说明/开发参考，不建议直接写入LUCI_DEPENDS）
# 前端依赖（仅文档说明，非Makefile依赖）:
#   echarts         # 信号分布、热力图、趋势图（前端CDN或npm引入）
#   chart.js        # 趋势图（前端CDN或npm引入）
#   jspdf           # 日志导出 PDF（前端CDN或npm引入）
#   pdfmake         # 日志导出 PDF（可选，前端CDN或npm引入）

# 后端可选依赖（如需高级功能/脚本扩展，需手动安装）:
#   python3         # 高级数据处理/采集脚本
#   jq              # JSON处理（shell脚本用）
#   netcat          # UDP监听/调试用
#   avahi-daemon    # mDNS responder（AP端自动发现/注册用）

include $(INCLUDE_DIR)/package.mk

define Package/$(PKG_NAME)
  SECTION:=luci
  CATEGORY:=LuCI
  SUBMENU:=3. Applications
  TITLE:=$(LUCI_TITLE)
  DEPENDS:=$(LUCI_DEPENDS)
  PKGARCH:=$(LUCI_PKGARCH)
  CONFFILES:=/etc/config/wifi_ac
endef

define Package/$(PKG_NAME)/description
LuCI Web UI for WiFi AC Controller, supporting AP management, optimization, firmware upgrade, logs, and settings.
endef

define Package/$(PKG_NAME)/install
	# LuCI 控制器、模型、CBI、视图
	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/controller
	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/model
	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/model/cbi
	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/view/wifi_ac

	# 控制器、模型、视图
	$(CP) ./root/usr/lib/lua/luci/controller/wifi_ac.lua $(1)/usr/lib/lua/luci/controller/
	$(CP) ./root/usr/lib/lua/luci/model/wifi_ac.lua $(1)/usr/lib/lua/luci/model/
	$(CP) ./root/usr/lib/lua/luci/model/firmware_manager.lua $(1)/usr/lib/lua/luci/model/
	$(CP) ./root/usr/lib/lua/luci/model/wifi_ap_ubus_example.lua $(1)/usr/lib/lua/luci/model/
	$(CP) ./root/usr/lib/lua/luci/model/cbi/wifi_ac.lua $(1)/usr/lib/lua/luci/model/cbi/
	$(CP) ./root/usr/lib/lua/luci/view/wifi_ac/*.htm $(1)/usr/lib/lua/luci/view/wifi_ac/

	# 前端静态资源
	$(INSTALL_DIR) $(1)/www/luci-static/resources/wifi-ac/js
	$(CP) ./root/www/luci-static/resources/wifi-ac/js/*.js $(1)/www/luci-static/resources/wifi-ac/js/

	# 配置文件与模板
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_DIR) $(1)/etc/wifi-ac
	$(INSTALL_DIR) $(1)/etc/wifi-ac/templates
	$(CP) ./root/etc/config/wifi_ac $(1)/etc/config/
	$(CP) ./root/etc/wifi-ac/*.json $(1)/etc/wifi-ac/
	$(CP) ./root/etc/wifi-ac/*.sql $(1)/etc/wifi-ac/
	$(CP) ./root/etc/wifi-ac/templates/*.json $(1)/etc/wifi-ac/templates/
	$(CP) ./root/etc/wifi-ac/template_schema.json $(1)/etc/wifi-ac/

	# 日志轮转
	$(INSTALL_DIR) $(1)/etc/logrotate.d
	$(CP) ./root/etc/logrotate.d/logrotate-wifi-ac.conf $(1)/etc/logrotate.d/

	# 守护进程、服务脚本
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_DIR) $(1)/usr/sbin
	$(CP) ./root/etc/init.d/wifi-ac-optimizationd $(1)/etc/init.d/
	$(CP) ./root/etc/init.d/wifi-ac-discoverd $(1)/etc/init.d/
	$(CP) ./root/usr/sbin/wifi-ac-optimizationd $(1)/usr/sbin/
	$(CP) ./root/usr/sbin/wifi-ac-discoverd $(1)/usr/sbin/
	$(CP) ./root/usr/sbin/wifi-ac-log-clean.sh $(1)/usr/sbin/
	$(CP) ./root/usr/sbin/wifi-ac-data-collector $(1)/usr/sbin/
	$(CP) ./root/usr/sbin/collect_wifi_data.sh $(1)/usr/sbin/
	$(CP) ./root/usr/sbin/ap-agent-firmware-upload.sh $(1)/usr/sbin/
	$(CP) ./root/usr/sbin/ap-agent-firmware-rollback.sh $(1)/usr/sbin/
	$(CP) ./root/usr/sbin/init_wifi_ac_env.sh $(1)/usr/sbin/
	$(CP) ./root/usr/sbin/optimization-daemon.sh $(1)/usr/sbin/

	# 国际化（po2lmo 缺失时不报错）
ifneq ($(wildcard ./po),)
	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/i18n
	$(foreach po,$(wildcard ./po/*.po), \
		po2lmo $(po) $(1)/usr/lib/lua/luci/i18n/$(notdir $(basename $(po))).zh-cn.lmo || true;)
endif

	# files/ 兼容支持（如有）
ifneq ($(wildcard ./files),)
	$(CP) ./files/* $(1)/
endif
endef

define Package/$(PKG_NAME)/postinst
#!/bin/sh
set -e
chmod +x $${IPKG_INSTROOT}/usr/sbin/*.sh
chmod +x $${IPKG_INSTROOT}/usr/sbin/wifi-ac-*
chmod +x $${IPKG_INSTROOT}/etc/init.d/wifi-ac-*
exit 0
endef

# LuCI 应用标准引入
include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature