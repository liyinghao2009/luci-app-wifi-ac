# luci-app-wifi-ac 项目说明

## 目录结构

```
luci-app-wifi-ac/
├── Makefile
├── ap-agent-README.md           # AP端对接说明
├── 前端功能.md                  # 前端功能梳理
├── 后端功能.md                  # 后端功能梳理
├── root/
│   ├── etc/
│   │   └── config/
│   │       └── wifi_ac
│   │   └── wifi-ac/
│   │       ├── roles.json
│   │       ├── template_schema.json
│   │       └── *.json
│   ├── usr/
│   │   └── lib/
│   │       └── lua/
│   │           ├── controller/
│   │           │   └── wifi_ac.lua
│   │           ├── model/
│   │           │   ├── wifi_ac.lua
│   │           │   └── wifi_ap_ubus_example.lua
│   │           └── view/
│   │               └── wifi_ac/
│   │                   ├── settings.htm
│   │                   ├── optimization.htm
│   │                   └── ...
│   └── www/
│       └── luci-static/
│           └── resources/
│               └── wifi-ac/
│                   ├── js/
│                   │   ├── main.js
│                   │   ├── device.js
│                   │   ├── optimization.js
│                   │   ├── firmware.js
│                   │   ├── log.js
│                   │   └── settings.js
│                   ├── css/
│                   │   └── style.css
│                   └── img/
│                       └── vendor_logo.png
├── po/
│   └── zh-cn/wifi-ac.po
```

## 模块功能概览

### 1. 设备管理模块

**已实现：**
- 设备列表展示（LOGO、型号、MAC、IP、状态、CPU/内存、接入量、固件等）
- 多条件筛选（厂商、状态、固件）、MAC/名称搜索
- 批量操作（重启、升级、配置同步）
- 自动发现（UDP/mDNS/HTTP注册，需AP端配合）
- 设备注册/删除、WebSocket推送
- 设备详情弹窗、实时状态刷新（WebSocket）

**待完善/建议：**
- 跨网段自动发现完善（需AP端mDNS responder/主动注册）
- 设备添加重复检测（后端校验MAC/IP唯一性）
- 设备状态推送结构标准化，支持增量/全量
- 表格渲染优化、LOGO图片兜底
- 移动端适配、国际化全覆盖

### 2. 性能优化模块

**已实现：**
- 自动信道分配/负载均衡（基础算法，支持批量下发）
- 手动信道/功率分配API
- 优化任务队列、进度与日志反馈
- 策略模板管理与批量应用
- 信道热力图、趋势数据API（部分为示例数据）
- 功率调节控件（基础控件）、阈值设置
- 优化进度与日志反馈（定时拉取/推送）

**待完善/建议：**
- 复杂负载均衡/干扰感知算法（邻居AP干扰、动态负载均衡）
- 功率调节控件细粒度适配（后端返回type/range/options，前端动态渲染）
- 趋势图自定义时间范围、导出CSV/PDF
- 优化操作权限细粒度校验（前后端联动）
- 批量操作/模板应用失败详细展示与重试
- 升级队列拖拽排序、分阶段升级

### 3. 固件升级与日志系统

**已实现：**
- 固件仓库管理（上传、哈希校验、版本管理）
- 批量升级队列、升级状态实时监控
- 日志分类与高级查询、导出CSV/PDF
- WebSocket实时告警推送、日志结构含用户字段

**待完善/建议：**
- 断点续传与失败回滚（需AP端支持分块传输、断点续传）
- 日志轮转与自动清理（实现日志归档/清理脚本）
- 日志API权限细粒度控制（前端按权限控制，后端API需完善）
- 日志导出PDF美化（集成专业PDF库，支持图表摘要）
- 日志存储占用展示（前端展示日志空间占用，调用后端API）

### 4. 系统设置与仪表盘

**已实现：**
- 基础参数配置、RADIUS对接、模板管理、权限管理、恢复出厂
- 仪表盘统计、趋势图、快捷入口
- 滚动通知、信号分布美化（ECharts渐变色、动画、可关闭）

**待完善/建议：**
- 权限管理细粒度分配界面（前端弹窗分配角色权限，联动后端API）
- 仪表盘趋势图多指标切换（负载/信号/接入数切换）
- 权限管理细粒度控制（角色/操作级别权限配置，API校验）
- 仪表盘趋势数据采集持久化（完善采集脚本，支持多指标、历史查询）

### 5. 其它建议与扩展点

- 结构进一步模块化，减少重复逻辑
- 增强移动端适配
- 操作二次确认与高危操作权限校验
- 前后端接口参数/返回结构标准化
- 支持HTTPS通信，接口签名与白名单机制
- 跨网段自动发现多方式结合
- 三方AP适配接口预留，便于后续扩展


## OpenWrt 23.05 内置或可选依赖（本项目用到的）

