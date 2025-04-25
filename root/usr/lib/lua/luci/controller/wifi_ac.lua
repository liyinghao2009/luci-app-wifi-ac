module("luci.controller.wifi_ac", package.seeall)

function index()
    if not nixio.fs.access("/etc/config/wifi_ac") then
        return
    end
    entry({"admin", "network", "wifi_ac"}, alias("admin", "network", "wifi_ac", "device_list"), _("WiFi AC"), 90).dependent = true
    entry({"admin", "network", "wifi_ac", "device_list"}, template("wifi_ac/device_list"), _("设备列表"), 10)
    entry({"admin", "network", "wifi_ac", "device_detail"}, template("wifi_ac/device_detail"), _("设备详情"), 20)
    entry({"admin", "network", "wifi_ac", "optimization"}, template("wifi_ac/optimization"), _("优化"), 30)
    entry({"admin", "network", "wifi_ac", "firmware"}, template("wifi_ac/firmware"), _("固件"), 40)
    entry({"admin", "network", "wifi_ac", "log"}, template("wifi_ac/log"), _("日志"), 50)
    entry({"admin", "network", "wifi_ac", "settings"}, cbi("wifi_ac"), _("设置"), 60)
    entry({"admin", "network", "wifi_ac", "api", "device_list"}, call("api_device_list"), nil).leaf = true
    entry({"admin", "network", "wifi_ac", "api", "device_detail"}, call("api_device_detail"), nil).leaf = true
    entry({"admin", "network", "wifi_ac", "api", "device_batch"}, call("api_device_batch"), nil).leaf = true
    entry({"admin", "network", "wifi_ac", "api", "device_add"}, call("api_device_add"), nil).leaf = true
    entry({"admin", "network", "wifi_ac", "api", "device_template"}, call("api_device_template"), nil).leaf = true
    entry({"admin", "network", "wifi_ac", "api", "ws_status"}, call("api_ws_status"), nil).leaf = true
    entry({"admin", "network", "wifi_ac", "api", "templates"}, call("api_templates"), nil).leaf = true
    entry({"admin", "network", "wifi_ac", "api", "optimization"}, call("api_optimization"), nil).leaf = true
    entry({"admin", "network", "wifi_ac", "api", "optimization_threshold"}, call("api_optimization_threshold"), nil).leaf = true
    entry({"admin", "network", "wifi_ac", "api", "optimization_trend"}, call("api_optimization_trend"), nil).leaf = true
    entry({"ws", "wifi-ac", "status"}, call("ws_status"), nil).leaf = true
    entry({"admin", "network", "wifi_ac", "api", "load_balance"}, call("api_load_balance"), nil).leaf = true
    entry({"admin", "network", "wifi_ac", "api", "channel_heatmap"}, call("api_channel_heatmap"), nil).leaf = true
    entry({"admin", "network", "wifi_ac", "api", "set_channel"}, call("api_set_channel"), nil).leaf = true
    entry({"admin", "network", "wifi_ac", "api", "apply_template"}, call("api_apply_template"), nil).leaf = true
    entry({"admin", "network", "wifi_ac", "api", "trends"}, call("api_trends"), nil).leaf = true
    entry({"admin", "network", "wifi_ac", "api", "firmware"}, call("api_firmware"), nil).leaf = true
    entry({"admin", "network", "wifi_ac", "api", "log"}, call("api_log"), nil).leaf = true
    entry({"admin", "network", "wifi_ac", "api", "settings"}, call("api_settings"), nil).leaf = true
    entry({"admin", "network", "wifi_ac", "api", "template_manage"}, call("api_template_manage"), nil).leaf = true
    entry({"admin", "network", "wifi_ac", "api", "role_manage"}, call("api_role_manage"), nil).leaf = true
    entry({"admin", "network", "wifi_ac", "api", "factory_reset"}, call("api_factory_reset"), nil).leaf = true
    entry({"admin", "network", "wifi_ac", "api", "storage_info"}, call("api_storage_info"), nil).leaf = true
    entry({"admin", "network", "wifi_ac", "api", "overview"}, call("api_overview"), nil).leaf = true
    entry({"admin", "network", "wifi_ac", "api", "txpower_range"}, call("api_txpower_range"), nil).leaf = true
    entry({"admin", "network", "wifi_ac", "api", "trend_data"}, call("api_trend_data"), nil).leaf = true
    entry({"admin", "network", "wifi_ac", "api", "collect_trend"}, call("api_collect_trend"), nil).leaf = true
    entry({"admin", "network", "wifi_ac", "api", "set_client_limit"}, call("api_set_client_limit"), nil).leaf = true
    entry({"admin", "network", "wifi_ac", "api", "set_power", ":mac", ":vendor"}, call("api_set_power"), nil).leaf = true
    entry({"admin", "network", "wifi_ac", "api", "firmware", "queue", "update"}, call("api_firmware_queue_update"), nil).leaf = true
    entry({"admin", "network", "wifi_ac", "api", "vendors"}, call("api_vendors"), nil).leaf = true
    entry({"admin", "network", "wifi_ac", "api", "models"}, call("api_models"), nil).leaf = true
    entry({"admin", "network", "wifi_ac", "api", "upgrade_queue"}, call("api_upgrade_queue"), nil).leaf = true
    entry({"admin", "network", "wifi_ac", "api", "upgrade_stage"}, call("api_upgrade_stage"), nil).leaf = true
