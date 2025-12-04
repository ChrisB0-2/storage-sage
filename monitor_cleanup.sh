#!/bin/bash
# StorageSage Real-Time Monitor
# Monitors metrics and file counts in real-time while creating/deleting test files

echo "=== StorageSage Real-Time Monitor ==="
echo "Watching metrics every 2 seconds..."
echo "Press Ctrl+C to stop"
echo ""

# Get initial metrics
INITIAL_METRICS=$(curl -s http://localhost:9090/metrics)
INITIAL_FILES_DELETED=$(echo "$INITIAL_METRICS" | grep "storagesage_files_deleted_total" | grep -v "#" | awk '{print $2}')
INITIAL_BYTES_FREED=$(echo "$INITIAL_METRICS" | grep "storagesage_bytes_freed_total" | grep -v "#" | awk '{print $2}')
INITIAL_ERRORS=$(echo "$INITIAL_METRICS" | grep "storagesage_errors_total" | grep -v "#" | awk '{print $2}')

echo "Initial state:"
echo "  Files Deleted: $INITIAL_FILES_DELETED"
echo "  Bytes Freed: $INITIAL_BYTES_FREED"
echo "  Errors: $INITIAL_ERRORS"
echo ""
echo "Starting monitor..."
echo ""

while true; do
    clear
    echo "=== $(date '+%Y-%m-%d %H:%M:%S') ==="
    echo ""
    
    # Get metrics
    METRICS=$(curl -s http://localhost:9090/metrics)
    
    FILES_DELETED=$(echo "$METRICS" | grep "storagesage_files_deleted_total" | grep -v "#" | awk '{print $2}')
    BYTES_FREED=$(echo "$METRICS" | grep "storagesage_bytes_freed_total" | grep -v "#" | awk '{print $2}')
    ERRORS=$(echo "$METRICS" | grep "storagesage_errors_total" | grep -v "#" | awk '{print $2}')
    
    # Calculate deltas
    FILES_DELTA=$(echo "$FILES_DELETED - $INITIAL_FILES_DELETED" | bc 2>/dev/null || echo "0")
    BYTES_DELTA=$(echo "$BYTES_FREED - $INITIAL_BYTES_FREED" | bc 2>/dev/null || echo "0")
    
    # Format bytes
    BYTES_FREED_MB=$(echo "scale=2; $BYTES_FREED / 1024 / 1024" | bc 2>/dev/null || echo "0")
    BYTES_DELTA_MB=$(echo "scale=2; $BYTES_DELTA / 1024 / 1024" | bc 2>/dev/null || echo "0")
    
    echo "📊 Metrics:"
    echo "  Files Deleted: $FILES_DELETED (since start: +$FILES_DELTA)"
    echo "  Bytes Freed: $BYTES_FREED ($BYTES_FREED_MB MB) (since start: +$BYTES_DELTA_MB MB)"
    echo "  Errors: $ERRORS"
    echo ""
    
    # Check current files in test directory
    if [ -d "/tmp/storage-sage-test-workspace/var/log" ]; then
        FILE_COUNT=$(find /tmp/storage-sage-test-workspace/var/log -type f 2>/dev/null | wc -l)
        DISK_USAGE=$(du -sh /tmp/storage-sage-test-workspace/var/log 2>/dev/null | awk '{print $1}')
        
        echo "📁 Test Directory:"
        echo "  Current files: $FILE_COUNT"
        echo "  Disk usage: $DISK_USAGE"
        echo ""
        
        # Show sample files if any
        if [ "$FILE_COUNT" -gt 0 ]; then
            echo "  Sample files:"
            ls -lh /tmp/storage-sage-test-workspace/var/log | head -5 | tail -3 | awk '{print "    " $0}'
        fi
    else
        echo "⚠️  Test directory not found: /tmp/storage-sage-test-workspace/var/log"
    fi
    
    echo ""
    echo "Press Ctrl+C to stop..."
    
    sleep 2
done


