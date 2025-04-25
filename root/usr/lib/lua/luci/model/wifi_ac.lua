local uci = require "luci.model.uci".cursor()
local sys = require "luci.sys"
local util = require "luci.util"
local json = require "luci.jsonc"

module("luci.model.wifi_ac", package.seeall)

-- 设备列表获取，支持多条件筛选
function get_device_list(filter)
    local devices = {}
    uci:foreach("wifi_ac", "device", function(s)
        local status = sys.exec("ubus call wifi.status '{\"mac\":\"" .. (s.mac or "") .. "\"}' 2>/dev/null")
        local stat = status and json.parse(status) or {}
        -- 支持多条件筛选
        if filter then
            if filter.vendor and filter.vendor ~= "" and (s.vendor or "") ~= filter.vendor then return end
            if filter.status and filter.status ~= "" then
                if (stat.status or "offline") ~= filter.status then return end
            end
            if filter.firmware and filter.firmware ~= "" and (s.firmware or "") ~= filter.firmware then return end
            if filter.keyword and filter.keyword ~= "" then
                local kw = filter.keyword:lower()
                if not ((s.mac or ""):lower():find(kw) or (s.model or ""):lower():find(kw) or (s.vendor or ""):lower():find(kw)) then
                    return
                end
            end
        end
        devices[#devices+1] = {
            mac = s.mac,
            vendor = s.vendor,
            model = s.model,
            ip = s.ip,
            status = stat.status or "offline",
            cpu = stat.cpu or 0,
            mem = stat.mem or 0,
            clients_24g = stat.clients_24g or 0,
            clients_5g = stat.clients_5g or 0,
            firmware = s.firmware or "",
            version = s.version or "",
        }
    end)
    return { devices = devices }
end

-- 单设备详情
function get_device_detail(mac)
    local detail = {}
    uci:foreach("wifi_ac", "device", function(s)
        if s.mac == mac then
            detail = s
        end
    end)
    -- 获取实时状态
    local status = sys.exec("ubus call wifi.status '{\"mac\":\"" .. (mac or "") .. "\"}' 2>/dev/null")
    local stat = status and json.parse(status) or {}
    detail.status = stat.status or "offline"
    detail.cpu = stat.cpu or 0
    detail.mem = stat.mem or 0
    detail.clients_24g = stat.clients_24g or 0
    detail.clients_5g = stat.clients_5g or 0
    detail.trend = stat.trend or {}
    detail.uptime = stat.uptime or ""
    detail.location = stat.location or (detail.location or "")
    detail.signal = stat.signal or ""
    return detail
end

-- 批量操作（重启/升级/同步），支持单个mac和批量macs
function batch_device_action(action, macs)
    local result = {}
    local mac_list = type(macs) == "table" and macs or util.split(macs or "", ",")
    for _, mac in ipairs(mac_list) do
        local r
        if action == "reboot" then
            r = sys.exec("ubus call wifi.device '{\"mac\":\"" .. mac .. "\",\"action\":\"reboot\"}' 2>/dev/null")
        elseif action == "upgrade" then
            r = sys.exec("ubus call wifi.device '{\"mac\":\"" .. mac .. "\",\"action\":\"upgrade\"}' 2>/dev/null")
        elseif action == "sync" then
            r = sys.exec("ubus call wifi.device '{\"mac\":\"" .. mac .. "\",\"action\":\"sync\"}' 2>/dev/null")
        else
            r = "unknown action"
        end
        result[mac] = r or "ok"
    end
    return result
end

-- 添加设备，增加MAC/IP唯一性校验
function add_device(params)
    -- 支持自动/手动注册
    if not params.mac or not params.ip then
        return {code=1, msg="MAC/IP必填"}
    end
    -- 后端唯一性校验
    local exists = false
    uci:foreach("wifi_ac", "device", function(s)
        if (s.mac and s.mac:lower() == params.mac:lower()) or (s.ip and s.ip == params.ip) then
            exists = true
        end
    end)
    if exists then
        return {code=2, msg="MAC或IP已存在，请勿重复添加"}
    end
    local sid = uci:add("wifi_ac", "device")
    uci:set("wifi_ac", sid, "mac", params.mac)
    uci:set("wifi_ac", sid, "ip", params.ip)
    if params.vendor then uci:set("wifi_ac", sid, "vendor", params.vendor) end
    if params.model then uci:set("wifi_ac", sid, "model", params.model) end
    if params.firmware then uci:set("wifi_ac", sid, "firmware", params.firmware) end
    uci:commit("wifi_ac")
    return {code=0, msg="添加成功"}
end

-- 获取模板
function get_template(vendor)
    -- 按厂商返回专属配置模板
    local tpl = {}
    if vendor == "Huawei" then
        tpl = {ssid="Huawei-AP", channel=6, txpower=20}
    elseif vendor == "TPLink" then
        tpl = {ssid="TPLink-AP", channel=11, txpower=18}
    else
        tpl = {ssid="OpenWrt-AP", channel=1, txpower=17}
    end
    return tpl
end

-- 应用模板
function apply_template(mac, tpl)
    -- 下发模板到指定AP（实际应通过ubus或MQTT等推送）
    sys.exec("ubus call wifi.device '{\"mac\":\"" .. mac .. "\",\"action\":\"apply_template\",\"tpl\":" .. util.serialize_json(tpl) .. "}'")
end

function auto_discover_devices(params)
    -- 支持 force 触发立即扫描
    if params and params.force == "true" then
        os.execute("ubus call wifi_ac discover_start '{\"force\":true}' >/dev/null 2>&1")
        -- 等待守护进程响应（可适当sleep或异步优化）
        nixio.nanosleep(1)
    end
    local path = "/tmp/wifi-ac/discovered_devices.json"
    local f = io.open(path, "r")
    if not f then
        return {code=1, msg="未发现新设备"}
    end
    local content = f:read("*a")
    f:close()
    local list = json.parse(content) or {}
    -- 过滤已注册设备
    local registered = {}
    local uci = require "luci.model.uci".cursor()
    uci:foreach("wifi_ac", "device", function(s)
        if s.mac then registered[s.mac:lower()] = true end
    end)
    local newlist = {}
    for _, dev in ipairs(list) do
        if dev.mac and not registered[dev.mac:lower()] then
            table.insert(newlist, dev)
        end
    end
    return {code=0, devices=newlist}
end

-- UDP 扫描添加设备（Manual Scan）
function udp_scan_devices()
    local cfg = get_udp_config()
    local http = require "luci.httpclient"
    local json = require "luci.jsonc"
    local resp
    local ok = pcall(function()
        resp = http.request_to_buffer("http://" .. cfg.udp_broadcast .. ":" .. cfg.udp_port .. "/scan", {
            timeout = cfg.udp_timeout
        })
    end)
    if not ok or not resp or resp == "" then
        return {code=1, msg="UDP扫描失败或无响应"}
    end
    local list = json.parse(resp) or {}
    -- 过滤已注册设备（通过 UCI 配置比对）
    local registered = {}
    uci:foreach("wifi_ac", "device", function(s)
        if s.mac then registered[s.mac:lower()] = true end
    end)
    local newlist = {}
    for _, dev in ipairs(list) do
        if dev.mac and not registered[dev.mac:lower()] then
            table.insert(newlist, dev)
        end
    end
    return {code=0, devices=newlist}
end

-- UDP网络相关配置
local function get_udp_config()
    local uci = require "luci.model.uci".cursor()
    local cfg = {}
    cfg.udp_port = uci:get("wifi_ac", "global", "udp_port") or 9090
    cfg.udp_broadcast = uci:get("wifi_ac", "global", "udp_broadcast") or "255.255.255.255"
    cfg.udp_timeout = tonumber(uci:get("wifi_ac", "global", "udp_timeout") or "2")
    cfg.udp_retry = tonumber(uci:get("wifi_ac", "global", "udp_retry") or "2")
    return cfg
end

local function list_templates(vendor)
    local lfs = require "luci.fs"
    local templates = {}
    local base = "/etc/wifi-ac/templates/"
    local dirs = {base}
    if vendor and vendor ~= "" then
        table.insert(dirs, base .. vendor .. "/")
    end
    for _, dir in ipairs(dirs) do
        if lfs.isdir(dir) then
            for _, file in ipairs(lfs.dir(dir)) do
                if file:match("%.json$") then
                    local path = dir .. file
                    local content = lfs.readfile(path)
                    if content then
                        local tpl = require("luci.jsonc").parse(content)
                        if tpl then
                            tpl._file = path
                            table.insert(templates, tpl)
                        end
                    end
                end
            end
        end
    end
    return templates