end

-- TOKEN/SECRET 文件路径
local TOKEN_FILE = "/etc/wifi-ac/token"
local SECRET_FILE = "/etc/wifi-ac/secret"

local function get_token_file()
    local lfs = require "luci.fs"
    local token = lfs.readfile(TOKEN_FILE)
    if token then
        return token:gsub("%s+$", "")
    end
    -- 回退到UCI
    local uci = require "luci.model.uci".cursor()
    return uci:get("wifi_ac", "global", "token") or "default_token"
end

local function get_secret_file()
    local lfs = require "luci.fs"
    local secret = lfs.readfile(SECRET_FILE)
    if secret then
        return secret:gsub("%s+$", "")
    end
    -- 回退到UCI
    local uci = require "luci.model.uci".cursor()
    return uci:get("wifi_ac", "global", "secret") or "default_secret"
end

-- 获取全局token
local function get_token()
    return get_token_file()
end

-- 校验token
local function check_token(token)
    return token and token == get_token()
end

-- 操作级别/角色校验（可扩展为更细粒度）
local function check_permission(user, action)
    -- 读取角色权限配置（如/etc/wifi-ac/roles.json）
    local json = require "luci.jsonc"
    local lfs = require "luci.fs"
    local data = lfs.readfile("/etc/wifi-ac/roles.json")
    local roles = data and json.parse(data) or {roles={}}
    -- 查找用户角色
    local user_role
    for _, role in ipairs(roles.roles or {}) do
        if role.users and type(role.users) == "table" then
            for _, u in ipairs(role.users) do
                if u == user then user_role = role; break end
            end
        end
        if user_role then break end
    end
    -- 权限判断
    if user_role and user_role.perms then
        if user_role.perms[action] then return true end
    end
    -- 默认admin全权限，普通用户只读
    if user == "admin" then return true end
    if action == "read" then return true end
    return false
end

-- UDP命令下发，带token，预留签名/白名单校验
local function send_udp_command(mac, command, param, retry)
    local nixio = require("nixio")
    local token = get_token()
    local s = nixio.socket("inet", "dgram")
    if not s then return false end
    local ip = luci.sys.exec(string.format("arp -n | grep %s | awk '{print $1}'", mac)):gsub("\n", "")
    if not ip or ip == "" then return false end
    local payload = string.format("%s,%s,%s,%s", mac, command, tostring(param or ""), token)
    s:sendto(payload, ip, 9090)
    s:close()
    return true
end

-- UDP命令下发，带ACK确认与重试机制
local function send_udp_command_with_ack(mac, command, param, retry)
    local socket = require("luci.sys.socket")
    local token = get_token_file()
    local secret = get_secret_file()
    local s = socket("AF_INET", "SOCK_DGRAM", 0)
    if not s then return false, "socket error" end
    local ip = luci.sys.exec(string.format("arp -n | grep %s | awk '{print $1}'", mac)):gsub("\n", "")
    if not ip or ip == "" then return false, "no ip" end
    -- 生成签名
    local signature = require("luci.util").md5(mac..command..tostring(param or "")..token..secret)
    local payload = string.format("%s,%s,%s,%s,%s", mac, command, tostring(param or ""), token, signature)
    local ack_ok = false
    retry = tonumber(retry) or 2
    for i=1,retry do
        socket.sendto(s, payload, ip, 9090)
        -- 等待ACK
        socket.settimeout(s, 1)
        local data = socket.recv(s, 128)
        if data and data:match("^ACK:"..mac..","..command) then
            ack_ok = true
            break
        end
    end
    socket.close(s)
    return ack_ok
end

-- Web API敏感操作token和权限双重校验
function api_device_batch()
    local action = luci.http.formvalue("action")
    local macs = luci.http.formvalue("macs")
    local token = luci.http.formvalue("token")
    local user = luci.http.formvalue("user") or "guest"
    if not check_token(token) then
        luci.http.status(403, "Forbidden")
        luci.http.write_json({code=403, msg="无效Token"})
        return
    end
    if not check_permission(user, "write") then
        luci.http.status(403, "Forbidden")
        luci.http.write_json({code=403, msg="无权限"})
        return
    end
    local result = require("luci.model.wifi_ac").batch_device_action(action, macs)
    local summary = { success = 0, fail = 0, detail = result }
    for mac, v in pairs(result) do
        if tostring(v):match("^ok") then
            summary.success = summary.success + 1
        else
            summary.fail = summary.fail + 1
            -- 失败自动重试一次
            local retry = require("luci.model.wifi_ac").batch_device_action(action, mac)
            summary.detail[mac .. "_retry"] = retry[mac]
            -- 推送告警
            require("luci.model.wifi_ac").push_alarm_ws("AP " .. mac .. " 批量操作失败: " .. tostring(v))
        end
    end
    luci.http.prepare_content("application/json")
    luci.http.write_json(summary)
