# DMIT 部署说明

适用场景：

- 本地开发机是 macOS
- 目标机器是 `dmit`（`x86_64` / `linux/amd64`）
- 线上使用 `/root/sub2api-deploy/docker-compose.yml`
- 线上通过本地镜像标签 `sub2api-local:<tag>` 部署

## 当前部署结构

- 目标主机：`ssh dmit`
- 部署目录：`/root/sub2api-deploy`
- `.env` 里的关键镜像变量：
  - `SUB2API_IMAGE=sub2api-local`
  - `SUB2API_VERSION=<当前标签>`
- 主要容器：
  - `sub2api`
  - `sub2api-postgres`
  - `sub2api-redis`
  - `sub2api-caddy`

## 推荐流程

### 1. 确认本地代码与分支

```bash
git status --short --branch
git rev-parse --short HEAD
```

要求：

- 当前分支应为目标分支，例如 `ddh`
- 工作区应干净，避免把未提交改动打进镜像

### 2. 使用 `linux/amd64` 构建镜像 tar

不要直接用默认本机架构，必须显式指定：

```bash
TAG="ddh-$(git rev-parse --short HEAD)-$(date +%Y%m%d)"
TAR="/tmp/sub2api-${TAG}-amd64.tar"

docker buildx build \
  --builder amd64-builder \
  --platform linux/amd64 \
  --build-arg GOPROXY=https://proxy.golang.org,direct \
  --build-arg GOSUMDB=sum.golang.org \
  --build-arg COMMIT="$(git rev-parse --short HEAD)" \
  -t "sub2api-local:${TAG}" \
  --output type=docker,dest="${TAR}" \
  .
```

说明：

- 本地是 macOS，目标是 Linux，所以必须走 `buildx --platform linux/amd64`
- 如果 `goproxy.cn` 抽风，优先改成 `https://proxy.golang.org,direct`

### 3. 直接流式导入到 `dmit`

```bash
ssh dmit 'docker load -i -' < "${TAR}"
```

导入后可确认：

```bash
ssh dmit 'docker image inspect sub2api-local:'"${TAG}"' --format "{{.Architecture}}/{{.Os}}"'
```

期望输出：

```text
amd64/linux
```

### 4. 更新远端部署标签

进入部署目录后，只改 `.env` 中的镜像版本：

```bash
ssh dmit "python3 - <<'PY'
from pathlib import Path
p = Path('/root/sub2api-deploy/.env')
lines = p.read_text().splitlines()
out = []
for line in lines:
    if line.startswith('SUB2API_IMAGE='):
        out.append('SUB2API_IMAGE=sub2api-local')
    elif line.startswith('SUB2API_VERSION='):
        out.append('SUB2API_VERSION=${TAG}')
    else:
        out.append(line)
p.write_text('\n'.join(out) + '\n')
PY"
```

### 5. 只重启 `sub2api`

避免误重建数据库和 Redis，使用 `--no-deps`：

```bash
ssh dmit 'cd /root/sub2api-deploy && docker compose up -d --no-deps sub2api'
```

### 6. 验证

先看容器状态：

```bash
ssh dmit 'cd /root/sub2api-deploy && docker compose ps'
```

再看应用日志：

```bash
ssh dmit 'docker logs --tail=200 sub2api'
```

再做 HTTP 检查：

```bash
curl -I https://api.foreverlin.cn/
```

可选检查：

```bash
ssh dmit 'docker inspect --format "{{.State.Health.Status}}" sub2api'
```

## 回滚

如果新版本异常，直接把 `/root/sub2api-deploy/.env` 的 `SUB2API_VERSION` 改回上一个标签，然后执行：

```bash
ssh dmit 'cd /root/sub2api-deploy && docker compose up -d --no-deps sub2api'
```

## 注意事项

- 不要把 macOS 本机构建产物直接当成 Linux 镜像部署
- 不要把包含 refresh token 的导出 JSON 提交进 Git
- 部署时优先使用 `docker compose up -d --no-deps sub2api`
- 如果只是切换 `sub2api` 镜像，不需要动 `postgres` / `redis` / `caddy`
