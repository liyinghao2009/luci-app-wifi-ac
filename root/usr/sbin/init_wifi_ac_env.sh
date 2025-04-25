#!/bin/sh

# 1. 创建数据存储目录
mkdir -p /etc/wifi-ac/

# 2. 初始化sqlite3数据库（需提前准备schema.sql）
if [ -f /etc/wifi-ac/schema.sql ]; then
    sqlite3 /etc/wifi-ac/data.db < /etc/wifi-ac/schema.sql
fi

# 3. 启动ubus数据订阅（需env_handler.sh脚本实现处理逻辑）
ubus subscribe wifi_environment ap_status /usr/sbin/env_handler.sh &

# 4. 开启UDP监听（AC端，记录收到的命令）
mkdir -p /var/log/wifi
nc -ul 9090 > /var/log/wifi-ac/udp_commands.log &

# 统一端口配置（如需将所有API/前端/WS服务统一到8080端口）
AC_PORT="${AC_PORT:-8080}"

# 可用于后续脚本、守护进程、uhttpd/nginx配置等
export AC_PORT

# 示例：uhttpd配置自动修改（如存在/etc/config/uhttpd）
if grep -q "option listen_http" /etc/config/uhttpd; then
    uci set uhttpd.main.listen_http="0.0.0.0:$AC_PORT"
    uci set uhttpd.main.listen_https="0.0.0.0:$(($AC_PORT + 1))"
    uci commit uhttpd
    /etc/init.d/uhttpd restart
fi
