#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
API_DOMAIN="https://www.heyunidc.cn"
ACCOUNT="cokei521@qq.com"       # 替换为你的账户名
PASSWORD="JtqIWj1aXus3"      # 替换为你的API Key
JWT_CACHE_FILE="${SCRIPT_DIR}/jwt_${ACCOUNT}.cache"
LOG_FILE="${SCRIPT_DIR}/monitor.jsonl" # 使用 jsonl 格式存储日志

if ! command -v jq &> /dev/null; then
    echo '{"time":"'$(date -Iseconds)'","level":"ERROR","msg":"jq not installed"}' >> "$LOG_FILE"
    exit 1
fi

# 封装JSON日志记录函数
log_json() {
    local level=$1; local msg=$2; local host_id=${3:-""}; local ip=${4:-""}
    jq -nc --arg t "$(date -Iseconds)" --arg l "$level" --arg m "$msg" \
           --arg hid "$host_id" --arg ip "$ip" \
           '{time: $t, level: $l, msg: $m, host_id: $hid, ip: $ip}' >> "$LOG_FILE"
}

get_cached_jwt() { [ -f "$JWT_CACHE_FILE" ] && cat "$JWT_CACHE_FILE"; }

login_and_cache() {
    local resp=$(curl -s -X POST "${API_DOMAIN}/v1/login_api" -H "Content-Type: application/json" \
        -d "{\"account\":\"${ACCOUNT}\",\"password\":\"${PASSWORD}\"}")
    local jwt=$(echo "$resp" | jq -r '.jwt')
    if [ -z "$jwt" ] || [ "$jwt" == "null" ]; then
        log_json "ERROR" "登录失败: $resp"; return 1
    fi
    echo "$jwt" > "$JWT_CACHE_FILE"; echo "$jwt"
}

log_json "INFO" "========== 开始执行主机状态检查 =========="
JWT=$(get_cached_jwt)
if [ -n "$JWT" ]; then
    HOSTS_RESP=$(curl -s -X GET "${API_DOMAIN}/v1/hosts" -H "authorization: JWT ${JWT}")
    if [ -z "$(echo "$HOSTS_RESP" | jq -r '.data.total // empty')" ]; then
        log_json "WARN" "缓存的JWT已失效，正在重新登录..."
        JWT=$(login_and_cache) || exit 1
        HOSTS_RESP=$(curl -s -X GET "${API_DOMAIN}/v1/hosts" -H "authorization: JWT ${JWT}")
    else log_json "INFO" "JWT缓存有效！"; fi
else
    log_json "INFO" "未检测到JWT缓存，首次登录..."
    JWT=$(login_and_cache) || exit 1
    HOSTS_RESP=$(curl -s -X GET "${API_DOMAIN}/v1/hosts" -H "authorization: JWT ${JWT}")
fi

HOST_IDS=$(echo "$HOSTS_RESP" | jq -r '.data.host[] | select(.type == "dcimcloud" and .domainstatus == "Active") | .id')
[ -z "$HOST_IDS" ] && { log_json "WARN" "未找到符合条件的活跃主机。"; exit 0; }

for HOST_ID in $HOST_IDS; do
    HOST_IP=$(echo "$HOSTS_RESP" | jq -r ".data.host[] | select(.id == ${HOST_ID}) | .dedicatedip")
    STATUS_RESP=$(curl -s -X GET "${API_DOMAIN}/v1/hosts/${HOST_ID}/module/status?type=host" -H "authorization: JWT ${JWT}")
    HOST_STATUS=$(echo "$STATUS_RESP" | jq -r '.data.status')
    HOST_DES=$(echo "$STATUS_RESP" | jq -r '.data.des')

    if [ "$HOST_STATUS" == "on" ]; then
        if [ -n "$HOST_IP" ] && [ "$HOST_IP" != "null" ] && ping -c 3 -W 1 "$HOST_IP" &> /dev/null; then
            log_json "INFO" "状态正常(API: ${HOST_DES}, Ping: 可达)" "$HOST_ID" "$HOST_IP"
        else
            log_json "WARN" "API显示开机但Ping不可达" "$HOST_ID" "$HOST_IP"
        fi
    else
        if [ -n "$HOST_IP" ] && [ "$HOST_IP" != "null" ] && ping -c 3 -W 1 "$HOST_IP" &> /dev/null; then
            log_json "INFO" "API显示${HOST_DES}，但Ping可达，暂不干预。" "$HOST_ID" "$HOST_IP"
        else
            log_json "WARN" "异常且不可达，正在发起硬重启..." "$HOST_ID" "$HOST_IP"
            REBOOT_RESP=$(curl -s -X PUT "${API_DOMAIN}/v1/hosts/${HOST_ID}/module/hard_reboot" -H "authorization: JWT ${JWT}")
            REBOOT_MSG=$(echo "$REBOOT_RESP" | jq -r '.msg')
            log_json "ACTION" "硬重启结果: ${REBOOT_MSG}" "$HOST_ID" "$HOST_IP"
        fi
    fi
done
log_json "INFO" "========== 所有主机检查完毕 =========="