# 魔方财务 主机自动检查与重启脚本

自动检测 魔方财务（核云为例） 平台上 dcimcloud 类型的主机状态，在状态异常重启前检查ping, 如果ping正常则不执行重启（主要针对主控异常的“未知”状态）。。

## 配置

编辑 `heyun_monitor.sh` 顶部的配置项：

```bash
API_DOMAIN="https://www.heyunidc.cn"
ACCOUNT="your_account"
PASSWORD="you_api_key"
```

## 依赖

- **bash**
- **curl**
- **jq**（用于解析 JSON 响应）

安装 jq：

```bash
# Debian/Ubuntu
apt-get install jq

# CentOS/RHEL
yum install jq
```

## 手动运行

```
./heyun_monitor.sh
```

## 配合 cron 定时执行

添加 crontab 任务，每 5 分钟检查一次：

```bash
crontab -e
```

写入：

```
*/5 * * * * bash /path/to/your/heyun_monitor.sh >> /var/log/check.log 2>&1
```

> **注意**：必须使用 `bash` 而非 `sh` 执行，脚本使用了 bash 特有语法（`BASH_SOURCE`、`==` 等），`sh`（dash）下无法正常运行。


# web_console.py

基于 Python 内置库的单文件 Web 服务器。无需安装任何第三方依赖。查看脚本执行的日志。每 60s 自动刷新一次日志。

## 工作流程

1. 优先读取本地缓存的 JWT，若有效则直接使用
2. 缓存不存在或已失效时，自动重新登录获取新 JWT
3. 获取所有 dcimcloud 类型且状态为 Active 的主机
4. 在状态异常重启前检查ping, 如果ping正常则不执行重启（主要针对主控异常的“未知”状态）。

# 待完善
日志轮转：随着时间推移，monitor.log 可能会变得非常大。 Linux 系统中配置 logrotate 来自动切割和压缩日志文件，避免日志文件无限膨胀。