end

-- 日志API权限校验与审计
function api_log()
    local method = luci.http.getenv("REQUEST_METHOD")
    local model = require("luci.model.wifi_ac")
    local user = luci.http.formvalue("user")
    local token = luci.http.formvalue("token")
    if not check_token(token) then
        luci.http.status(403, "Forbidden")
        luci.http.write_json({code=403, msg="无效Token"})
        return
    end
    if not check_permission(user, "read") then
        luci.http.status(403, "Forbidden")
        luci.http.write_json({code=403, msg="无权限"})
        return
    end
    if method == "GET" then
        local params = {
            type = luci.http.formvalue("type"),
            vendor = luci.http.formvalue("vendor"),
            keyword = luci.http.formvalue("keyword"),
            since = luci.http.formvalue("since"),
            ["until"] = luci.http.formvalue("until"),
            user = luci.http.formvalue("user"),
            export = luci.http.formvalue("export")
        }
        local result = model.query_log(params)
        if params.export == "csv" then
            luci.http.header("Content-Disposition", "attachment; filename=wifi-ac-log.csv")
            luci.http.prepare_content("text/csv")
            luci.http.write(result)
        elseif params.export == "pdf" then
            luci.http.header("Content-Disposition", "attachment; filename=wifi-ac-log.pdf")
            luci.http.prepare_content("application/pdf")
            luci.http.write(result)
        else
            luci.http.prepare_content("application/json")
            luci.http.write_json(result)
        end
    elseif method == "POST" then
        local params = luci.http.formvalue()
        local result = model.add_log(params)
        luci.http.prepare_content("application/json")
        luci.http.write_json(result)
    else
        luci.http.status(405, "Method Not Allowed")
    end
end

-- Ubus接口本地权限校验（仅允许白名单进程/用户调用）
local function ubus_local_auth()
    -- 仅允许root或指定进程名
    local uid = tonumber(luci.sys.exec("id -u"))
    if uid ~= 0 then return false end
    -- 可扩展：校验/proc/self/cmdline是否为白名单进程
    return true
end

-- 示例：通过ubus调用时加本地权限校验
function api_set_client_limit()
    if not ubus_local_auth() then
        luci.http.status(403, "Forbidden")
        luci.http.write_json({status="fail", message="本地权限不足"})
        return
    end
    local params = luci.http.formvalue()
    local mac = params.mac
    local limit = tonumber(params.limit)
    local vendor = params.vendor or ""
    if not mac or not limit then
        luci.http.prepare_content("application/json")
        luci.http.write_json({status="fail", message="参数缺失"})
        return
    end
    if vendor:lower() == "openwrt" then
        -- 通过ubus调用底层驱动
        local ubus = require("ubus")
        local conn = ubus.connect()
        if conn then
            conn:call("wifi", "set_client_limit", {mac=mac, limit=limit})
            conn:close()
        end
        send_udp_command(mac, "reload_config")
        luci.http.prepare_content("application/json")
        luci.http.write_json({status="success"})
    else
        -- 三方AP适配待开发
        luci.http.prepare_content("application/json")
        luci.http.write_json({status="not_supported", message="三方AP控制接口待开发"})
    end
end

-- 支持动态筛选与搜索
function api_device_list()
    local vendor = luci.http.formvalue("vendor")
    local status = luci.http.formvalue("status")
    local firmware = luci.http.formvalue("firmware")
    local keyword = luci.http.formvalue("keyword")
    local devices = require("luci.model.wifi_ac").get_device_list({
        vendor = vendor,
        status = status,
        firmware = firmware,
        keyword = keyword
    })
    luci.http.prepare_content("application/json")
    luci.http.write_json(devices)
end

-- 设备详情，含离线原因
function api_device_detail()
    local mac = luci.http.formvalue("mac")
    local detail = require("luci.model.wifi_ac").get_device_detail(mac)
    if detail.status ~= "online" then
        if require("luci.model.wifi_ac").get_offline_reason then
            detail.offline_reason = require("luci.model.wifi_ac").get_offline_reason(mac)
        end
    end
    luci.http.prepare_content("application/json")
    luci.http.write_json(detail)
end

