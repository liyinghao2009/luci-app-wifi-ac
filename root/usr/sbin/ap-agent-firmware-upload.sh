#!/bin/sh
# AP端分块接收与断点续传/回滚示例

UPLOAD_LOG="/tmp/firmware_upload.log"
BACKUP="/firmware/backup.bin"
TARGET="/firmware/upgrade.bin"

# 接收分块（伪接口，实际应由HTTP/ubus服务实现）
# 参数: $1=offset $2=base64_chunk
offset="$1"
chunk_b64="$2"
[ -z "$offset" ] && exit 1
[ -z "$chunk_b64" ] && exit 1

chunk_bin=$(echo "$chunk_b64" | base64 -d)
dd if=/dev/zero of=$TARGET bs=1 count=0 seek=$offset 2>/dev/null
echo -n "$chunk_bin" | dd of=$TARGET bs=1 seek=$offset conv=notrunc 2>/dev/null

echo "$offset" > $UPLOAD_LOG

# 回滚机制
if [ "$3" = "rollback" ]; then
    [ -f "$BACKUP" ] && cp "$BACKUP" "$TARGET"
fi