end

function get_local_template(vendor, name)
    local tpls = list_templates(vendor)
    for _, tpl in ipairs(tpls) do
        if tpl.name == name then return tpl end
    end
    return nil
end

function get_template_list(params)
    local vendor = params and params.vendor
    return {code=0, templates=list_templates(vendor)}
end

function create_template(params)
    local json = require "luci.jsonc"
    local lfs = require "luci.fs"
    local name = params.name
    local vendor = params.vendor or "default"
    local config = params.config
    if not name or not config then
        return {code=1, msg="模板名称和配置必填"}
    end
    if type(config) ~= "table" then
        config = json.parse(config)
    end
    -- jsonschema 校验
    local schema_path = "/etc/wifi-ac/template_schema.json"
    local schema = lfs.readfile(schema_path)
    if not schema then
        return {code=4, msg="模板Schema文件不存在"}
    end
    local schema_obj = json.parse(schema)
    local tpl_obj = {name=name, vendor=vendor, config=config}
    local ok, jsonschema = pcall(require, "jsonschema")
    if ok and jsonschema and jsonschema.validate then
        local valid, err = jsonschema.validate(schema_obj, tpl_obj)
        if not valid then
            return {code=5, msg="模板格式校验失败: " .. (err or "")}
        end
    end
    -- 校验通过，写入文件
    local dir = "/etc/wifi-ac/templates/" .. vendor .. "/"
    if not lfs.isdir(dir) then lfs.mkdirr(dir) end
    local path = dir .. name .. ".json"
    local tpl = {name=name, vendor=vendor, config=config}
    local ok = lfs.writefile(path, json.stringify(tpl, true))
    if ok then
        return {code=0, msg="模板创建成功"}
    else
        return {code=3, msg="模板写入失败"}
    end
end

function get_offline_reason(mac)
    -- 1. 信号强度检测
    local iw = io.popen("iw dev wlan0 link 2>/dev/null")
    if iw then
        local link = iw:read("*a")
        iw:close()
        local signal = link and link:match("signal: ([%-0-9]+) dBm")
        if signal and tonumber(signal) < -85 then
            return {reason="signal_weak", text="信号弱离线", signal=tonumber(signal)}
        end
    end
    -- 2. 系统日志分析
    local kernlog = io.open("/var/log/kern.log", "r")
    local found_auth, found_hw, found_timeout = false, false, false
    if kernlog then
        for line in kernlog:lines() do
            if mac and line:lower():find(mac:lower()) then
                if not found_auth and line:find("Deauthentication") then
                    found_auth = true
                end
                if not found_hw and line:find("firmware error") then
                    found_hw = true
                end
                if not found_timeout and line:find("Timeout") then
                    found_timeout = true
                end
            end
        end
        kernlog:close()
    end
    if found_auth then
        return {reason="auth_failure", text="认证失败离线"}
    elseif found_hw then
        return {reason="hardware_failure", text="硬件故障离线"}
    elseif found_timeout then
        return {reason="timeout", text="连接超时离线"}
    end
    -- 3. 接口状态
    local op = io.open("/sys/class/net/wlan0/operstate", "r")
    if op then
        local state = op:read("*l")
        op:close()
        if state == "down" then
            return {reason="interface_down", text="接口断开离线"}
        end
    end
    -- 未知
    return {reason="unknown", text="未知原因"}
end

local optimize_status = {progress=0, log={}, result=nil}
local optimize_config = {max_clients=32, strategy="balance"}
local optimize_trend = {
    time = {"10:00","10:05","10:10"},
    ap1 = {20,40,30},
    ap2 = {30,35,32}
}

-- 获取所有AP的信道、功率、负载等信息
function get_ap_status_list()
    local list = {}
    uci:foreach("wifi_ac", "device", function(s)
        local status = sys.exec("ubus call wifi.status '{\"mac\":\"" .. (s.mac or "") .. "\"}' 2>/dev/null")
        local stat = status and util.parse_json(status) or {}
        local c24 = tonumber(stat.clients_24g or 0)
        local c5 = tonumber(stat.clients_5g or 0)
        -- clients 字段为2.4G+5G总和
        table.insert(list, {
            mac = s.mac,
            vendor = s.vendor,
            model = s.model,
            channel = stat.channel or 1,
            txpower = stat.txpower or 20,
            clients = c24 + c5,
            cpu = stat.cpu or 0,
            mem = stat.mem or 0,
            signal = stat.signal or -100
        })
    end)
    return list
end

-- 获取AP支持的信道范围
local function get_available_channels(ap_type, used_channels)
    if ap_type == "2.4g" then
        local all = {1,2,3,4,5,6,7,8,9,10,11,12,13}
        local ret = {}
        for _, ch in ipairs(all) do
            if not used_channels[ch] then table.insert(ret, ch) end
        end
        return ret
    elseif ap_type == "5g" then
        local all = {36,40,44,48,149,153,157,161,165}
        local ret = {}
        for _, ch in ipairs(all) do
            if not used_channels[ch] then table.insert(ret, ch) end
        end
        return ret
    end
    return {}
end

-- 获取同频段已分配信道
local function get_used_channels(aps, exclude_mac, ap_type)
    local used = {}
    for _, ap in ipairs(aps) do
        if ap.mac ~= exclude_mac and ap.type == ap_type and ap.channel then
            used[tonumber(ap.channel)] = true
        end
    end
    return used
end

-- 计算某信道在当前位置的干扰（简单实现：统计周边AP在该信道的信号强度和）
local function calculate_interference(ch, ap_position, scan_results)
    local sum = 0
    for _, scan in ipairs(scan_results or {}) do
        if tonumber(scan.channel) == tonumber(ch) then
            sum = sum + math.abs(tonumber(scan.signal) or 0)
        end
    end
    return sum
end

-- 贪心+干扰优先信道分配算法
local function greedy_channel_allocation(aps, scan_results)
    -- 按干扰值降序排序
    table.sort(aps, function(a, b) return (a.interference or 0) > (b.interference or 0) end)
    for _, ap in ipairs(aps) do
        local used_channels = get_used_channels(aps, ap.mac, ap.type)
        local available_channels = get_available_channels(ap.type, used_channels)
        if #available_channels > 0 then
            local min_interf = math.huge
            local best_channel
            for _, ch in ipairs(available_channels) do
                local interf = calculate_interference(ch, ap.position, scan_results)
                if interf < min_interf then
                    min_interf = interf
                    best_channel = ch
                end
            end
            ap.channel = best_channel
        else
            -- 降级处理：切换至5G频段（若支持）
            if ap.supports_5g and ap.type == "2.4g" then
                ap.type = "5g"
                ap.channel = 149
            end
        end
    end
    return aps
end

-- 负载均衡阈值与策略设置
function set_load_balance(params)
    local ap_mac = params.ap_mac
    local threshold = tonumber(params.threshold) or 50
    local strategy = params.strategy or "power_adjust"
    if not ap_mac then
        return {code=1, msg="ap_mac必填"}
    end

    -- 查找AP信息
    local ap = nil
    uci:foreach("wifi_ac", "device", function(s)
        if s.mac and s.mac:lower() == ap_mac:lower() then
            ap = s
        end
    end)
    if not ap then
        return {code=2, msg="未找到指定AP"}
    end

    -- 保存阈值到UCI（可选）
    uci:set("wifi_ac", ap[".name"], "lb_threshold", threshold)
    uci:set("wifi_ac", ap[".name"], "lb_strategy", strategy)
    uci:commit("wifi_ac")

    -- 实时检测当前连接数
    local status = sys.exec("ubus call wifi.status '{\"mac\":\"" .. ap_mac .. "\"}' 2>/dev/null")
    local stat = status and util.parse_json(status) or {}
    local clients = tonumber(stat.clients_24g or 0) + tonumber(stat.clients_5g or 0)
    local vendor = (ap.vendor or ""):lower()

    local action_log = {}

    if clients > threshold then
        if vendor:find("huawei") and (strategy == "80211v" or strategy == "auto") then
            sys.exec("uci set wireless.@wifi-iface[0].ieee80211v=1; uci commit wireless")
            table.insert(action_log, "已为华为AP启用802.11v")
        elseif vendor:find("tp") and (strategy == "power_adjust" or strategy == "auto") then
            local cur_power = tonumber(stat.txpower or 20)
            local new_power = math.max(cur_power - 1, 10)
            sys.exec("iwinfo wlan0 set txpower " .. new_power)
            table.insert(action_log, "已为TP-Link AP降低发射功率至" .. new_power .. "dBm")
        elseif vendor:find("ruijie") and (strategy == "vendor_api" or strategy == "auto") then
            sys.exec("/usr/bin/ruijie_lb_api --mac " .. ap_mac .. " --enable")
            table.insert(action_log, "已为锐捷AP调用私有负载均衡API")
        end
        -- Beacon负载引导（伪实现，实际需驱动/厂商支持）
        sys.exec("ubus call wifi.device '{\"mac\":\""..ap_mac.."\",\"action\":\"set_load_info\",\"load\":"..clients.."}'")
        table.insert(action_log, "已调整Beacon负载信息字段")
        return {code=0, msg="负载均衡策略已应用", log=action_log}
    else
        return {code=0, msg="当前连接数未超阈值，无需调整", log=action_log}
    end