-- 批量操作，返回进度与详细结果，支持失败自动重试
function api_device_batch()
    local action = luci.http.formvalue("action")
    local macs = luci.http.formvalue("macs")
    local token = luci.http.formvalue("token")
    local user = luci.http.formvalue("user") or "guest"
    if not check_token(token) then
        luci.http.status(403, "Forbidden")
        luci.http.write_json({code=403, msg="无效Token"})
        return
    end
    if not check_permission(user, "write") then
        luci.http.status(403, "Forbidden")
        luci.http.write_json({code=403, msg="无权限"})
        return
    end
    local result = require("luci.model.wifi_ac").batch_device_action(action, macs)
    local summary = { success = 0, fail = 0, detail = result }
    for mac, v in pairs(result) do
        if tostring(v):match("^ok") then
            summary.success = summary.success + 1
        else
            summary.fail = summary.fail + 1
            -- 失败自动重试一次
            local retry = require("luci.model.wifi_ac").batch_device_action(action, mac)
            summary.detail[mac .. "_retry"] = retry[mac]
            -- 推送告警
            require("luci.model.wifi_ac").push_alarm_ws("AP " .. mac .. " 批量操作失败: " .. tostring(v))
        end
    end
    luci.http.prepare_content("application/json")
    luci.http.write_json(summary)
end

-- 自动/手动添加设备，支持UDP、mDNS、HTTP多种发现方式，后端唯一性校验
function api_device_add()
    local params = luci.http.formvalue()
    local model = require("luci.model.wifi_ac")
    -- UDP广播发现
    if params.discover == "1" and model.auto_discover_devices then
        local result = model.auto_discover_devices()
        luci.http.prepare_content("application/json")
        luci.http.write_json(result)
        return
    end
    -- mDNS发现（跨网段，需AP端支持mDNS responder，守护进程采集写入/tmp/wifi-ac/mdns_devices.json）
    if params.mdns == "1" and model.mdns_discover_devices then
        local result = model.mdns_discover_devices()
        luci.http.prepare_content("application/json")
        luci.http.write_json(result)
        return
    end
    -- HTTP主动注册发现（AP端定期向AC HTTP接口注册，守护进程采集写入/tmp/wifi-ac/http_devices.json）
    if params.http == "1" and model.http_discover_devices then
        local result = model.http_discover_devices()
        luci.http.prepare_content("application/json")
        luci.http.write_json(result)
        return
    end
    -- 精确添加，后端唯一性校验
    if params.mac and params.ip then
        local exists = false
        local uci = require "luci.model.uci".cursor()
        uci:foreach("wifi_ac", "device", function(s)
            if (s.mac and s.mac:lower() == params.mac:lower()) or (s.ip and s.ip == params.ip) then
                exists = true
            end
        end)
        if exists then
            luci.http.prepare_content("application/json")
            luci.http.write_json({code=2, msg="MAC或IP已存在，请勿重复添加"})
            return
        end
    end
    local result = model.add_device(params)
    luci.http.prepare_content("application/json")
    luci.http.write_json(result)
end

-- 配置模板调用与下发，支持本地模板选择
function api_device_template()
    local mac = luci.http.formvalue("mac")
    local vendor = luci.http.formvalue("vendor")
    local template_name = luci.http.formvalue("template")
    local apply = luci.http.formvalue("apply")
    local model = require("luci.model.wifi_ac")
    local template
    if template_name and model.get_local_template then
        template = model.get_local_template(vendor, template_name)
    else
        template = model.get_template(vendor)
    end
    if apply == "1" and mac and template then
        model.apply_template(mac, template)
    end
    luci.http.prepare_content("application/json")
    luci.http.write_json(template or {})
end

-- WebSocket推送接口（需守护进程或uhttpd/ws实现）
function api_ws_status()
    luci.http.status(501, "Not Implemented")
end

-- 模板管理API接口：获取模板列表、创建模板
function api_templates()
    local method = luci.http.getenv("REQUEST_METHOD")
    local model = require("luci.model.wifi_ac")
    if method == "GET" then
        local vendor = luci.http.formvalue("vendor")
        local result = model.get_template_list({vendor=vendor})
        luci.http.prepare_content("application/json")
        luci.http.write_json(result)
    elseif method == "POST" then
        local params = luci.http.formvalue()
        -- config字段为json字符串，需解析
        if params.config and type(params.config) == "string" then
            local json = require "luci.jsonc"
            params.config = json.parse(params.config)
        end
        local result = model.create_template(params)
        luci.http.prepare_content("application/json")
        luci.http.write_json(result)
    else
        luci.http.status(405, "Method Not Allowed")
    end
end

-- 性能优化API
function api_optimization()
    local action = luci.http.formvalue("action")
    local params = luci.http.formvalue()
    local model = require("luci.model.wifi_ac")
    local result
    if action == "auto" then
        result = model.optimize_auto(params)
    elseif action == "manual" then
        result = model.optimize_manual(params)
    elseif action == "progress" then
        result = model.optimize_progress()
    elseif action == "apply_template" then
        result = model.optimize_apply_template(params)
    else
        result = {code=1, msg="未知操作"}
    end
    luci.http.prepare_content("application/json")
    luci.http.write_json(result)
