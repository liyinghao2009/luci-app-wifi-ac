m = Map("wifi_ac", translate("WiFi AC Settings"))

s = m:section(TypedSection, "wifi_ac", translate("Global Settings"))
s.anonymous = true

s:option(Flag, "enabled", translate("Enable"))
s:option(Value, "ac_name", translate("AC Name"))
s:option(Value, "ac_ip", translate("AC Controller IP"))
s:option(Value, "subnet", translate("Subnet"))
s:option(Value, "gateway", translate("Gateway"))
s:option(ListValue, "network_mode", translate("Network Mode")).default = "dhcp"
s:option(Value, "udp_port", translate("UDP端口"))
s:option(Value, "udp_broadcast", translate("UDP广播地址"))
s:option(Value, "udp_timeout", translate("UDP超时时间(秒)"))
s:option(Value, "udp_retry", translate("UDP重试次数"))
s:option(Value, "ws_port", translate("WebSocket端口"))
s:option(Value, "log_level", translate("日志级别"))
s:option(Value, "log_rotate_days", translate("日志保留天数"))
s:option(Value, "trend_db", translate("趋势数据库路径"))
s:option(Value, "log_retention_days", translate("日志保留天数"))
s:option(Value, "firmware_retention", translate("固件存储上限(MB)"))

g = m:section(NamedSection, "global", "wifi_ac", translate("全局设置"))
g:option(Value, "udp_port", translate("UDP端口")).default = 9090
g:option(Value, "udp_broadcast", translate("UDP广播地址")).default = "255.255.255.255"
g:option(Value, "udp_timeout", translate("UDP超时时间(秒)")).default = 2
g:option(Value, "udp_retry", translate("UDP重试次数")).default = 2

-- 配置模板管理入口（可扩展为Tab/Section）
tpl = m:section(TypedSection, "template_manage", translate("配置模板管理"))
tpl.anonymous = true
tpl.addremove = true
tpl:option(Value, "name", translate("模板名称"))
tpl:option(Value, "vendor", translate("厂商"))
tpl:option(TextValue, "config", translate("配置内容(JSON)"))

-- 权限管理入口（可扩展为Tab/Section）
role = m:section(TypedSection, "role_manage", translate("权限与角色管理"))
role.anonymous = true
role.addremove = true
role:option(Value, "role", translate("角色名"))
role:option(Value, "desc", translate("描述"))
role:option(DynamicList, "users", translate("用户列表"))

-- 恢复出厂设置入口（可扩展为按钮/Section）
reset = m:section(TypedSection, "factory_reset", translate("恢复出厂设置"))
reset.anonymous = true
btn = reset:option(Button, "_reset", translate("恢复出厂设置"))
btn.inputstyle = "reset"
function btn.write()
    luci.http.redirect(luci.dispatcher.build_url("admin/network/wifi_ac/api/factory_reset"))
end

return m