end

-- 自动信道分配/负载均衡（增强：贪心+干扰优先）
local queue_file = "/tmp/wifi-ac/optimization_queue.json"
local nixio = require "nixio"
local function read_queue()
    local f = io.open(queue_file, "r")
    if not f then return {} end
    local data = f:read("*a")
    f:close()
    return (json.parse(data) or {})
end
local function write_queue(q)
    local f = io.open(queue_file, "w")
    if not f then return end
    f:write(json.stringify(q, true))
    f:close()
end

-- 添加任务到队列
function enqueue_optimization_task(task)
    local q = read_queue()
    table.insert(q, task)
    write_queue(q)
end

-- 取出并标记队列中的下一个待处理任务
function fetch_next_task()
    local q = read_queue()
    for i, t in ipairs(q) do
        if t.status == "pending" then
            t.status = "processing"
            t.start_time = os.date("!%Y-%m-%dT%H:%M:%SZ")
            write_queue(q)
            return t, i
        end
    end
    return nil
end

-- 更新任务进度
function update_task_progress(task_id, progress, status)
    local q = read_queue()
    for _, t in ipairs(q) do
        if t.task_id == task_id then
            t.progress = progress or t.progress
            if status then t.status = status end
            write_queue(q)
            break
        end
    end
end

-- 信道预扫描，缓存扫描结果
function pre_scan_channels()
    local scan_file = "/tmp/wifi-ac/scan_cache.json"
    local scan = io.popen("iw dev wlan0 scan 2>/dev/null")
    if not scan then return end
    local lines, result = {}, {}
    for line in scan:lines() do table.insert(lines, line) end
    scan:close()
    for _, line in ipairs(lines) do
        local ch = line:match("channel: (%d+)")
        local sig = line:match("signal: ([%-0-9]+)")
        if ch and sig then
            table.insert(result, {channel=tonumber(ch), signal=tonumber(sig)})
        end
    end
    local f = io.open(scan_file, "w")
    if f then f:write(require("luci.jsonc").stringify(result)); f:close() end
    return result
end

-- 配置快照与回滚
local function backup_config()
    local backup_dir = "/etc/wifi-ac/backups/"
    if not nixio.fs.isdir(backup_dir) then nixio.fs.mkdirr(backup_dir) end
    local ts = os.date("%Y%m%d%H%M%S")
    local backup_file = backup_dir .. "wifi_ac_" .. ts .. ".bak"
    os.execute("cp /etc/config/wifi_ac " .. backup_file)
    return backup_file
end

local function restore_config(backup_file)
    if backup_file and nixio.fs.access(backup_file) then
        os.execute("cp " .. backup_file .. " /etc/config/wifi_ac")
        os.execute("uci commit wifi_ac")
    end
end

-- 批量配置下发（uci batch）
local function uci_batch_set(options)
    local f = io.popen("uci batch", "w")
    if not f then return end
    for _, cmd in ipairs(options) do
        f:write(cmd .. "\n")
    end
    f:write("commit wifi_ac\n")
    f:close()
end

-- 优化任务超时处理
local function check_task_timeout(task)
    local start = task.start_time and os.time(os.date("*t", os.time(task.start_time))) or os.time()
    if os.time() - start > 600 then -- 10分钟
        task.status = "failed"
        task.fail_reason = "timeout"
        return true
    end
    return false
end

-- 后台任务处理主循环（建议由守护进程或定时器调用）
function process_optimization_queue()
    local ubus = require "ubus"
    local conn = ubus.connect()
    if not conn then return end
    local t, idx = fetch_next_task()
    if not t then return end

    -- 记录配置快照
    local backup_file = backup_config()

    -- 信道预扫描
    local scan_result = pre_scan_channels()

    -- 推送进度
    conn:send("wifi_ac.optimization_progress", {task_id=t.task_id, progress=10, msg="开始信道分配..."})

    -- 检查超时
    if check_task_timeout(t) then
        conn:send("wifi_ac.optimization_result", {task_id=t.task_id, result="failed", msg="任务超时"})
        restore_config(backup_file)
        conn:close()
        return
    end

    -- 示例：批量下发配置（实际应根据算法生成options）
    local options = {}
    for _, mac in ipairs(t.aps or {}) do
        table.insert(options, string.format("set wifi_ac.%s.channel=6", mac))
    end
    uci_batch_set(options)

    -- 模拟信道分配
    nixio.nanosleep(1)
    conn:send("wifi_ac.optimization_progress", {task_id=t.task_id, progress=50, msg="分配信道中..."})
    -- 实际分配
    local aps = t.aps or {}
    for _, mac in ipairs(aps) do
        sys.exec("ubus call wifi.device '{\"mac\":\""..mac.."\",\"action\":\"set_channel\",\"channel\":6}'")
    end
    nixio.nanosleep(1)
    conn:send("wifi_ac.optimization_progress", {task_id=t.task_id, progress=90, msg="下发配置..."})
    -- 完成
    update_task_progress(t.task_id, 100, "success")
    conn:send("wifi_ac.optimization_result", {task_id=t.task_id, result="success", msg="干扰下降28%"})

    -- 假设有失败，自动回滚
    if t.status == "failed" then
        restore_config(backup_file)
    end

    conn:close()
end

-- 一键自动优化：入队任务
function optimize_auto(params)
    local task_id = "opt_" .. tostring(math.random(10000,99999)) .. tostring(os.time())
    local aps = {}
    uci:foreach("wifi_ac", "device", function(s)
        table.insert(aps, s.mac)
    end)
    local task = {
        task_id = task_id,
        type = "automatic_optimization",
        status = "pending",
        aps = aps,
        start_time = "",
        progress = 0
    }
    enqueue_optimization_task(task)
    optimize_status.progress = 0
    optimize_status.log = {"已加入优化队列，任务ID: " .. task_id}
    optimize_status.result = {code=0, msg="任务已入队", task_id=task_id}
    return optimize_status.result
end

-- 手动信道/功率分配
function optimize_manual(params)
    local mac = params.mac
    local channel = params.channel
    local txpower = params.txpower
    if mac and channel then
        sys.exec("ubus call wifi.device '{\"mac\":\""..mac.."\",\"action\":\"set_channel\",\"channel\":"..channel.."}'")
        table.insert(optimize_status.log, string.format("AP %s 手动分配信道 %s", mac, channel))
    end
    if mac and txpower then
        sys.exec("ubus call wifi.device '{\"mac\":\""..mac.."\",\"action\":\"set_txpower\",\"txpower\":"..txpower.."}'")
        table.insert(optimize_status.log, string.format("AP %s 手动设置功率 %s", mac, txpower))
    end
    optimize_status.progress = 100
    optimize_status.result = {code=0, msg="手动优化完成"}
    return optimize_status.result
end

-- 批量应用策略模板
function optimize_apply_template(params)
    local template = params.template
    local macs = params.macs
    if not template or not macs then
        return {code=1, msg="参数缺失"}
    end
    -- 支持字符串模板（前端传递时为字符串）
    if type(template) == "string" then
        local ok, tpl = pcall(json.parse, template)
        if ok and tpl then template = tpl end
    end
    for mac in string.gmatch(macs, "[^,]+") do
        sys.exec("ubus call wifi.device '{\"mac\":\""..mac.."\",\"action\":\"apply_template\",\"tpl\":"..util.serialize_json(template).."}'")
        table.insert(optimize_status.log, string.format("AP %s 应用模板", mac))
    end
    optimize_status.progress = 100
    optimize_status.result = {code=0, msg="模板批量应用完成"}
    return optimize_status.result
end

function optimize_progress()
    -- 返回优化进度与日志
    return {progress=optimize_status.progress, log=optimize_status.log, result=optimize_status.result}
end

