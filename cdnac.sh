#!/bin/bash
# IP库更新 + 优选结果地区识别
# 2026-10-16 重写（原混淆版备份为 cdnac.sh.bak.*）
# 数据源：IPDB (github.com/ymyuuu/IPDB) —— 已失效的 zip.baipiao.eu.org / cf.yg-kkk.gq 的继任者
export LANG=en_US.UTF-8
cd /root/cfipopw || exit 1

IPDB="https://ipdb.api.030101.xyz/"

fetch() {   # $1=url  $2=outfile  最多重试 3 次
    local i
    for i in 1 2 3; do
        if curl -sm30 -A "Mozilla/5.0" "$1" -o "$2" && [ -s "$2" ]; then
            return 0
        fi
        sleep 3
    done
    return 1
}

# ========== 收尾阶段（informlog 已存在）：对优选结果做地区识别 ==========
if [ -f /root/cfipopw/informlog ]; then
    echo
    echo "请稍等，对优选IP进行地区识别，最多显示前 10 个"
    rm -f cdnIP.csv b.csv a.csv
    awk -F ',' 'NR>1 && NR<=11 {print $1}' result.csv > a.csv
    : > b.csv
    while IFS= read -r ip; do
        [ -z "$ip" ] && continue
        cc=$(curl -sm6 "http://ip-api.com/json/${ip}?fields=countryCode" 2>/dev/null \
             | sed -n 's/.*"countryCode":"\([A-Za-z]*\)".*/\1/p')
        [ -z "$cc" ] && cc="??"
        echo "IP地址 $ip 的地区是: $cc" | tee -a b.csv
        sleep 1
    done < a.csv
    { echo; echo "优选IP--国家地区识别"; cat b.csv; } >> informlog
    echo
    exit 0
fi

# ========== 启动阶段：更新IP库 ip.txt ==========
echo "正在更新IP库（数据源：IPDB）……"

# 1) CF 官方 IP 段（基本不变；优先取 IPDB，取不到则用内置官方列表）
fetch "${IPDB}?type=cfv4" .ipdb_cfv4
if [ "$(grep -c -E '^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$' .ipdb_cfv4 2>/dev/null)" -ge 3 ]; then
    grep -E '^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$' .ipdb_cfv4 > ip.txt
    echo "CF 官方 IP 段：来自 IPDB"
else
    cat > ip.txt <<'EOF'
173.245.48.0/20
103.21.244.0/22
103.22.200.0/22
103.31.4.0/22
141.101.64.0/18
108.162.192.0/18
190.93.240.0/20
188.114.96.0/20
197.234.240.0/22
198.41.128.0/17
162.158.0.0/15
104.16.0.0/13
104.24.0.0/14
172.64.0.0/13
131.0.72.0/22
EOF
    echo "CF 官方 IP 段：使用内置列表"
fi

# 2) 追加 IPDB 优选 CF 官方 IP
if fetch "${IPDB}?type=bestcf" .ipdb_bestcf; then
    grep -Eo '^([0-9]{1,3}\.){3}[0-9]{1,3}' .ipdb_bestcf >> ip.txt
fi

sort -u ip.txt -o ip.txt
echo "IP库已更新：ip.txt 共 $(grep -c . ip.txt) 行（含 CF 段 $(grep -c '/' ip.txt) 行）"

# 3) 反代IP库：单独存档备查（本机当前不可用，不参与优选，避免拉低结果）
rm -f .ipdb_bestproxy .ipdb_proxy
fetch "${IPDB}?type=bestproxy" .ipdb_bestproxy
fetch "${IPDB}?type=proxy"     .ipdb_proxy
cat .ipdb_bestproxy .ipdb_proxy 2>/dev/null \
    | tr -d '\r' | grep -Eo '^([0-9]{1,3}\.){3}[0-9]{1,3}' | sort -u > proxy_ip.txt
echo "反代IP库已存档：proxy_ip.txt 共 $(grep -c . proxy_ip.txt) 条（暂不参与优选）"
