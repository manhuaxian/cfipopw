# cfipopw —— Cloudflare 优选 IP 自动更新（飞牛 NAS 自用版）

用 [XIU2/CloudflareSpeedTest](https://github.com/XIU2/CloudflareSpeedTest) 测出对**你当前网络**最快的 Cloudflare 边缘 IP，
再通过 Cloudflare API 自动把这批 IP 更新到指定域名的 A 记录上（DNS-only / 灰云）。

> 本项目是在 [lee1080/CloudflareSpeedTestDDNS](https://github.com/lee1080/CloudflareSpeedTestDDNS) 基础上做了较多修改的自用版本，
> 测速内核来自 [XIU2/CloudflareSpeedTest](https://github.com/XIU2/CloudflareSpeedTest)。感谢两位作者。

---

## 目录结构

| 文件 | 说明 |
| --- | --- |
| `cdnip.sh` | 主控脚本：调用 cfst 测速 → 过滤 → 更新 DNS |
| `cdnac.sh` | 辅助脚本：从 IPDB 拉取 IP 库（cfv4 / bestcf），并做优选 IP 的地区识别 |
| `run_every5d.sh` | cron 包装脚本，实现"每 5 天跑一次" |
| `cfst` | 测速二进制（需自行下载，见下） |
| `ip.txt` | IP 段数据文件（由 `cdnac.sh` 自动生成，也可自己维护） |
| `proxy_ip.txt` | 反代 IP 存档（不参与优选） |
| `result.csv` | 测速结果（脚本运行时生成） |
| `informlog` | 运行日志（脚本运行时生成） |

---

## 部署

```bash
# 1) 下载测速内核（按机器架构选 aarch64 / amd64）
mkdir -p /root/cfipopw && cd /root/cfipopw
curl -L -o cfst.tar.gz https://github.com/XIU2/CloudflareSpeedTest/releases/latest/download/cfst_linux_arm64.tar.gz
tar -xzf cfst.tar.gz && rm -f cfst.tar.gz
chmod +x cfst

# 2) 放入本仓库的 cdnip.sh / cdnac.sh / run_every5d.sh

# 3) 编辑 cdnip.sh 顶部的配置（见下）

# 4) 手动跑一次
bash cdnip.sh

# 5) 配 cron（每 5 天 03:19 一次）
crontab -e
# 19 3 * * * /bin/sh /root/cfipopw/run_every5d.sh
```

依赖：`curl`、`jq`、`python3`（可选）、`timeout`（coreutils）。

---

## 必填配置（`cdnip.sh` 顶部）

| 变量 | 说明 |
| --- | --- |
| `x_email` | Cloudflare 账号邮箱 |
| `zone_id` | 目标域名所在的 Zone ID |
| `api_token` | Cloudflare **API Token**（见下方权限） |
| `domain` | 主域名，如 `example.com` |
| `subdomain` | 子域名，如 `cf`（最终更新 `cf.example.com`） |
| `CFST_URL_R` | 下载测速地址，**必须**是带 `Content-Length` 的静态文件 |

### API Token 权限

建议**不要**用 Global API Key，改用最小权限 Token：

- Zone → Zone → Read
- Zone → DNS → Read
- Zone → DNS → Write
- 资源范围限定为**这一个 zone**

脚本对 Cloudflare 的调用只有：读 zone 信息、列出/新建/删除/修改 DNS 记录，上面三个权限即可全覆盖。

---

## 当前参数

| 参数 | 值 | 含义 |
| --- | --- | --- |
| `point` | 443 | 测速端口 |
| `CFST_N` | 26 | 延迟测速并发线程 |
| `CFST_T` | 4 | 单个 IP 延迟测速次数 |
| `CFST_DN` | 60 | 下载测速 IP 数量 |
| `CFST_TL` | 200 | 平均延迟上限（ms） |
| `CFST_TLL` | 0 | 平均延迟下限（ms） |
| `CFST_SL` | 0 | 下载速度下限（用脚本内 awk 过滤代替，见下） |
| `CFST_URL_R` | 自建静态文件 | 下载测速地址 |

### 几个关键取舍（踩过的坑）

1. **不要用 `-sl`（下载速度下限）**。cfst 的 `-sl` 在"凑不够 `-dn` 数量"时会**一直测速不退出**，实测跑 16 分钟仍在继续，还会把测速站打出 403。
   这里改成 `CFST_SL=0` + 脚本内 `awk -F ',' 'NR==1{print;next} $6+0>=5'` 过滤结果，效果等价但请求数可控。
2. **测速地址必须有 `Content-Length`**。`speed.cloudflare.com/__down` 是 chunked 响应且 HEAD 返回 403，cfst 测出来恒为 `0.00 MB/s`。
   最稳的做法是自建：在服务器上放一个静态文件（如 200MB），用 nginx 提供，前面挂 Cloudflare 橙云代理即可（CF 会缓存，源站流量极小）。
3. **过滤后无结果时跳过 DNS 更新**，避免把已有解析清空。
4. **结果截断要保留表头**，否则会少发布一个 IP。

---

## cfst 行为备忘

- 默认**对每个 /24 网段随机抽 1 个 IP**（加 `-allip` 才是全量，1.5M 个，别开）。所以单次测速数量固定（CF 全部 IPv4 约 5966 个），但**具体 IP 每次运行都重新随机**。
- `-tl` / `-tll` / `-tlr` 在**下载测速之前**过滤，只有落在区间内的 IP 才会进入下载队列。
- `-cfcolo`（按机房筛，如 `HKG,NRT,LAX`）**只在 HTTPing 模式可用**；TCPing 模式拿不到机房信息。HTTPing 会把每次延迟探测变成一次 HTTP 请求，代价大。
- CF 的 IP 是 anycast，**IP 本身不归属某个国家**，落到哪个机房取决于你的运营商路由。

---

## 定时任务

```cron
19 3 * * * /bin/sh /root/cfipopw/run_every5d.sh
```

`run_every5d.sh` 用 epoch 天数取模来判断是否该跑：

```sh
[ $(( $(date +%s) / 86400 % 5 )) -eq 0 ] || exit 0
```

比 cron 的 `*/5`（月初会跳变成只隔 1 天）更均匀。

---

## 相关说明

- 优选出来的 IP 建议配一个**独立子域名**（本项目里是 `subdomain` 指定的那个），并保持 **DNS-only（灰云）**。
  灰云 + 指向 CF 自己的 IP，直接用浏览器打开会报 **Error 1000（DNS points to prohibited IP）** —— 这是正常的，它的用途是"给客户端取 IP"，不是拿来访问的。
- 如果你要让一个**橙云域名**也能走优选 IP：把该域名改成**灰云 CNAME 指向优选域名**，并给它加一条 **Worker 路由**（路由会在边缘抢先接管，不走源站，因此不会报 1000）。

---

## 免责声明

本脚本会向 Cloudflare 的 IP 段发起大量连接与下载，请自行评估你的网络环境与运营商策略。
仅供学习研究使用。
