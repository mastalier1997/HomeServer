#!/bin/bash

# Get the directory where the script is located
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATUS_FILE="$REPO_ROOT/server_status.md"

# Gathering system information
TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")
RAM_USAGE=$(free -h | grep Mem | awk '{print $3 " / " $2}')
DISK_USAGE=$(df -h / | tail -1 | awk '{print $3 " / " $2}')
UPTIME=$(uptime -p)
CPU_LOAD=$(top -bn1 | grep "Cpu(s)" | awk '{print $2 + $4}')%

# Create the status file content
echo "### 📊 Live Server Status" > "$STATUS_FILE"
echo "Last update: \`$TIMESTAMP\`" >> "$STATUS_FILE"
echo "" >> "$STATUS_FILE"
echo "| Metric | Value |" >> "$STATUS_FILE"
echo "| :--- | :--- |" >> "$STATUS_FILE"
echo "| **Status** | 🟢 Online |" >> "$STATUS_FILE"
echo "| **CPU Load** | $CPU_LOAD |" >> "$STATUS_FILE"
echo "| **RAM Usage** | $RAM_USAGE |" >> "$STATUS_FILE"
echo "| **Disk Usage** | $DISK_USAGE |" >> "$STATUS_FILE"
echo "| **Uptime** | $UPTIME |" >> "$STATUS_FILE"

# Git operations
cd "$REPO_ROOT"
git add "$STATUS_FILE"
git commit -m "chore: automated status update $TIMESTAMP"
git push
