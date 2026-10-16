#!/bin/sh
# 每 5 天执行一次优选（用 epoch 天数取模，避免 cron 里 */5 在月初跳变）
# crontab: 19 3 * * * /bin/sh /root/cfipopw/run_every5d.sh
[ $(( $(date +%s) / 86400 % 5 )) -eq 0 ] || exit 0
cd /root/cfipopw || exit 1
exec bash cdnip.sh
