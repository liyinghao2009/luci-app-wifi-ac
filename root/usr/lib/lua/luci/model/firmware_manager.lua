local lfs = require "luci.fs"
local json = require "luci.jsonc"
local chunk_size = 1024 * 1024  -- 1MB，实际可从配置读取

local M = {}

function M.read_chunk(ap_mac, offset)
    local fw_path = "/etc/wifi-ac/firmware/" .. ap_mac .. ".bin"
    local f = io.open(fw_path, "rb")
    if not f then return nil end
    f:seek("set", offset)
    local data = f:read(chunk_size)
    f:close()
    if not data then return nil end
    local b64 = require("luci.util").b64encode(data)
    return json.stringify({
        type = "chunk",
        mac = ap_mac,
        offset = offset,
        data = b64
    })
end

return M
