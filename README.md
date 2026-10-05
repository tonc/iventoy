# iVentoy Docker 版

将 [ventoy/PXE](https://github.com/ventoy/PXE)（iVentoy）的 Linux 版打包成 Docker 镜像，并通过 GitHub Actions 自动跟踪
`https://api.github.com/repos/ventoy/PXE/releases/latest`，一旦有新版本就自动构建并推送镜像。

> iVentoy 与 Ventoy 是两个不同的软件：iVentoy 用于网络（PXE/HTTPBoot）批量安装系统，本镜像只使用其开源部分（Linux 包）。

## 🚀 特性

- ✅ **自动跟踪上游版本**：每 6 小时检查 `ventoy/PXE` 最新 release，有更新即自动构建
- ✅ **多阶段构建**：下载/解压在一个临时阶段完成，运行镜像只保留 iVentoy 本体，不含 curl、jq、压缩包等中间产物
- ✅ **多架构**：`linux/amd64`（free 版）、`linux/arm64`（trial 版）
- ✅ **开箱即用**：内置 iVentoy 全部依赖库，Web 管理界面 26000 端口
- ✅ **国内源优化**：apt 使用中科大源，构建时可用 `GH_PROXY` 加速 GitHub 下载
- ✅ **数据持久化**：ISO、配置、脚本、日志均通过挂载卷保存

## 📦 镜像信息

- **镜像名称**: `xkand/iventoy`
- **标签**: `latest`, `{version}`
- **基础镜像**: Ubuntu 22.04
- **当前 iVentoy 版本**: 见 [version](./version) 文件

## 🛠️ 快速开始

### 使用 Docker Compose（推荐）

```bash
# 把 ISO 文件放进 ./iso 目录
mkdir -p iso data user log

docker compose up -d

# 查看日志
docker compose logs -f
```

然后浏览器打开 `http://<服务器IP>:26000`，选择服务器 IP、设置 IP 地址池，点击绿色按钮启动 PXE 服务。

### 使用 Docker 命令

```bash
docker run -d \
  --name iventoy \
  --network host \
  --cap-add SYS_ADMIN --cap-add NET_ADMIN --cap-add NET_RAW --cap-add NET_BIND_SERVICE \
  -e AUTO_RUN=0 \
  -v $PWD/iso:/opt/iventoy/iso \
  -v $PWD/data:/opt/iventoy/data \
  -v $PWD/user:/opt/iventoy/user \
  -v $PWD/log:/opt/iventoy/log \
  xkand/iventoy:latest
```

> ⚠️ **必须使用 host 网络**：PXE 依赖 DHCP/TFTP 广播，bridge 模式下客户端无法获取 IP。

### 手动构建

```bash
# 自动拉取最新版
docker build -t xkand/iventoy:latest .

# 指定版本
docker build --build-arg VERSION=1.0.44 -t xkand/iventoy:1.0.44 .

# GitHub 下载慢时加速
docker build --build-arg GH_PROXY=https://ghfast.top/ -t xkand/iventoy:latest .
```

## 🔧 配置说明

### 环境变量

| 变量名 | 默认值 | 说明 |
|--------|--------|------|
| `AUTO_RUN` | `0` | 设为 `1` 时自动按上次配置启动 PXE 服务（需先在页面上配置并启动过一次） |
| `TZ` | `Asia/Shanghai` | 时区 |
| `IVENTOY_HOME` | `/opt/iventoy` | iVentoy 安装目录 |

### 构建参数

| 参数 | 默认值 | 说明 |
|--------|--------|------|
| `VERSION` | `latest` | iVentoy 版本（不含 `v` 前缀） |
| `GH_PROXY` | 空 | GitHub 下载加速前缀，如 `https://ghfast.top/` |

### 数据卷

| 容器路径 | 说明 |
|----------|------|
| `/opt/iventoy/iso` | 放 ISO 文件，可建子目录分类 |
| `/opt/iventoy/data` | 配置 / License，首次为空时自动用内置默认文件初始化 |
| `/opt/iventoy/user` | 自动安装脚本、注入文件、第三方软件 |
| `/opt/iventoy/log` | 日志 |

### 端口

| 端口 | 协议 | 说明 |
|------|------|------|
| 67 / 68 | UDP | DHCP |
| 69 | UDP | TFTP |
| 4011 | UDP | DHCP Proxy（仅 Proxy 模式） |
| 26000 | TCP | Web 管理界面 |
| 16000 | TCP | PXE 服务 HTTP |
| 10809 | TCP | NBD |
| 3260 | TCP | iSCSI |
| 12049 | TCP | NFS |
| 10445 | TCP | SMB |

host 网络下无需映射；防火墙需放行以上端口。

## 📁 项目结构

```
.
├── Dockerfile                  # Docker 镜像构建文件（自动下载 iVentoy）
├── docker-compose.yml          # Docker Compose 配置
├── start_iventoy.sh            # 容器启动脚本
├── version                     # 已构建的 iVentoy 版本记录
└── .github/workflows/
    └── iventoy.yml             # GitHub Actions 自动构建工作流
```

## 🔄 自动更新机制

1. **版本检查**：每 6 小时从 `https://api.github.com/repos/ventoy/PXE/releases/latest` 获取最新 `tag_name`
2. **版本比较**：与 `version` 文件对比
3. **自动构建**：有新版本时构建 amd64/arm64 镜像并推送
4. **版本更新**：更新 `version` 文件并在仓库创建通知 Issue

### 手动检查版本

```bash
cat version

curl -s https://api.github.com/repos/ventoy/PXE/releases/latest | jq -r .tag_name
```

## 🐛 故障排除

- **日志报 `mount directory failed, errno:1` / 容器启动即退出**：缺少 `SYS_ADMIN` 权限（iVentoy 需要挂载 ISO 读取内容），请加 `--cap-add SYS_ADMIN` 或 `--privileged`
- **客户端拿不到 IP**：确认使用 `network_mode: host`，且局域网内没有其他 DHCP 服务冲突
- **Web 页面打不开**：确认 26000 端口未被占用，查看 `docker logs iventoy`
- **ISO 不显示**：确认 ISO 已放入挂载的 `iso` 目录，路径与文件名不要包含中文或空格
- **arm64 版本说明**：上游 arm64 包为 trial 版，功能与 free 版一致但有试用限制

## 📄 许可证

- 本项目（Dockerfile/脚本）：MIT
- iVentoy 本体：见容器内 `/opt/iventoy/doc` 下的 LICENSE / EULA

## 🔗 相关链接

- [iVentoy 官网](https://www.iventoy.com)
- [iVentoy 使用文档](https://www.iventoy.com/en/doc_start.html)
- [ventoy/PXE Releases](https://github.com/ventoy/PXE/releases)
- [Docker Hub 镜像](https://hub.docker.com/r/xkand/iventoy)