end

function api_optimization_threshold()
    local model = require("luci.model.wifi_ac")
    if luci.http.getenv("REQUEST_METHOD") == "POST" then
        local params = luci.http.formvalue()
        local result = model.optimize_set_threshold(params)
        luci.http.prepare_content("application/json")
        luci.http.write_json(result)
    else
        local result = model.optimize_get_threshold()
        luci.http.prepare_content("application/json")
        luci.http.write_json(result)
    end
end

function api_optimization_trend()
    local model = require("luci.model.wifi_ac")
    local result = model.optimize_trend_data()
    luci.http.prepare_content("application/json")
    luci.http.write_json(result)
end

-- 负载均衡阈值设置API
function api_load_balance()
    local params = luci.http.formvalue()
    local model = require("luci.model.wifi_ac")
    local result = model.set_load_balance(params)
    luci.http.prepare_content("application/json")
    luci.http.write_json(result)
end

-- 信道热力图数据API
function api_channel_heatmap()
    local model = require("luci.model.wifi_ac")
    local data = model.get_channel_heatmap()
    luci.http.prepare_content("application/json")
    luci.http.write_json({code=0, data=data})
end

-- 手动设置AP信道
function api_set_channel()
    local mac = luci.http.formvalue("mac")
    local channel = luci.http.formvalue("channel")
    if not mac or not channel then
        luci.http.prepare_content("application/json")
        luci.http.write_json({code=1, msg="参数缺失"})
        return
    end
    local sys = require "luci.sys"
    local cmd = string.format("ubus call wifi.device '{\"mac\":\"%s\",\"action\":\"set_channel\",\"channel\":%s}'", mac, channel)
    local result = sys.exec(cmd)
    luci.http.prepare_content("application/json")
    luci.http.write_json({code=0, msg="已下发", result=result})
end

-- 批量应用策略模板API
function api_apply_template()
    local json = require "luci.jsonc"
    local params = luci.http.content() and json.parse(luci.http.content()) or {}
    local model = require("luci.model.wifi_ac")
    local result = model.apply_template_batch(params)
    luci.http.prepare_content("application/json")
    luci.http.write_json(result)
end

-- WebSocket实时推送接口
function ws_status(env)
    local http = require "luci.http"
    local ws = require "luci.http.websocket"
    local ubus = require "ubus"
    local json = require "luci.jsonc"

    -- 权限校验（LuCI会话）
    if not http.formvalue("stok") and not http.getenv("HTTP_COOKIE") then
        http.status(403, "Forbidden")
        return
    end

    local ws_sock = ws.websocket(http)
    if not ws_sock then
        http.status(400, "Bad Request")
        return
    end

    local function ws_log(msg)
        local f = io.open("/var/log/wifi-ac/websocket.log", "a")
        if f then
            f:write(os.date("%Y-%m-%d %H:%M:%S") .. " " .. msg .. "\n")
            f:close()
        end
    end

    ws_log("WebSocket connected")

    local conn = ubus.connect()
    if not conn then
        ws_sock:send(json.stringify({type="error", msg="ubus unavailable"}))
        ws_sock:close()
        return
    end

    local running = true
    local function on_event(ev)
        if running and ev and ev.data then
            local ok, err = pcall(function() ws_sock:send(json.stringify(ev.data)) end)
            if not ok then
                ws_log("WebSocket push failed: " .. tostring(err))
            end
        end
    end

    -- 订阅wifi_ac.status_update事件
    local subid = conn:listen({
        ["wifi_ac.status_update"] = on_event
    })

    -- 保持连接，简单心跳
    while running do
        local msg, typ = ws_sock:recv(30)
        if typ == "close" or not msg then
            running = false
            break
        end
    end

    conn:unlisten(subid)
    ws_sock:close()
    ws_log("WebSocket closed")
end

