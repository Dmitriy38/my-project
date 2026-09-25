#!/bin/bash
LOG=/root/zabbix-scripts/zabbix-auto-fix.log
echo "=== $(date) ===" >> $LOG
python3 /root/zabbix-scripts/fix_interface_ip.py >> $LOG 2>&1
python3 /root/zabbix-scripts/rename_ip_hosts.py >> $LOG 2>&1
cat /root/zabbix-scripts/zabbix-auto-fix.log


