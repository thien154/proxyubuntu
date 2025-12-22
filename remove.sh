#!/bin/bash
set -e
set -x  # bật debug để thấy lệnh chạy

echo "=== Dừng 3proxy nếu đang chạy ==="
sudo systemctl stop 3proxy || true
sudo systemctl disable 3proxy || true
sudo systemctl daemon-reload

echo "=== Xóa systemd service ==="
sudo rm -f /etc/systemd/system/3proxy.service
sudo systemctl daemon-reload

echo "=== Xóa binary 3proxy ==="
sudo rm -f /usr/local/bin/3proxy

echo "=== Xóa folder config và log ==="
sudo rm -rf /etc/3proxy
sudo rm -rf /var/log/3proxy

echo "=== Xóa user proxy3 ==="
sudo deluser --system proxy3 || true
sudo delgroup proxy3 || true

echo "=== Xóa file temp nếu có ==="
rm -rf ~/3proxy-0.9.5*
rm -rf /tmp/3proxy-0.9.5*

echo "=== Đã xóa hoàn toàn 3proxy cũ ==="