-- WebSocket状态推送服务
local ok_ws, ws = pcall(require, "luci.http.websocket")
if ok_ws and ws and ws.register then
    ws.register("/ws/wifi-ac/status", function(socket)
        -- 权限校验（仅认证用户）
        if not luci.http.cookie_get("luci_session") then
            socket:close()
            return
        end

        -- 订阅ubus事件
        local ubus = require("luci.ubus")
        local ubus_ctx = ubus.connect()
        if not ubus_ctx then
            socket:close()
            return
        end
        local event_id = ubus_ctx:subscribe("wifi_ac", "status_update", function(data)
            -- 标准化推送结构
            local payload = {}
            if type(data) == "string" then
                local json = require "luci.jsonc"
                data = json.parse(data)
            end
            if data and data.devices then
                payload.devices = data.devices
                payload.type = "status_update"
                payload.mode = data.mode or "full"
            elseif data and data.mac then
                payload.devices = {data}
                payload.type = "status_update"
                payload.mode = "delta"
            else
                payload = {type="status_update", devices={}, mode="unknown"}
            end
            socket:send(require("luci.jsonc").stringify(payload))
        end)

        -- 保持连接循环
        while true do
            if not socket:is_open() then
                ubus_ctx:unsubscribe(event_id)
                ubus_ctx:close()
                break
            end
            luci.sys.sleep(1)
        end
    end)

    -- WebSocket推送优化进度/状态
    ws.register("/ws/wifi-ac/optimization", function(socket)
        if not luci.http.cookie_get("luci_session") then
            socket:close()
            return
        end
        local ubus = require("luci.ubus")
        local ubus_ctx = ubus.connect()
        if not ubus_ctx then
            socket:close()
            return
        end
        local event_id = ubus_ctx:subscribe("wifi_ac", "optimization_progress", function(data)
            socket:send(data)
        end)
        while true do
            if not socket:is_open() then
                ubus_ctx:unsubscribe(event_id)
                ubus_ctx:close()
                break
            end
            luci.sys.sleep(1)
        end
    end)

    -- WebSocket实时告警推送服务
    ws.register("/ws/wifi-ac/alarm", function(socket)
        if not luci.http.cookie_get("luci_session") then
            socket:close()
            return
        end
        local ubus = require("luci.ubus")
        local ubus_ctx = ubus.connect()
        if not ubus_ctx then
            socket:close()
            return
        end
        local event_id = ubus_ctx:subscribe("wifi_ac", "alarm", function(data)
            socket:send(data)
        end)
        while true do
            if not socket:is_open() then
                ubus_ctx:unsubscribe(event_id)
                ubus_ctx:close()
                break
            end
            luci.sys.sleep(1)
        end
    end)
end

function api_trends()
    local mac = luci.http.formvalue("mac")
    local days = tonumber(luci.http.formvalue("days")) or 7
    local model = require("luci.model.wifi_ac")
    local data = model.query_trend_data(mac, days)
    luci.http.prepare_content("application/json")
    luci.http.write_json(data)
end

function api_firmware()
    local method = luci.http.getenv("REQUEST_METHOD")
    local model = require("luci.model.wifi_ac")
    if method == "GET" then
        if luci.http.formvalue("status") then
            local result = model.get_upgrade_status()
            luci.http.prepare_content("application/json")
            luci.http.write_json(result)
            return
        end
        local vendor = luci.http.formvalue("vendor")
        local model_name = luci.http.formvalue("model")
        local result = model.get_firmware_list({vendor=vendor, model=model_name})
        luci.http.prepare_content("application/json")
        luci.http.write_json(result)
    elseif method == "POST" then
        local result = model.upload_firmware()
        luci.http.prepare_content("application/json")
        luci.http.write_json(result)
    elseif method == "PUT" then
        local params = luci.http.formvalue()
        local result = model.batch_upgrade(params)
        luci.http.prepare_content("application/json")
        luci.http.write_json(result)
    else
        luci.http.status(405, "Method Not Allowed")
    end
end

function api_firmware_queue_update()
    local json = require "luci.jsonc"
    local uci = require "luci.model.uci".cursor()
    local new_order = luci.http.content() and json.parse(luci.http.content()) or {}
    if type(new_order) == "table" then
        uci:set("firmware", "queue", "order", table.concat(new_order, ","))
        uci:commit("firmware")
        luci.http.prepare_content("application/json")
        luci.http.write_json({status = "success"})
    else
        luci.http.prepare_content("application/json")
        luci.http.write_json({status = "fail", msg = "参数错误"})
    end
end

function api_log()
    local method = luci.http.getenv("REQUEST_METHOD")
    local model = require("luci.model.wifi_ac")
    local user = luci.http.formvalue("user")
    local token = luci.http.formvalue("token")
    if not check_token(token) then
        luci.http.status(403, "Forbidden")
        luci.http.write_json({code=403, msg="无效Token"})
        return
    end
    if not check_permission(user, "read") then
        luci.http.status(403, "Forbidden")
        luci.http.write_json({code=403, msg="无权限"})
        return
    end
    if method == "GET" then
        local params = {
            type = luci.http.formvalue("type"),
            vendor = luci.http.formvalue("vendor"),
            keyword = luci.http.formvalue("keyword"),
            since = luci.http.formvalue("since"),
            ["until"] = luci.http.formvalue("until"),
            user = luci.http.formvalue("user"),
            export = luci.http.formvalue("export")
        }
        local result = model.query_log(params)
        if params.export == "csv" then
            luci.http.header("Content-Disposition", "attachment; filename=wifi-ac-log.csv")
            luci.http.prepare_content("text/csv")
            luci.http.write(result)
        elseif params.export == "pdf" then
            luci.http.header("Content-Disposition", "attachment; filename=wifi-ac-log.pdf")
            luci.http.prepare_content("application/pdf")
            luci.http.write(result)
        else
            luci.http.prepare_content("application/json")
            luci.http.write_json(result)
        end
    elseif method == "POST" then
        local params = luci.http.formvalue()
        local result = model.add_log(params)
        luci.http.prepare_content("application/json")
        luci.http.write_json(result)
    else
        luci.http.status(405, "Method Not Allowed")
    end