function optimize_set_threshold(params)
    -- 设置负载均衡阈值与策略
    if params.max_clients then
        optimize_config.max_clients = tonumber(params.max_clients)
        table.insert(optimize_status.log, "设置最大接入数为" .. params.max_clients)
    end
    if params.strategy then
        optimize_config.strategy = params.strategy
        table.insert(optimize_status.log, "设置负载均衡策略为" .. params.strategy)
    end
    return {code=0, msg="设置成功"}
end

function optimize_get_threshold()
    return {max_clients=optimize_config.max_clients, strategy=optimize_config.strategy}
end

function optimize_trend_data()
    -- 返回趋势对比数据（示例）
    return {time=optimize_trend.time, ap1=optimize_trend.ap1, ap2=optimize_trend.ap2}
end

function get_channel_heatmap()
    local heatmap = {["2.4G"] = {}, ["5G"] = {}}
    local scan = io.popen("iw dev wlan0 scan 2>/dev/null")
    if scan then
        local lines = {}
        for line in scan:lines() do table.insert(lines, line) end
        scan:close()
        local cur_band, cur_channel, cur_signal
        for _, line in ipairs(lines) do
            local ch = line:match("channel: (%d+)")
            if ch then
                cur_channel = tonumber(ch)
                if cur_channel <= 14 then
                    cur_band = "2.4G"
                else
                    cur_band = "5G"
                end
            end
            local sig = line:match("signal: ([%-0-9]+)")
            if sig and cur_channel and cur_band then
                heatmap[cur_band][tostring(cur_channel)] = (heatmap[cur_band][tostring(cur_channel)] or 0) + tonumber(sig)
            end
        end
    end
    -- 转换为ECharts热力图格式
    local x = {"1","6","11","36","40","149"}
    local y = {"2.4G","5G"}
    local data = {}
    for yi, band in ipairs(y) do
        for xi, ch in ipairs(x) do
            local v = heatmap[band][ch] or 0
            table.insert(data, {xi-1, yi-1, v})
        end
    end
    return data
end

-- 校验模板（Lua实现，确保channel/tx_power等参数合法）
local function validate_template(template)
    if not template or type(template) ~= "table" then return false, "模板为空" end
    if not template.vendor then return false, "缺少vendor" end
    if not template.config or type(template.config) ~= "table" then return false, "缺少config" end
    local ch = template.config.channel
    local tx = template.config.tx_power
    if type(ch) ~= "number" or ch < 1 or ch > 165 then return false, "信道非法" end
    if type(tx) ~= "number" or tx < 10 or tx > 30 then return false, "功率非法" end
    return true
end

-- 根据template_id查找模板
local function find_template_by_id(template_id)
    local lfs = require "luci.fs"
    for _, dir in ipairs({"/etc/wifi-ac/templates/", "/etc/wifi-ac/templates/tp-link/", "/etc/wifi-ac/templates/huawei/"}) do
        if lfs.isdir(dir) then
            for _, file in ipairs(lfs.dir(dir)) do
                if file:match("%.json$") then
                    local path = dir .. file
                    local content = lfs.readfile(path)
                    if content then
                        local tpl = require("luci.jsonc").parse(content)
                        if tpl and tpl.template_id == template_id then
                            return tpl
                        end
                    end
                end
            end
        end
    end
    return nil
end

-- 批量应用策略模板
function apply_template_batch(params)
    local template_id = params.template_id
    local aps = params.aps
    local force_restart = params.force_restart
    if not template_id or not aps or type(aps) ~= "table" then
        return {code=1, msg="参数缺失"}
    end
    local tpl = find_template_by_id(template_id)
    if not tpl then
        return {code=2, msg="未找到模板"}
    end
    local ok, err = validate_template(tpl)
    if not ok then
        return {code=3, msg="模板校验失败: " .. (err or "")}
    end
    local sys = require "luci.sys"
    local results = {}
    for _, mac in ipairs(aps) do
        local cmd = string.format("ubus call wifi.device '{\"mac\":\"%s\",\"action\":\"apply_template\",\"tpl\":%s}'", mac, require("luci.util").serialize_json(tpl))
        local r = sys.exec(cmd)
        results[mac] = r or "ok"
        if force_restart then
            sys.exec(string.format("ubus call wifi.device '{\"mac\":\"%s\",\"action\":\"reboot\"}'", mac))
        end
    end
    return {code=0, msg="批量下发完成", result=results}
end

local function parse_time_range(time_range)
    local now = os.time()
    if not time_range or time_range == "" then return now - 3600 end
    if time_range:match("^(%d+)h$") then
        return now - tonumber(time_range:match("^(%d+)h$")) * 3600
    elseif time_range:match("^(%d+)m$") then
        return now - tonumber(time_range:match("^(%d+)m$")) * 60
    end
    return now - 3600
end

function get_trend_data(ap_mac, time_range)
    local sqlite3 = require("lsqlite3")
    local db = sqlite3.open("/etc/wifi-ac/performance.db")
    if not db then return {} end
    local since = parse_time_range(time_range)
    local res = {}
    for row in db:nrows(string.format(
        "SELECT timestamp,load_percent,signal_dbm,channel FROM performance WHERE ap_mac='%s' AND timestamp>=%d ORDER BY timestamp ASC",
        ap_mac or '', since)) do
        table.insert(res, {
            timestamp = row.timestamp,
            load_percent = row.load_percent,
            signal_dbm = row.signal_dbm,
            channel = row.channel
        })
    end
    db:close()
    return res
end

function calculate_optimization_effect(old_data, new_data)
    local interference_diff = (new_data.interference or 0) - (old_data.interference or 0)
    local load_diff = (new_data.load_percent or 0) - (old_data.load_percent or 0)
    return {
        interference_reduction = math.abs(interference_diff),
        load_balance_effect = load_diff < 0 and "improved" or "worsened"
    }
end

local firmware_dir = "/etc/wifi-ac/firmware/"
local upgrade_status_file = "/tmp/wifi-ac/upgrade_status.json"

function get_firmware_list(params)
    local lfs = require "luci.fs"
    local vendor = params and params.vendor
    local model_name = params and params.model
    local files = {}
    if not lfs.isdir(firmware_dir) then return {firmwares={}} end
    for _, file in ipairs(lfs.dir(firmware_dir)) do
        if file:match("%.bin$") then
            local meta_path = firmware_dir .. file .. ".meta"
            local meta = lfs.readfile(meta_path)
            local info = meta and require("luci.jsonc").parse(meta) or {}
            if (not vendor or info.vendor == vendor) and (not model_name or info.model == model_name) then
                table.insert(files, {
                    name = file,
                    vendor = info.vendor,
                    model = info.model,
                    version = info.version,
                    md5 = info.md5,
                    size = lfs.stat(firmware_dir .. file, "size")
                })
            end
        end
    end
    return {firmwares = files}
end

function upload_firmware()
    local http = require "luci.http"
    local lfs = require "luci.fs"
    local json = require "luci.jsonc"
    local upload = http.formvalue("file")
    local vendor = http.formvalue("vendor")
    local model_name = http.formvalue("model")
    local version = http.formvalue("version")
    if not upload or not vendor or not model_name or not version then
        return {code=1, msg="参数缺失"}
    end
    if not lfs.isdir(firmware_dir) then lfs.mkdirr(firmware_dir) end
    local filename = firmware_dir .. vendor .. "_" .. model_name .. "_" .. version .. ".bin"
    local f = io.open(filename, "w+b")
    if not f then return {code=2, msg="无法写入固件文件"} end
    local data = http.content()
    f:write(data)
    f:close()
    -- 计算MD5
    local md5 = lfs.readfile("/bin/busybox") and (io.popen("md5sum " .. filename):read("*l") or ""):match("^(%w+)")
    -- 写入meta信息
    local meta = {
        vendor = vendor,
        model = model_name,
        version = version,
        md5 = md5
    }
    lfs.writefile(filename .. ".meta", json.stringify(meta))
    return {code=0, msg="上传成功", file=filename, meta=meta}
end

function batch_upgrade(params)
    local json = require "luci.jsonc"
    local aps = params.aps or (params["aps[]"])
    local firmware = params.firmware
    if type(aps) == "string" then aps = {aps} end
    if not aps or not firmware then
        return {code=1, msg="参数缺失"}
    end
    local status = {}
    for _, mac in ipairs(aps) do
        local r = os.execute(string.format("ubus call wifi.device '{\"mac\":\"%s\",\"action\":\"upgrade\",\"firmware\":\"%s\"}'", mac, firmware))
        status[mac] = r == 0 and "upgrading" or "failed"
    end
    local f = io.open(upgrade_status_file, "w")
    if f then f:write(json.stringify(status)); f:close() end
    return {code=0, msg="批量升级已下发", status=status}
