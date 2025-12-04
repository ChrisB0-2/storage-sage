#!/bin/bash

echo "🔍 CABE REALITY CHECK — StorageSage System Scan $(date)"
echo "----------------------------------------------"

# 1️⃣ Verify Go Binary Build
echo "🧱 Checking binary..."
if [ -f ~/projects/storage-sage/build/storage-sage ]; then
  file ~/projects/storage-sage/build/storage-sage
  ~/projects/storage-sage/build/storage-sage --version 2>/dev/null || echo "ℹ️ Binary found but version not printed."
else
  echo "❌ storage-sage binary missing in build/ directory."
fi

# 2️⃣ Check Config File
echo "⚙️ Checking /etc/storage-sage/config.yaml..."
if [ -f /etc/storage-sage/config.yaml ]; then
  ls -l /etc/storage-sage/config.yaml
  head -n 15 /etc/storage-sage/config.yaml
else
  echo "❌ Config file missing at /etc/storage-sage/config.yaml"
fi

# 3️⃣ Check systemd Service
echo "🧠 Checking systemctl service..."
systemctl status storage-sage --no-pager -l || echo "❌ Service not active."

# 4️⃣ Confirm Prometheus Metrics Endpoint
echo "📊 Checking Prometheus metrics endpoint..."
curl -s localhost:9090/metrics | grep cleanup_ | head -n 10 || echo "❌ No metrics found at :9090."

# 5️⃣ Confirm Grafana is running
echo "📈 Checking Grafana service..."
systemctl status grafana-server --no-pager | grep Active || echo "❌ Grafana not active."

# 6️⃣ Disk + CPU Snapshot (safety validation)
echo "💾 Disk & CPU Snapshot..."
df -h | grep data || echo "⚠️ /data mount not found."
top -b -n1 | head -n 10

# 7️⃣ Log Evidence
echo "🧾 Recent StorageSage Logs..."
sudo journalctl -u storage-sage -n 20 --no-pager || echo "❌ No recent logs found."

# 8️⃣ CABE Final Summary
echo "----------------------------------------------"
echo "✅ CABE Verification Completed — $(date)"
echo "Check above for missing components or inactive services."