end

function api_settings()
    local method = luci.http.getenv("REQUEST_METHOD")
    local model = require("luci.model.wifi_ac")
    if method == "GET" then
        local result = model.get_settings()
        luci.http.prepare_content("application/json")
        luci.http.write_json(result)
    elseif method == "POST" then
        local params = luci.http.formvalue()
        if params.action == "test_radius" then
            local result = model.test_radius(params)
            luci.http.prepare_content("application/json")
            luci.http.write_json(result)
            return
        end
        local result = model.set_settings(params)
        luci.http.prepare_content("application/json")
        luci.http.write_json(result)
    else
        luci.http.status(405, "Method Not Allowed")
    end
end

function api_template_manage()
    local model = require("luci.model.wifi_ac")
    local method = luci.http.getenv("REQUEST_METHOD")
    if method == "GET" then
        local result = model.list_templates_manage()
        luci.http.prepare_content("application/json")
        luci.http.write_json(result)
    elseif method == "POST" then
        local params = luci.http.formvalue()
        local result = model.save_template_manage(params)
        luci.http.prepare_content("application/json")
        luci.http.write_json(result)
    elseif method == "DELETE" then
        local params = luci.http.formvalue()
        local result = model.delete_template_manage(params)
        luci.http.prepare_content("application/json")
        luci.http.write_json(result)
    else
        luci.http.status(405, "Method Not Allowed")
    end
end

function api_role_manage()
    local model = require("luci.model.wifi_ac")
    local method = luci.http.getenv("REQUEST_METHOD")
    if method == "GET" then
        local result = model.list_roles()
        luci.http.prepare_content("application/json")
        luci.http.write_json(result)
    elseif method == "POST" then
        local params = luci.http.formvalue()
        local result = model.save_roles(params)
        luci.http.prepare_content("application/json")
        luci.http.write_json(result)
    elseif method == "PUT" then
        local params = luci.http.formvalue()
        local result = model.import_roles(params)
        luci.http.prepare_content("application/json")
        luci.http.write_json(result)
    elseif method == "DELETE" then
        local params = luci.http.formvalue()
        local result = model.delete_role(params)
        luci.http.prepare_content("application/json")
        luci.http.write_json(result)
    else
        luci.http.status(405, "Method Not Allowed")
    end
end

function api_factory_reset()
    local model = require("luci.model.wifi_ac")
    local params = luci.http.formvalue()
    local result = model.factory_reset(params)
    luci.http.prepare_content("application/json")
    luci.http.write_json(result)
end

function api_storage_info()
    local model = require("luci.model.wifi_ac")
    local result = model.get_storage_info()
    luci.http.prepare_content("application/json")
    luci.http.write_json(result)
end

function api_overview()
    local model = require("luci.model.wifi_ac")
    local result = model.get_overview_data()
    luci.http.prepare_content("application/json")
    luci.http.write_json(result)
end

function api_txpower_range()
    local vendor = luci.http.formvalue("vendor")
    local model = luci.http.formvalue("model")
    local range = require("luci.model.wifi_ac").get_txpower_range(vendor, model)
    luci.http.prepare_content("application/json")
    luci.http.write_json(range)
end

function api_trend_data()
    local model = require("luci.model.wifi_ac")
    local data = model.get_trend_data()
    luci.http.prepare_content("application/json")
    luci.http.write_json(data)
end

-- 定时采集趋势数据（可由定时任务调用）
function api_collect_trend()
    require("luci.model.wifi_ac").collect_trend_data()
    luci.http.prepare_content("application/json")
    luci.http.write_json({code=0, msg="ok"})
end

local nixio = require("nixio")

-- 发送UDP命令到AP（端口9090）
local function send_udp_command(mac, command, param)
    local s = nixio.socket("inet", "dgram")
    if not s then return false end

    -- 通过ARP获取AP IP（假设AP已注册）
    local ip = luci.sys.exec(string.format("arp -n | grep %s | awk '{print $1}'", mac)):gsub("\n", "")
    if not ip or ip == "" then return false end

    -- 获取token（假设从UCI配置读取）
    local uci = require "luci.model.uci".cursor()
    local token = uci:get("wifi_ac", "global", "token") or "default_token"

    -- 协议格式：<mac>,<command_type>,<params>,<token>
    local payload = string.format("%s,%s,%s,%s", mac, command, tostring(param or ""), token)
    s:sendto(payload, ip, 9090)
    s:close()
    return true
end