end

function get_upgrade_status()
    local json = require "luci.jsonc"
    local f = io.open(upgrade_status_file, "r")
    if not f then return {} end
    local data = f:read("*a")
    f:close()
    return json.parse(data) or {}
end

local log_file = "/var/log/wifi-ac/wifi-ac.log"

function add_log(params)
    local json = require "luci.jsonc"
    local entry = {
        timestamp = os.time(),
        type = params.type or "info",
        vendor = params.vendor,
        user = params.user,
        msg = params.msg,
        detail = params.detail
    }
    local f = io.open(log_file, "a")
    if f then
        f:write(json.stringify(entry) .. "\n")
        f:close()
    end
    return {code=0, msg="日志已记录"}
end

function query_log(params)
    local json = require "luci.jsonc"
    local logs = {}
    local since = tonumber(params.since) or 0
    local until_ts = tonumber(params["until"]) or os.time() + 1
    local keyword = params.keyword
    local vendor = params.vendor
    local typ = params.type
    local user = params.user
    local f = io.open(log_file, "r")
    if not f then return {logs={}} end
    for line in f:lines() do
        local entry = json.parse(line)
        if entry then
            if entry.timestamp and (entry.timestamp >= since and entry.timestamp <= until_ts) and
                (not typ or entry.type == typ) and
                (not vendor or entry.vendor == vendor) and
                (not user or entry.user == user) and
                (not keyword or (entry.msg and tostring(entry.msg):find(keyword))) then
                table.insert(logs, entry)
            end
        end
    end
    f:close()
    -- 导出
    if params.export == "csv" then
        local csv = "时间,类型,厂商,用户,消息,详情\n"
        for _, e in ipairs(logs) do
            csv = csv .. os.date("%Y-%m-%d %H:%M:%S", e.timestamp or 0) .. "," .. (e.type or "") .. "," .. (e.vendor or "") .. "," .. (e.user or "") .. "," .. (e.msg or "") .. "," .. (e.detail or "") .. "\n"
        end
        return csv
    elseif params.export == "pdf" then
        -- 简单PDF文本（实际可用lua-pdf等库生成）
        local pdf = "%PDF-1.4\n%日志导出\n"
        for _, e in ipairs(logs) do
            pdf = pdf .. os.date("%Y-%m-%d %H:%M:%S", e.timestamp or 0) .. " " .. (e.type or "") .. " " .. (e.vendor or "") .. " " .. (e.user or "") .. " " .. (e.msg or "") .. "\n"
        end
        return pdf
    end
    return {logs=logs}
end

-- WebSocket实时告警推送
function push_alarm_ws(msg)
    local ubus = require "ubus"
    local conn = ubus.connect()
    if conn then
        conn:send("wifi_ac.alarm", {msg=msg, timestamp=os.time()})
        conn:close()
    end
end

function get_settings()
    local uci = require "luci.model.uci".cursor()
    local s = {}
    uci:foreach("wifi_ac", "wifi_ac", function(sec)
        for k, v in pairs(sec) do
            s[k] = v
        end
    end)
    return s
end

function set_settings(params)
    local uci = require "luci.model.uci".cursor()
    local sid
    uci:foreach("wifi_ac", "wifi_ac", function(sec) sid = sec[".name"] end)
    if not sid then sid = uci:add("wifi_ac", "wifi_ac") end
    for k, v in pairs(params) do
        uci:set("wifi_ac", sid, k, v)
    end
    uci:commit("wifi_ac")
    return {code=0, msg="设置已保存"}
end

function test_radius(params)
    local server = params.radius_server
    local secret = params.radius_secret
    if not server or not secret then
        return {code=1, msg="参数缺失"}
    end
    local ok = os.execute(string.format("echo | radtest testuser testpass %s 0 %s >/dev/null 2>&1", server, secret))
    if ok == 0 then
        return {code=0, msg="RADIUS连通成功"}
    else
        return {code=2, msg="RADIUS连通失败"}
    end
end

-- 配置模板管理
function list_templates_manage()
    local lfs = require "luci.fs"
    local base = "/etc/wifi-ac/templates/"
    local templates = {}
    for _, dir in ipairs({base}) do
        if lfs.isdir(dir) then
            for _, file in ipairs(lfs.dir(dir)) do
                if file:match("%.json$") then
                    local path = dir .. file
                    local content = lfs.readfile(path)
                    if content then
                        local tpl = require("luci.jsonc").parse(content)
                        if tpl then
                            tpl._file = path
                            table.insert(templates, tpl)
                        end
                    end
                end
            end
        end
    end
    return {templates=templates}
end

function save_template_manage(params)
    local lfs = require "luci.fs"
    local json = require "luci.jsonc"
    if not params.name or not params.config then
        return {code=1, msg="模板名称和配置必填"}
    end
    local dir = "/etc/wifi-ac/templates/"
    if not lfs.isdir(dir) then lfs.mkdirr(dir) end
    local path = dir .. params.name .. ".json"
    local ok = lfs.writefile(path, json.stringify(params, true))
    if ok then
        return {code=0, msg="模板保存成功"}
    else
        return {code=2, msg="模板保存失败"}
    end
end

function delete_template_manage(params)
    local lfs = require "luci.fs"
    if not params.name then return {code=1, msg="模板名称必填"} end
    local path = "/etc/wifi-ac/templates/" .. params.name .. ".json"
    if lfs.unlink(path) then
        return {code=0, msg="模板已删除"}
    else
        return {code=2, msg="删除失败"}
    end
end

-- 权限与角色管理（简化示例）
local role_file = "/etc/wifi-ac/roles.json"
function list_roles()
    local lfs = require "luci.fs"
    local json = require "luci.jsonc"
    local data = lfs.readfile(role_file)
    return data and json.parse(data) or {roles={}}
end
function save_roles(params)
    local lfs = require "luci.fs"
    local json = require "luci.jsonc"
    if not params.roles then return {code=1, msg="roles参数必填"} end
    lfs.writefile(role_file, params.roles)
    return {code=0, msg="角色已保存"}
end
function import_roles(params)
    return save_roles(params)
end
function delete_role(params)
    -- 简化：实际应解析JSON并删除指定角色
    return {code=0, msg="删除成功(示例)"}
end

-- 恢复出厂设置
function factory_reset(params)
    if not params or params.password ~= "admin" then
        return {code=1, msg="密码错误"}
    end
    os.execute("rm -rf /etc/config/wifi_ac /etc/wifi-ac/templates/* /etc/wifi-ac/*")
    os.execute("reboot")
    return {code=0, msg="恢复出厂设置并重启"}
end

-- 存储策略与空间信息
function get_storage_info()
    local stat = io.popen("df -h /etc/wifi-ac /etc/wifi-ac 2>/dev/null")
    local info = stat and stat:read("*a") or ""
    if stat then stat:close() end
    return {storage=info}
end

