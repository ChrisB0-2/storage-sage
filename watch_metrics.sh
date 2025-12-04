#!/bin/bash
# StorageSage Metrics Watcher
# Simple watch command for metrics endpoint

watch -n 1 'echo "=== $(date) ===" && curl -s http://localhost:9090/metrics | grep -E "storagesage_files_deleted_total|storagesage_bytes_freed_total|storagesage_errors_total" | grep -v "#" && echo "" && echo "Files in test dir: $(find /tmp/storage-sage-test-workspace/var/log -type f 2>/dev/null | wc -l)" && echo "Disk usage: $(du -sh /tmp/storage-sage-test-workspace/var/log 2>/dev/null | awk '\''{print $1}'\'')"'


