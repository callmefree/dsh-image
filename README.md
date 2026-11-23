# dsh-image

DeepSeekRuntime (dsh) 运行镜像的 **GitHub Actions 云构建**仓库。

官方 [deepseek-ai/deepseek-harness releases](https://github.com/deepseek-ai/deepseek-harness/releases) 只发 tag、**不发任何构建产物**，
所以升级只能自己构建。本仓库把构建搬到 Actions：产物推到 GHCR，宿主只 `docker pull`，不再本地编译。

## 触发构建

```bash
# 网页：Actions -> build-dsh-image -> Run workflow -> 填 version（如 0.2.3-alpha.2）
# 或 API：
curl -X POST -H "Authorization: token <PAT>" \
  -H "Accept: application/vnd.github+json" \
  https://api.github.com/repos/callmefree/dsh-image/actions/workflows/build.yml/dispatches \
  -d '{"ref":"main","inputs":{"version":"0.2.3-alpha.2"}}'
```

产物：`ghcr.io/callmefree/dsh:<version>-patched` 与 `:latest`。

## 宿主使用（两种，都无需本地构建）

```bash
docker pull ghcr.io/callmefree/dsh:0.2.3-alpha.2-patched

# 方式 A：直接把运行时从镜像里拷成宿主目录，只改 compose 的挂载指向
mkdir -p /vol2/1000/docker/dsh/workspace/dsh-runtime/alpha2/lib
cid=$(docker create ghcr.io/callmefree/dsh:0.2.3-alpha.2-patched)
docker cp "$cid":/usr/local/lib/node_modules /vol2/1000/docker/dsh/workspace/dsh-runtime/alpha2/lib/
docker rm "$cid"

# 方式 B：整镜像替换（compose 里删掉 dsh-runtime 挂载，改 image:）
```

方式 A 不动 compose 结构、可秒回滚（把挂载指回 `rc3`），适合本次升级。

## 版本事实

- `0.2.3-alpha.2` 的 `engines` 是 `node ^24.22.3 || >=26.13.1`，故基础镜像钉 `node:24.22.3-bookworm-slim`。
- 我们线上 rc.3 的运行时与 npm 原包 **26/26 文件零差异**（无源码补丁），因此镜像只需“OS 依赖 + 指定版本 npm 包”。