-- API: 设置AP客户端数限制（支持OpenWrt原生AP，三方AP可扩展）
function api_set_client_limit()
    local params = luci.http.formvalue()
    local mac = params.mac
    local limit = tonumber(params.limit)
    local vendor = params.vendor or ""
    if not mac or not limit then
        luci.http.prepare_content("application/json")
        luci.http.write_json({status="fail", message="参数缺失"})
        return
    end
    if vendor:lower() == "openwrt" then
        -- 通过ubus调用底层驱动
        local ubus = require("ubus")
        local conn = ubus.connect()
        if conn then
            conn:call("wifi", "set_client_limit", {mac=mac, limit=limit})
            conn:close()
        end
        send_udp_command(mac, "reload_config")
        luci.http.prepare_content("application/json")
        luci.http.write_json({status="success"})
    else
        -- 三方AP适配待开发
        luci.http.prepare_content("application/json")
        luci.http.write_json({status="not_supported", message="三方AP控制接口待开发"})
    end
end

function api_set_power(mac, vendor)
    local power = tonumber(luci.http.content() or luci.http.formvalue("power"))
    if not mac or not vendor or not power then
        luci.http.prepare_content("application/json")
        luci.http.write_json({status="fail", message="参数缺失"})
        return
    end
    if vendor:lower() == "openwrt" then
        local ubus = require("ubus")
        local conn = ubus.connect()
        if conn then
            conn:call("wifi", "set_txpower", {mac=mac, power=power})
            conn:close()
        end
        luci.http.prepare_content("application/json")
        luci.http.write_json({status="success", power=power})
    else
        luci.http.prepare_content("application/json")
        luci.http.write_json({status="not_implemented", message="三方厂商功率接口待开发"})
    end
end

-- 支持AP主动心跳/状态上报（见AP端ap_agent/ubus实现，AC端可定期拉取和被动接收）
-- 相关接口已在AP端ubus和UDP心跳实现，AC端通过ubus call wifi.status或UDP监听/定时拉取

-- 自动发现支持mDNS、HTTP等多种方式（部分需AP端配合）
function discover_devices()
    -- 1. UDP广播发现（局域网内有效，跨网段易失效）
    -- ...原有UDP扫描代码...
    -- 2. mDNS发现（需AP端支持mDNS响应）
    -- 3. HTTP主动注册（AP端定期向AC HTTP接口注册）
    -- 实际生产环境建议多方式结合，提升发现率
    -- ...existing code...
end

function api_vendors()
    local model = require("luci.model.wifi_ac")
    local vendors = model.get_all_vendors and model.get_all_vendors() or {}
    luci.http.prepare_content("application/json")
    luci.http.write_json(vendors)
end

function api_models()
    local vendor = luci.http.formvalue("vendor")
    local model_m = require("luci.model.wifi_ac")
    local models = model_m.get_models_by_vendor and model_m.get_models_by_vendor(vendor) or {}
    luci.http.prepare_content("application/json")
    luci.http.write_json(models)
end

-- 升级队列顺序保存API（支持拖拽排序）
function api_upgrade_queue()
    local macs = luci.http.formvalue("macs")
    if not macs then
        luci.http.prepare_content("application/json")
        luci.http.write_json({status="fail", msg="参数缺失"})
        return
    end
    local lfs = require "luci.fs"
    local path = "/etc/wifi-ac/upgrade_queue.json"
    lfs.writefile(path, macs)
    luci.http.prepare_content("application/json")
    luci.http.write_json({status="success"})
end

-- 分阶段升级API
function api_upgrade_stage()
    local stage = tonumber(luci.http.formvalue("stage"))
    if not stage or stage < 1 then
        luci.http.prepare_content("application/json")
        luci.http.write_json({status="fail", msg="参数错误"})
        return
    end
    -- 读取升级队列
    local lfs = require "luci.fs"
    local path = "/etc/wifi-ac/upgrade_queue.json"
    local macs = lfs.readfile(path) or ""
    local mac_list = {}
    for mac in string.gmatch(macs, "[^,]+") do table.insert(mac_list, mac) end
    -- 分阶段下发升级
    local sys = require "luci.sys"
    local total = #mac_list
    local idx = 1
    while idx <= total do
        for i = idx, math.min(idx+stage-1, total) do
            sys.exec("ubus call wifi.device '{\"mac\":\""..mac_list[i].."\",\"action\":\"upgrade\"}'")
        end
        idx = idx + stage
        nixio.nanosleep(10) -- 每阶段间隔10秒
    end
    luci.http.prepare_content("application/json")
    luci.http.write_json({status="success", msg="分阶段升级已下发"})
end

-- 日志存储占用展示API
function api_storage_info()
    local stat = io.popen("du -sh /var/log/wifi-ac 2>/dev/null")
    local info = stat and stat:read("*a") or ""
    if stat then stat:close() end
    luci.http.prepare_content("application/json")
    luci.http.write_json({storage=info})
end