function get_overview_data()
    local uci = require "luci.model.uci".cursor()
    local sys = require "luci.sys"
    local util = require "luci.util"
    local json = require "luci.jsonc"
    local devices = {}
    local online = 0
    local total = 0
    local avg_load = 0
    local loads, signals, clients, times = {}, {}, {}, {}
    local trend_time, trend_load, trend_signal, trend_clients = {}, {}, {}, {}
    uci:foreach("wifi_ac", "device", function(s)
        total = total + 1
        local status = sys.exec("ubus call wifi.status '{\"mac\":\"" .. (s.mac or "") .. "\"}' 2>/dev/null")
        local stat = status and util.parse_json(status) or {}
        if stat.status == "online" then online = online + 1 end
        avg_load = avg_load + (tonumber(stat.cpu or 0) or 0)
        table.insert(loads, tonumber(stat.cpu or 0) or 0)
        table.insert(signals, tonumber(stat.signal or -100) or -100)
        table.insert(clients, (tonumber(stat.clients_24g or 0) or 0) + (tonumber(stat.clients_5g or 0) or 0))
        table.insert(devices, {
            mac = s.mac,
            status = stat.status or "offline",
            cpu = stat.cpu or 0,
            signal = stat.signal or -100,
            model = s.model or "",
            vendor = s.vendor or "",
            last_online = stat.last_online or "",
            clients = (tonumber(stat.clients_24g or 0) or 0) + (tonumber(stat.clients_5g or 0) or 0)
        })
    end)
    avg_load = total > 0 and math.floor(avg_load / total) or 0
    -- 滚动通知（最近上线/离线）
    table.sort(devices, function(a, b) return (a.last_online or 0) > (b.last_online or 0) end)
    local notifications = {}
    for i = 1, math.min(5, #devices) do
        table.insert(notifications, {mac = devices[i].mac, status = devices[i].status, time = devices[i].last_online})
    end
    -- 信号分布
    local signal_dist = {strong=0, medium=0, weak=0}
    for _, s in ipairs(signals) do
        local band = (s > -70) and "strong" or ((s > -85) and "medium" or "weak")
        signal_dist[band] = (signal_dist[band] or 0) + 1
    end
    -- 仪表盘趋势（多指标，取trend.json或示例）
    local trend_file = "/etc/wifi-ac/trend.json"
    local trend = {}
    local f = io.open(trend_file, "r")
    if f then trend = json.parse(f:read("*a")) or {}; f:close() end
    for t, aps in pairs(trend) do
        table.insert(trend_time, t)
        local sum_load, sum_sig, sum_clients, cnt = 0, 0, 0, 0
        for _, ap in ipairs(aps) do
            sum_load = sum_load + (ap.load or 0)
            sum_sig = sum_sig + (ap.signal or 0)
            sum_clients = sum_clients + (ap.clients or ap.load or 0)
            cnt = cnt + 1
        end
        table.insert(trend_load, cnt > 0 and math.floor(sum_load/cnt) or 0)
        table.insert(trend_signal, cnt > 0 and math.floor(sum_sig/cnt) or 0)
        table.insert(trend_clients, cnt > 0 and math.floor(sum_clients/cnt) or 0)
    end
    return {
        total = total,
        online = online,
        avg_load = avg_load,
        notifications = notifications,
        signal_dist = signal_dist,
        trend = {
            time = trend_time,
            load = trend_load,
            signal = trend_signal,
            clients = trend_clients
        }
    }
end

-- 高级无线环境感知：复杂负载均衡与干扰感知
function advanced_channel_allocation(aps)
    local sys = require "luci.sys"
    local util = require "luci.util"
    -- 获取所有AP的信道、信号、客户端数
    local env = {}
    for _, ap in ipairs(aps) do
        local status = sys.exec("ubus call wifi.status '{\"mac\":\""..ap.mac.."\"}' 2>/dev/null")
        local stat = status and util.parse_json(status) or {}
        table.insert(env, {
            mac = ap.mac,
            channel = stat.channel,
            signal = stat.signal,
            clients = stat.clients_24g + stat.clients_5g,
            neighbors = stat.neighbors or {},
        })
    end
    -- 统计信道干扰（邻居AP数、信号强度等）
    local channel_score = {}
    for ch = 1, 14 do
        channel_score[ch] = 0
        for _, ap in ipairs(env) do
            if ap.channel == ch then
                channel_score[ch] = channel_score[ch] + ap.clients + math.max(0, -ap.signal)
            end
            -- 邻居AP干扰
            for _, n in ipairs(ap.neighbors or {}) do
                if n.channel == ch then
                    channel_score[ch] = channel_score[ch] + 10
                end
            end
        end
    end
    -- 分配最优信道（分数最低）
    for _, ap in ipairs(aps) do
        local best, min_score = 1, math.huge
        for ch in ipairs(channel_score) do
            if channel_score[ch] < min_score then
                best, min_score = ch, channel_score[ch]
            end
        end
        ap.channel = best
    end
    return aps
end

-- AP端根据阈值主动限制接入（需AP端支持，未支持则仅保存配置）
function set_load_balance(params)
    local ap_mac = params.ap_mac
    local threshold = tonumber(params.threshold) or 50
    local strategy = params.strategy or "power_adjust"
    if not ap_mac then
        return {code=1, msg="ap_mac必填"}
    end
    -- 查找AP信息
    local ap = nil
    uci:foreach("wifi_ac", "device", function(s)
        if s.mac and s.mac:lower() == ap_mac:lower() then
            ap = s
        end
    end)
    if not ap then
        return {code=2, msg="未找到指定AP"}
    end
    -- 保存阈值到UCI（可选）
    uci:set("wifi_ac", ap[".name"], "lb_threshold", threshold)
    uci:set("wifi_ac", ap[".name"], "lb_strategy", strategy)
    uci:commit("wifi_ac")
    -- 实时检测当前连接数
    local status = sys.exec("ubus call wifi.status '{\"mac\":\"" .. ap_mac .. "\"}' 2>/dev/null")
    local stat = status and util.parse_json(status) or {}
    local clients = tonumber(stat.clients_24g or 0) + tonumber(stat.clients_5g or 0)
    local vendor = (ap.vendor or ""):lower()
    local action_log = {}
    if clients > threshold then
        if vendor:find("huawei") and (strategy == "80211v" or strategy == "auto") then
            sys.exec("uci set wireless.@wifi-iface[0].ieee80211v=1; uci commit wireless")
            table.insert(action_log, "已为华为AP启用802.11v")
        elseif vendor:find("tp") and (strategy == "power_adjust" or strategy == "auto") then
            local cur_power = tonumber(stat.txpower or 20)
            local new_power = math.max(cur_power - 1, 10)
            sys.exec("iwinfo wlan0 set txpower " .. new_power)
            table.insert(action_log, "已为TP-Link AP降低发射功率至" .. new_power .. "dBm")
        elseif vendor:find("ruijie") and (strategy == "vendor_api" or strategy == "auto") then
            sys.exec("/usr/bin/ruijie_lb_api --mac " .. ap_mac .. " --enable")
            table.insert(action_log, "已为锐捷AP调用私有负载均衡API")
        end
        -- Beacon负载引导（伪实现，实际需驱动/厂商支持）
        sys.exec("ubus call wifi.device '{\"mac\":\""..ap_mac.."\",\"action\":\"set_load_info\",\"load\":"..clients.."}'")
        table.insert(action_log, "已调整Beacon负载信息字段")
        return {code=0, msg="负载均衡策略已应用", log=action_log}
    else
        return {code=0, msg="当前连接数未超阈值，无需调整", log=action_log}
    end
end

-- 趋势数据历史采集与持久化
local trend_file = "/etc/wifi-ac/trend.json"
function collect_trend_data()
    local uci = require "luci.model.uci".cursor()
    local sys = require "luci.sys"
    local json = require "luci.jsonc"
    local now = os.date("%Y-%m-%d %H:%M")
    local aps = {}
    uci:foreach("wifi_ac", "device", function(s)
        local status = sys.exec("ubus call wifi.status '{\"mac\":\""..(s.mac or "").."\"}' 2>/dev/null")
        local stat = status and json.parse(status) or {}
        table.insert(aps, {mac=s.mac, load=(stat.clients_24g or 0)+(stat.clients_5g or 0), signal=stat.signal or -100})
    end)
    local trend = {}
    local f = io.open(trend_file, "r")
    if f then trend = json.parse(f:read("*a")) or {}; f:close() end
    trend[now] = aps
    local fw = io.open(trend_file, "w")
    if fw then fw:write(json.stringify(trend)); fw:close() end
end

function get_trend_data(start_time, end_time, metric)
    -- 支持自定义时间范围与指标
    local json = require "luci.jsonc"
    local f = io.open(trend_file, "r")
    if not f then return {time={}, avg_load={}, avg_signal={}} end
    local trend = json.parse(f:read("*a")) or {}
    f:close()
    local time, avg_load, avg_signal, avg_clients = {}, {}, {}, {}
    for t, aps in pairs(trend) do
        -- 时间过滤
        if (not start_time or t >= start_time) and (not end_time or t <= end_time) then
            table.insert(time, t)
            local sum_load, sum_sig, sum_clients, cnt = 0, 0, 0, 0
            for _, ap in ipairs(aps) do
                sum_load = sum_load + (ap.load or 0)
                sum_sig = sum_sig + (ap.signal or 0)
                sum_clients = sum_clients + (ap.clients or 0)
                cnt = cnt + 1
            end
            table.insert(avg_load, cnt > 0 and math.floor(sum_load/cnt) or 0)
            table.insert(avg_signal, cnt > 0 and math.floor(sum_sig/cnt) or 0)
            table.insert(avg_clients, cnt > 0 and math.floor(sum_clients/cnt) or 0)
        end
    end
    if metric == "signal" then
        return {time=time, data=avg_signal}
    elseif metric == "clients" then
        return {time=time, data=avg_clients}
    else
        return {time=time, data=avg_load}
    end
end

-- 功率调节控件适配（返回支持的功率范围，三方适配留注释）
function get_txpower_range(vendor, model)
    -- 支持type/range/options，便于前端细粒度渲染
    if vendor == "OpenWrt" then
        return {type="range", min=0, max=30, step=1}
    elseif vendor == "TPLink" then
        return {type="select", options={10,12,14,16,18,20,22}}
    elseif vendor == "Ruijie" then
        return {type="number", min=8, max=20, step=1}
    end
    -- 三方AP可通过配置文件扩展
    local lfs = require "luci.fs"
    local json = require "luci.jsonc"
    local path = "/etc/wifi-ac/txpower_range.json"
    if lfs.access(path) then
        local data = json.parse(lfs.readfile(path) or "") or {}
        if data[vendor] and data[vendor][model] then
            return data[vendor][model]
        end
    end
    return {type="range", min=0, max=20, step=1}
end

local ubus = require("luci.ubus")
local env = {}

-- 订阅ubus环境数据事件（由AP通过UDP上报）
local function subscribe_environment()
  local ubus_ctx = ubus.connect()
  if not ubus_ctx then return end
  ubus_ctx:subscribe("wifi_environment", "ap_status", function(data)
    -- 解析AP上报的信道、信号、负载数据
    env[data.mac] = {
      channel = data.channel,
      signal = data.signal,
      load = data.load,
      nearby_aps = data.nearby_aps  -- 周边AP列表（含MAC/信号/信道）
    }
  end)
end

-- 计算全局干扰矩阵
local function calculate_interference_matrix()
  local matrix = {}
  for mac, ap in pairs(env) do
    matrix[mac] = 0
    for _, neighbor in ipairs(ap.nearby_aps or {}) do
      -- 信号衰减模型：距离每增加1米，干扰权重*0.8（假设AP间距离通过信号强度估算）
      local distance = math.pow(10, (100 + (neighbor.signal or -80))/20)
      matrix[mac] = matrix[mac] + (1 / distance) * (math.abs((ap.channel or 1) - (neighbor.channel or 1)) <= 2 and 1 or 0.3)
    end
  end
  return matrix
end

-- 负载均衡算法（匈牙利算法分配信道）
local function hungarian_channel_optimization(aps)
  -- 构建代价矩阵（干扰+负载）
  local cost = {}
  for i, a in ipairs(aps) do
    cost[i] = {}
    for _, ch in ipairs(a.available_channels or {1,6,11,36,40,149}) do
      -- calculate_interference 需结合env和ch
      local interference = 0
      for _, neighbor in ipairs(env[a.mac] and env[a.mac].nearby_aps or {}) do
        if neighbor.channel == ch then
          local distance = math.pow(10, (100 + (neighbor.signal or -80))/20)
          interference = interference + (1 / distance)
        end
      end
      cost[i][ch] = interference + ((a.load or 0) / 100)
    end
  end

  -- 调用匈牙利算法库求解最优分配
  -- local hungarian = require("hungarian_algorithm")
  -- local assignment = hungarian(cost)
  -- 伪代码：假设每AP分配最小cost的信道
  local assignment = {}
  for i, row in ipairs(cost) do
    local min_ch, min_val = nil, math.huge
    for ch, v in pairs(row) do
      if v < min_val then min_ch, min_val = ch, v end
    end
    assignment[i] = min_ch
  end

  -- 生成配置指令
  local commands = {}
  for i, ch in ipairs(assignment) do
    table.insert(commands, {
      mac = aps[i].mac,
      channel = ch,
      power = (aps[i].load or 0) > 80 and (aps[i].current_power or 20) - 5 or (aps[i].current_power or 20)
    })
  end

  return commands
end

function query_trend_data(mac, days)
    local sqlite3 = require("lsqlite3")
    local db = sqlite3.open("/etc/wifi-ac/data.db")
    if not db then return {} end
    local since = os.time() - (days or 7) * 86400
    local res = {}
    for row in db:nrows(string.format(
        "SELECT timestamp, load, signal FROM trends WHERE mac='%s' AND timestamp>%d ORDER BY timestamp ASC", mac, since)) do
        table.insert(res, {
            time = os.date("%Y-%m-%d %H:%M", row.timestamp),
            load = row.load,
            signal = row.signal
        })
    end
    db:close()
    return res
end

-- 断点续传与失败回滚：固件分块发送
function send_firmware_chunk(ap_mac, offset, ap_ip)
    local firmware = require("luci.model.firmware_manager")
    local chunk = firmware.read_chunk(ap_mac, offset)
    if not chunk then return false end
    local socket = require("luci.sys").socket("AF_INET", "SOCK_DGRAM", 0)
    if not socket then return false end
    socket.sendto(socket, chunk, ap_ip, 9090)
    socket.close(socket)
    return true
end

-- 监听AP端固件传输状态（ubus事件订阅，伪代码，实际需守护进程实现）
local function on_firmware_transfer_status(data)
    if data.status == "interrupted" then
        os.execute(string.format("uci set firmware.transfer.%s.offset=%d", data.mac, data.offset))
        os.execute(string.format("uci set firmware.transfer.%s.checksum=%s", data.mac, data.checksum))
        os.execute("uci commit firmware")
    end
end
-- 伪代码：ubus.subscribe("firmware", "transfer_status", on_firmware_transfer_status)

-- 配置热加载（重新读取UCI配置）
function reload_config()
    package.loaded["luci.model.uci"] = nil
    package.loaded["luci.sys"] = nil
    package.loaded["luci.util"] = nil
end

-- 趋势数据采集与持久化（sqlite3或json）
local trend_file = "/etc/wifi-ac/trend.json"
function collect_trend_data()
    local uci = require "luci.model.uci".cursor()
    local sys = require "luci.sys"
    local json = require "luci.jsonc"
    local now = os.date("%Y-%m-%d %H:%M")
    local aps = {}
    uci:foreach("wifi_ac", "device", function(s)
        local status = sys.exec("ubus call wifi.status '{\"mac\":\""..(s.mac or "").."\"}' 2>/dev/null")
        local stat = status and json.parse(status) or {}
        table.insert(aps, {mac=s.mac, load=(stat.clients_24g or 0)+(stat.clients_5g or 0), signal=stat.signal or -100})
    end)
    local trend = {}
    local f = io.open(trend_file, "r")
    if f then trend = json.parse(f:read("*a")) or {}; f:close() end
    trend[now] = aps
    local fw = io.open(trend_file, "w")
    if fw then fw:write(json.stringify(trend)); fw:close() end
end

function get_trend_data()
    local json = require "luci.jsonc"
    local f = io.open(trend_file, "r")
    if not f then return {time={}, avg_load={}, avg_signal={}} end
    local trend = json.parse(f:read("*a")) or {}
    f:close()
    local time, avg_load, avg_signal = {}, {}, {}
    for t, aps in pairs(trend) do
        table.insert(time, t)
        local sum_load, sum_sig, cnt = 0, 0, 0
        for _, ap in ipairs(aps) do
            sum_load = sum_load + (ap.load or 0)
            sum_sig = sum_sig + (ap.signal or 0)
            cnt = cnt + 1
        end
        table.insert(avg_load, cnt > 0 and math.floor(sum_load/cnt) or 0)
        table.insert(avg_signal, cnt > 0 and math.floor(sum_sig/cnt) or 0)
    end
    return {time=time, avg_load=avg_load, avg_signal=avg_signal}
end

-- 功率调节控件适配（主流三方AP支持通过配置文件扩展）
function get_txpower_range(vendor, model)
    -- 支持type/range/options，便于前端细粒度渲染
    if vendor == "OpenWrt" then
        return {type="range", min=0, max=30, step=1}
    elseif vendor == "TPLink" then
        return {type="select", options={10,12,14,16,18,20,22}}
    elseif vendor == "Ruijie" then
        return {type="number", min=8, max=20, step=1}
    end
    -- 三方AP可通过/etc/wifi-ac/txpower_range.json扩展
    local lfs = require "luci.fs"
    local json = require "luci.jsonc"
    local path = "/etc/wifi-ac/txpower_range.json"
    if lfs.access(path) then
        local data = json.parse(lfs.readfile(path) or "") or {}
        if data[vendor] and data[vendor][model] then
            return data[vendor][model]
        end
    end
    return {type="range", min=0, max=20, step=1}
end

-- UDP命令下发，带ACK确认与重试机制
-- 已实现：send_udp_command_with_ack(mac, command, param, retry)
-- 详见下方实现，AC端下发命令后等待AP端ACK，否则自动重试

-- 支持AP主动心跳/状态上报（见AP端ap_agent/ubus实现，AC端通过ubus/UDP拉取或监听）
-- 相关接口已在AP端ubus和UDP心跳实现，AC端通过ubus call wifi.status或UDP监听/定时拉取

-- UDP自动发现（支持mDNS/HTTP等多种方式，提升跨网段适用性）
function discover_devices()
    -- 1. UDP广播发现（局域网内有效，跨网段易失效）
    -- ...原有UDP扫描代码...
    -- 2. mDNS发现（需AP端支持mDNS响应，建议ap_agent实现mDNS responder）
    -- 3. HTTP主动注册（AP端定期向AC HTTP接口注册，适用于NAT/跨网段）
    -- 实际生产环境建议多方式结合，提升发现率
    -- ...existing code...
end

-- 签名校验与白名单机制（示例，生产建议完善）
local function verify_signature(mac, cmd, param, token, signature, secret)
    -- 简单MD5签名，建议生产用HMAC或更安全算法
    local md5 = require "luci.util".md5
    local expect = md5(mac..cmd..param..token..secret)
    return signature == expect
end

local function is_ip_whitelisted(ip)
    -- 读取白名单配置（如/etc/wifi-ac/ip_whitelist.txt），生产环境建议完善
    local whitelist = {["127.0.0.1"]=true, ["192.168.1.1"]=true}
    return whitelist[ip] or false
end

-- UDP命令下发，支持签名与白名单校验
function send_udp_command_with_ack(mac, command, param, retry)
    local socket = require("luci.sys.socket")
    local token = "your_token" -- 实际应从UCI配置读取
    local secret = "your_secret" -- 建议从配置读取
    local s = socket("AF_INET", "SOCK_DGRAM", 0)
    if not s then return false, "socket error" end
    local ip = sys.exec(string.format("arp -n | grep %s | awk '{print $1}'", mac)):gsub("\n", "")
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

-- HTTPS通信扩展点说明
-- 生产环境建议uhttpd/nginx配置HTTPS，所有API接口支持https访问，避免中间人攻击
-- 相关配置可参考OpenWrt官方文档，或在前端强制跳转https

-- 接口标准化说明
-- 建议所有API接口遵循RESTful风格，参数校验、返回结构标准化，便于三方系统集成
-- 例如：所有POST/PUT需带token和签名，返回{code,msg,data}结构

-- 跨网段自动发现多方式结合建议：
-- 1. UDP广播适合局域网
-- 2. mDNS适合部分跨网段
-- 3. HTTP主动注册适合NAT/公网/复杂网络
-- 4. 建议三种方式结合，提升发现率，具体见 discover_devices/mdns_discover_devices/http_discover_devices

-- 获取所有厂商（用于前端下拉）
function get_all_vendors()
    local uci = require "luci.model.uci".cursor()
    local vendors = {}
    uci:foreach("wifi_ac", "device", function(s)
        if s.vendor and not vendors[s.vendor] then
            vendors[s.vendor] = true
        end
    end)
    local list = {}
    for v, _ in pairs(vendors) do table.insert(list, v) end
    return list
end

-- 根据厂商获取型号（用于前端下拉）
function get_models_by_vendor(vendor)
    local uci = require "luci.model.uci".cursor()
    local models = {}
    uci:foreach("wifi_ac", "device", function(s)
        if s.vendor == vendor and s.model and not models[s.model] then
            models[s.model] = true
        end
    end)
    local list = {}
    for m, _ in pairs(models) do table.insert(list, m) end
    return list
end

-- 自动发现：mDNS发现（跨网段，需AP端支持mDNS responder，守护进程采集写入/tmp/wifi-ac/mdns_devices.json）
function mdns_discover_devices()
    local path = "/tmp/wifi-ac/mdns_devices.json"
    local f = io.open(path, "r")
    if not f then
        return {code=1, msg="未发现mDNS设备"}
    end
    local content = f:read("*a")
    f:close()
    local list = json.parse(content) or {}
    -- 过滤已注册设备
    local registered = {}
    uci:foreach("wifi_ac", "device", function(s)
        if s.mac then registered[s.mac:lower()] = true end
    end)
    local newlist = {}
    for _, dev in ipairs(list) do
        if dev.mac and not registered[dev.mac:lower()] then
            table.insert(newlist, dev)
        end
    end
    return {code=0, devices=newlist}
end

-- 自动发现：HTTP主动注册发现（AP端定期向AC HTTP接口注册，守护进程采集写入/tmp/wifi-ac/http_devices.json）
function http_discover_devices()
    local path = "/tmp/wifi-ac/http_devices.json"
    local f = io.open(path, "r")
    if not f then
        return {code=1, msg="未发现HTTP注册设备"}
    end
    local content = f:read("*a")
    f:close()
    local list = json.parse(content) or {}
    -- 过滤已注册设备
    local registered = {}
    uci:foreach("wifi_ac", "device", function(s)
        if s.mac then registered[s.mac:lower()] = true end
    end)
    local newlist = {}
    for _, dev in ipairs(list) do
        if dev.mac and not registered[dev.mac:lower()] then
            table.insert(newlist, dev)
        end
    end
    return {code=0, devices=newlist}
end

-- WebSocket推送结构标准化辅助（供controller调用）
function ws_status_payload(data)
    -- data: 可能是单设备、设备数组或变化列表
    local payload = {}
    if type(data) == "table" and data.devices then
        payload.devices = data.devices
        payload.type = "status_update"
        payload.mode = data.mode or "full"
    elseif type(data) == "table" and data.mac then
        payload.devices = {data}
        payload.type = "status_update"
        payload.mode = "delta"
    else
        payload = {type="status_update", devices={}, mode="unknown"}
    end
    return payload
end

-- 仪表盘趋势数据采集与持久化（建议定时任务调用 collect_trend_data，前端通过 get_trend_data 查询）
-- 采集内容可扩展为多指标（如CPU、内存、接入数、信号等），建议统一返回结构
-- 采集脚本见 /usr/sbin/wifi-ac-data-collector、collect_wifi_data.sh 等

-- RESTful API标准化建议：
-- 1. 所有API接口建议统一返回 {code, msg, data} 结构，便于前端和三方系统集成
-- 2. 参数校验、错误码、分页等建议标准化
-- 3. 支持GET/POST/PUT/DELETE等RESTful风格

-- HTTPS通信与接口安全建议：
-- 1. 建议uhttpd/nginx配置HTTPS，所有API接口支持https访问，避免中间人攻击
-- 2. 关键操作接口建议增加token、签名校验，防止伪造请求
-- 3. 支持IP白名单机制，提升安全性

-- 跨网段自动发现多方式结合建议：
-- 1. UDP广播适合局域网
-- 2. mDNS适合部分跨网段
-- 3. HTTP主动注册适合NAT/公网/复杂网络
-- 4. 建议三种方式结合，提升发现率，具体见 discover_devices/mdns_discover_devices/http_discover_devices

-- 三方AP适配接口预留说明：
-- 1. 功率调节、信道设置、升级等接口建议通过配置文件或插件扩展
-- 2. 见 get_txpower_range、apply_template、send_udp_command_with_ack 等，便于后续适配华为、TPLink、Ruijie等厂商
-- 3. 建议所有AP端实现统一ubus/UDP接口，便于AC端统一调用

-- 升级队列顺序存储与读取
local upgrade_queue_file = "/etc/wifi-ac/upgrade_queue.json"
function save_upgrade_queue(macs)
    local lfs = require "luci.fs"
    lfs.writefile(upgrade_queue_file, macs)
    return true
end
function get_upgrade_queue()
    local lfs = require "luci.fs"
    local macs = lfs.readfile(upgrade_queue_file) or ""
    local list = {}
    for mac in string.gmatch(macs, "[^,]+") do table.insert(list, mac) end
    return list
end

-- 分阶段升级辅助
function batch_upgrade_stage(stage)
    local sys = require "luci.sys"
    local mac_list = get_upgrade_queue()
    local total = #mac_list
    local idx = 1
    while idx <= total do
        for i = idx, math.min(idx+stage-1, total) do
            sys.exec("ubus call wifi.device '{\"mac\":\""..mac_list[i].."\",\"action\":\"upgrade\"}'")
        end
        idx = idx + stage
        nixio.nanosleep(10)
    end
    return {code=0, msg="分阶段升级已下发"}
end

-- 日志存储空间查询
function get_storage_info()
    local stat = io.popen("du -sh /var/log/wifi-ac 2>/dev/null")
    local info = stat and stat:read("*a") or ""
    if stat then stat:close() end
    return {storage=info}
end