- `luci-base`                # LuCI 基础库
- `luci-mod-admin-full`      # LuCI 完整管理界面
- `luci-mod-network`         # 网络管理模块
- `luci-mod-status`          # 状态模块
- `luci-mod-system`          # 系统管理模块
- `luci-theme-bootstrap`     # 默认主题
- `luci-lib-jsonc`           # JSON 解析
- `luci-lib-nixio`           # 系统IO库
- `luci-lib-uci`             # UCI 配置库
- `luci-lib-ip`              # IP工具库
- `luci-lib-nl`              # netlink库
- `luci-lib-httpclient`      # HTTP客户端
- `rpcd`                     # RPC守护进程
- `rpcd-mod-rrdns`           # 反向DNS插件
- `uhttpd`                   # Web服务器
- `uhttpd-mod-ubus`          # uhttpd的ubus支持
- `ubus`                     # OpenWrt总线
- `ubusd`                    # OpenWrt总线守护进程
- `uci`                      # 配置系统
- `iwinfo`                   # 无线信息
- `netifd`                   # 网络接口守护进程
- `jsonfilter`               # JSON过滤工具
- `coreutils`                # 基础命令行工具
- `coreutils-base64`         # base64工具
- `coreutils-stat`           # stat工具
- `coreutils-sort`           # sort工具
- `coreutils-sha256sum`      # sha256sum工具
- `busybox`                  # 常用命令集合
- `logrotate`                # 日志轮转
- `opkg`                     # 软件包管理
- `libubox`                  # 基础库
- `libubus`                  # 基础库
- `libuci`                   # 基础库
- `libjson-c`                # 基础库
- `libnl-tiny`               # 基础库
- `libopenssl`               # 基础库
- `ca-bundle`                # CA证书
- `ca-certificates`          # CA证书
- `dnsmasq`                  # DHCP/DNS
- `odhcpd-ipv6only`          # IPv6 DHCP
- `iptables` 或 `nftables`   # 防火墙
- `ip-full`                  # ip命令
- `ipset`                    # IP集合
- `iptables-mod-tproxy`      # 透明代理（如需）
- `kmod-*`                   # 内核模块（如无线/网络相关，具体名称视硬件和功能需求）
- `cronie` 或 `cron`         # 定时任务（部分固件内置，部分需手动安装）
- `sqlite3-cli`              # sqlite3命令行工具（趋势数据持久化，部分功能可选）
- `libsqlite3`               # sqlite3库
- `curl`                     # 固件下载
- `wget`                     # 固件下载
- `bash`                     # 部分脚本依赖
- `inotify-tools`            # 配置热加载（可选）
- `lua-cjson`                # Lua JSON支持
- `luasocket`                # Lua socket支持

## OpenWrt 23.05 内置或可选依赖（标准包）包含情况说明

- **不包含**以下前端依赖（需手动引入或通过npm/cdn等方式集成）：
  - `echarts`
  - `chart.js`
  - `jspdf`
  - `pdfmake`

- **部分包含**后端依赖：
  - `sqlite3`：**可选包**，默认未安装，需自行安装。
  - `curl`：**可选包**，部分固件内置，部分需手动安装。
  - `wget`：**可选包**，部分固件内置，部分需手动安装。
  - `openssl`：**常见内置包**，大多数固件已包含。
  - `inotify-tools`：**可选包**，默认未安装，需自行安装。
  - `bash`：**可选包**，部分固件内置，部分需手动安装（OpenWrt 默认 shell 为 ash）。
  - `python3`：**可选包**，默认未安装，需自行安装。

- **AP 端配合**相关内容均为三方/外部实现，OpenWrt 官方固件不自带：
  - 守护进程（如 `ap_agent`）
  - `avahi-daemon` 或其他 mDNS responder
  - UDP/HTTP 注册脚本
  - `netcat`（UDP监听/调试用，可选）

// 结论：上述依赖均不属于 OpenWrt 23.05 的默认内置标准包，除 `openssl`、`curl`、`wget` 可能在部分固件中预装外，其余需根据实际需求手动安装或集成。

## 三方或外部依赖（需手动安装或集成）

- 前端依赖（OpenWrt 不自带，需CDN或npm等方式引入）：
  - `echarts`        # 信号分布、热力图、趋势图
  - `chart.js`       # 趋势图
  - `jspdf`          # 日志导出 PDF
  - `pdfmake`        # 日志导出 PDF（可选）

- 后端依赖（部分为可选包，部分需手动安装）：
  - `sqlite3`        # 趋势数据持久化（可选）
  - `curl`           # 固件下载（部分固件内置，部分需手动安装）
  - `wget`           # 固件下载（部分固件内置，部分需手动安装）
  - `openssl`        # 签名/加密（大多数固件已包含）
  - `inotify-tools`  # 配置热加载（可选）
  - `bash`           # 部分脚本依赖（OpenWrt 默认 shell 为 ash，部分固件内置，部分需手动安装）
  - `python3`        # 高级数据处理/采集脚本（可选）

- AP 端配合（OpenWrt 官方固件不自带，需三方实现）：
  - 守护进程（如 `ap_agent`） # AP端对接AC的守护进程
  - `avahi-daemon` 或其他 mDNS responder # mDNS发现
  - UDP/HTTP 注册脚本
  - `netcat`（UDP监听/调试用，可选）

// 注：如 `logrotate`、`cronie`/`cron` 已在内置依赖中出现，无需重复列为外部依赖。

## AP端对接说明

详见 `ap-agent-README.md`，核心要求如下：

- 实现标准ubus接口（wifi.status、wifi.device等）
- 支持UDP ACK、mDNS/HTTP注册、心跳/状态上报
- 支持批量命令ACK与失败重试
- 日志轮转与权限审计、趋势数据采集与持久化
- 支持HTTPS、Token/签名/白名单机制

## 接口与数据结构标准

- 所有API建议RESTful风格，参数/返回结构统一（如 `{code,msg,data}`）
- 日志、状态、配置模板等建议采用JSON结构，便于对接和扩展
- 关键操作接口建议增加token、签名校验，防止伪造请求

---

如需详细接口协议、AP端守护进程代码模板或三方适配建议，请参考 `ap-agent-README.md` 或补充需求。
