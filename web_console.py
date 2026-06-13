#!/usr/bin/env python3
import http.server
import socketserver
import json
import os
from urllib.parse import urlparse

PORT = 8080
LOG_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "monitor.jsonl")

HTML_PAGE = """<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>核云IDC 自动化运维控制台</title>
    <style>
        body { font-family: 'Segoe UI', sans-serif; background: #f4f6f9; margin: 0; padding: 20px; color: #333; }
        .container { max-width: 1000px; margin: 0 auto; background: white; border-radius: 8px; box-shadow: 0 2px 10px rgba(0,0,0,0.05); padding: 20px; }
        h1 { font-size: 24px; border-bottom: 2px solid #eee; padding-bottom: 10px; display: flex; justify-content: space-between; align-items: center;}
        .badge { font-size: 12px; padding: 4px 8px; border-radius: 4px; background: #e8f5e9; color: #2e7d32; }
        table { width: 100%; border-collapse: collapse; margin-top: 15px; font-size: 14px; }
        th, td { text-align: left; padding: 12px; border-bottom: 1px solid #eee; }
        th { background: #fafafa; font-weight: 600; }
        .level-INFO { color: #1976d2; } .level-WARN { color: #f57c00; font-weight: bold; } 
        .level-ACTION { color: #d32f2f; font-weight: bold; } .level-ERROR { color: #b71c1c; font-weight: bold; }
        .empty-msg { text-align: center; padding: 40px; color: #999; }
    </style>
</head>
<body>
<div class="container">
    <h1>核云IDC 运维控制台 <span class="badge" id="refresh-status">每 60s 自动刷新</span></h1>
    <table>
        <thead><tr><th style="width:180px;">时间</th><th style="width:80px;">级别</th><th>消息内容</th><th>主机 ID</th><th>IP 地址</th></tr></thead>
        <tbody id="log-body"><tr><td colspan="5" class="empty-msg">正在加载数据...</td></tr></tbody>
    </table>
</div>
<script>
    async function fetchLogs() {
        try {
            const res = await fetch('/api/logs');
            const logs = await res.json();
            const tbody = document.getElementById('log-body');
            if (!logs.length) { tbody.innerHTML = '<tr><td colspan="5" class="empty-msg">暂无运行记录</td></tr>'; return; }
            
            tbody.innerHTML = logs.reverse().map(log => `
                <tr>
                    <td>${new Date(log.time).toLocaleString('zh-CN')}</td>
                    <td class="level-${log.level}">${log.level}</td>
                    <td>${log.msg}</td>
                    <td>${log.host_id || '-'}</td>
                    <td><code>${log.ip || '-'}</code></td>
                </tr>`).join('');
        } catch (e) { console.error(e); }
    }
    fetchLogs();
    setInterval(fetchLogs, 60000); // 每60秒刷新一次
</script>
</body>
</html>"""

class Handler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        path = urlparse(self.path).path
        if path == "/":
            self.send_response(200)
            self.send_header("Content-type", "text/html; charset=utf-8")
            self.end_headers()
            self.wfile.write(HTML_PAGE.encode('utf-8'))
        elif path == "/api/logs":
            logs = []
            if os.path.exists(LOG_FILE):
                with open(LOG_FILE, 'r', encoding='utf-8') as f:
                    for line in f:
                        try: logs.append(json.loads(line.strip()))
                        except: pass
            # 仅返回最后 100 条日志，防止浏览器卡顿
            self.send_response(200)
            self.send_header("Content-type", "application/json; charset=utf-8")
            self.end_headers()
            self.wfile.write(json.dumps(logs[-100:]).encode('utf-8'))
        else:
            self.send_error(404)

if __name__ == "__main__":
    with socketserver.TCPServer(("", PORT), Handler) as httpd:
        print(f"[+] Web 控制台已启动: http://localhost:{PORT}")
        print("[+] 按 Ctrl+C 停止服务")
        httpd.serve_forever()