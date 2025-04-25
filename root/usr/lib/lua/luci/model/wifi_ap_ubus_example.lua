-- AP端需实现的ubus接口标准示例
-- 建议所有AP端实现如下ubus接口，便于AC端统一调用和扩展
-- 三方AP适配时可参考本文件，留接口和注释，便于后续扩展

local ubus = require "ubus"
local conn = ubus.connect()

-- 白名单进程名（可根据实际需求配置）
local process_whitelist = {["ap_agent"]=true, ["rpcd"]=true}

local function local_auth()
    -- 仅允许root或白名单进程名
    local uid = tonumber(io.popen("id -u"):read("*l"))
    if uid ~= 0 then return false end
    -- 校验/proc/self/cmdline是否为白名单进程
    local cmdline = io.open("/proc/self/cmdline"):read("*a") or ""
    for pname in pairs(process_whitelist) do
        if cmdline:find(pname, 1, true) then
            return true
        end
    end
    return false
end

-- 签名校验示例（实际部署应用更安全算法）
local function verify_signature(mac, cmd, param, token, signature, secret)
    -- 简单示例：md5(mac..cmd..param..token..secret)
    local md5 = require "luci.util".md5
    local expect = md5(mac..cmd..param..token..secret)
    return signature == expect
end

-- 状态上报接口
conn:add("wifi.status", {
    get = {
        function(req)
            if not local_auth() then
                return {code=403, msg="本地权限不足"}
            end
            local mac = req.mac
            -- 返回AP状态
            return {
                mac = mac,
                status = "online",
                cpu = 23,
                mem = 41,
                clients_24g = 12,
                clients_5g = 8,
                ip = "192.168.1.2",
                vendor = "Huawei",
                model = "AP123",
                firmware = "v1.0.2"
            }
        end, {mac="string"}
    }
})

-- UDP命令监听与ACK机制（建议由ap_agent守护进程实现）
-- 已实现：收到AC下发命令后，AP端立即回复ACK（ACK:<mac>,<cmd>,code=0,msg=ok），AC端收到ACK才认为下发成功，否则重试
local socket = require "socket"
local udp = socket.udp()
udp:setsockname("0.0.0.0", 9090)
udp:settimeout(0)

-- 支持ACK确认与详细结果反馈（AC端实现重试，AP端需及时ACK并返回操作结果/错误码）
local function handle_udp_command()
    local data, ip, port = udp:receivefrom()
    if data then
        -- 协议格式: <mac>,<command>,<params>,<token>[,signature]
        local mac, cmd, param, token, signature = data:match("([^,]+),([^,]*),([^,]*),([^,]+),?(.*)")
        -- 校验token
        if token ~= "your_token" then
            return
        end
        -- 校验签名（如有）
        if signature and signature ~= "" then
            if not verify_signature(mac, cmd, param, token, signature, "your_secret") then
                return
            end
        end
        -- 处理命令
        local result = {code=0, msg="ok"}
        -- 例如: if cmd == "set_channel" then ... end
        -- ...实际命令处理，result.code/result.msg可根据执行情况设置...
        -- 发送ACK+结果，AC端收到ACK后可认为下发成功，否则重试
        udp:sendto("ACK:"..mac..","..cmd..",code="..tostring(result.code)..",msg="..tostring(result.msg), ip, port)
        -- 建议记录操作日志
        -- local log = io.open("/var/log/ap_agent.log", "a")
        -- if log then log:write(os.date().." "..mac.." "..cmd.." "..result.code.." "..result.msg.."\n"); log:close() end
    end
end

-- 主循环（建议放到ap_agent守护进程，示例代码）
-- while true do
--     handle_udp_command()
--     socket.sleep(0.1)
-- end

-- 远程命令接口（标准接口，三方AP可扩展action分支）
conn:add("wifi.device", {
    set_channel = {
        function(req)
            if not local_auth() then
                return {code=403, msg="本地权限不足"}
            end
            if req.token ~= "your_token" then
                return {code=403, msg="无效Token"}
            end
            -- 可选：签名校验
            -- if not verify_signature(...) then return {code=403, msg="签名校验失败"} end
            -- 实际执行
            -- os.execute("iw dev wlan0 set channel " .. req.channel)
            return {code=0, msg="ok"}
        end, {mac="string", action="string", channel="number", token="string"}
    }
    -- ...更多命令...
    -- 三方AP适配：可在此处增加自定义action分支，如set_power、upgrade等
})

-- AP主动心跳/状态上报（建议由ap_agent定时执行）
-- 已实现：send_heartbeat(ac_ip, ac_port) 示例，建议定时上报静态与动态状态
local function send_heartbeat(ac_ip, ac_port)
    local sock = socket.udp()
    local status = {
        mac = "xx:xx:xx:xx:xx:xx",
        status = "online",
        cpu = 23,
        mem = 41,
        clients_24g = 12,
        clients_5g = 8,
        ip = "192.168.1.2",
        vendor = "Huawei",
        model = "AP123",
        firmware = "v1.0.2"
    }
    local json = require "luci.jsonc"
    sock:sendto(json.stringify(status), ac_ip, ac_port or 9090)
    sock:close()
end
-- 定时调用 send_heartbeat(ac_ip, ac_port)

-- mDNS/HTTP自动发现（建议由ap_agent实现，略，见README）
-- 建议ap_agent支持mDNS响应和HTTP主动注册，提升跨网段适用性

-- mDNS响应与HTTP主动注册（建议由ap_agent实现，提升跨网段适用性）
-- mDNS响应：建议ap_agent调用 avahi-publish-service 注册AP信息，AC端可通过mDNS发现AP
-- HTTP主动注册：ap_agent定期向AC的/api/ap_register接口POST自身信息，适配NAT/跨网段环境
-- 详见ap_agent脚本mdns_announce和http_register函数

-- 示例：关键事件ubus推送（上线/离线/升级/异常等）
local function push_event(event, data)
    local ok, ubus = pcall(require, "ubus")
    if ok and ubus then
        local conn = ubus.connect()
        if conn then
            conn:send("wifi_ap."..event, data or {})
            conn:close()
        end
    end
end

-- 例如：上线事件
-- push_event("status_update", {mac="xx:xx:xx:xx:xx:xx", status="online", time=os.time()})
-- 例如：升级完成事件
-- push_event("operation", {mac="xx:xx:xx:xx:xx:xx", action="upgrade", code=0, msg="done", time=os.time()})

-- 关闭连接
conn:close()