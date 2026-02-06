## 專案說明
本專案為一個簡單的 Node.js API 服務，啟動後監聽於 `3000` port。  
本次實作目標為建立一個**符合 production 環境需求**的 Docker image，包含：

- multi-stage build
- non-root 執行
- production-only dependencies
- cache-friendly layer 設計
- 正確處理 SIGTERM
- 真正有效的 healthcheck
- 基本安全與最佳實務

---

## A. Dockerfile 基本結構檢核

- ✅ 未使用 `node:latest`（使用 `node:20-alpine`）
- ✅ 使用 multi-stage build（deps stage / runner stage）
- ✅ final image 中不包含 npm / build tools
- ✅ Dockerfile 無多餘、未使用的 layer

### Dockerfile 節錄

**deps stage**
```dockerfile
FROM node:20-alpine AS deps
WORKDIR /app
COPY app/package.json app/package-lock.json ./
ENV NODE_ENV=production
RUN npm ci --omit=dev
```

**runner stage**
```dockerfile
FROM node:20-alpine AS runner
WORKDIR /app
ENV NODE_ENV=production
```

**Image size 驗證**
```
docker images | findstr candidate-api
candidate-api:challenge   ed52d7caf2e1        202MB         49.2MB
```
## B. 使用者與權限（Non-root）檢核 

✅ container 內程式非 root 執行

✅ 使用專用非 root 使用者 nodeapp

✅ 應用程式相關檔案權限正確

✅ container 啟動時不會因權限問題 crash

### Dockerfile 節錄

```dockerfile
RUN addgroup -S nodeapp && adduser -S nodeapp -G nodeapp
RUN chown -R nodeapp:nodeapp /app \
  && chmod -R go-w /app
USER nodeapp
```

**驗證**
```bash
docker exec -it candidate-api sh -lc "whoami && id"
```
```text
nodeapp
uid=100(nodeapp) gid=101(nodeapp) groups=101(nodeapp)
```

## C. Production dependencies 檢核

✅ final image 僅包含 production dependencies

✅ devDependencies 未被打包進 final image

✅ 清楚知道是哪一行確保此行為

### Dockerfile 節錄

```dockerfile
RUN npm ci --omit=dev
```

### 策略說明

1.在 deps stage 使用 npm ci --omit=dev，devDependencies 從一開始就不會被安裝

2.final stage 僅 COPY 該 node_modules

3.final image 中移除 npm / npx，避免 runtime 再安裝套件

## D. Layer Cache 設計檢核

✅ 修改 src/index.js 後重新 build，不會重跑 npm install

✅ 清楚區分依賴層與程式碼層

### Dockerfile 節錄

```dockerfile
COPY app/package.json app/package-lock.json ./
RUN npm ci --omit=dev
COPY app/src ./src
```

### Cache 設計說明

package.json / package-lock.json 變動頻率低，獨立成 dependency layer

src/ 變動頻率高，放在後面

修改程式碼不會影響 npm install cache

## E. 啟動與停止行為（Signal）檢核

✅ Node.js 為 container 中的 PID 1

✅ 使用 exec form 的 CMD

✅ docker stop 時可即刻停止

✅ 未被強制 SIGKILL

### Dockerfile 節錄

```dockerfile

CMD ["node", "src/index.js"]

```
### 行為說明

使用 exec form，避免 shell 攔截 SIGTERM，確保 docker stop 時
SIGTERM 能直接送達 Node.js process，container 可在合理時間內結束。

## F. Healthcheck 檢核

✅ Dockerfile 有設定 HEALTHCHECK

✅ healthcheck 真的檢查 HTTP 服務狀態

✅ healthcheck 失敗時會顯示 unhealthy

✅ 清楚設定 interval / timeout / retries

### Dockerfile 節錄

```dockerfile
HEALTHCHECK --interval=10s --timeout=3s --start-period=10s --retries=3 \
  CMD node -e "const http=require('http');const req=http.get({host:'127.0.0.1',port:3000,path:'/'},res=>process.exit(res.statusCode>=200&&res.statusCode<500?0:1));req.on('error',()=>process.exit(1));"
  ```

**驗證**

```bash
docker inspect candidate-api --format "{{json .Config.Healthcheck}}"
```
```text
{"Test":["CMD-SHELL","node -e \"const http=require('http');const req=http.get({host:'127.0.0.1',port:3000,path:'/'},res=>process.exit(res.statusCode>=200&&res.statusCode<500?0:1));req.on('error',()=>process.exit(1));req.setTimeout(2000,()=>{req.destroy();process.exit(1);});\""],"Interval":10000000000,"Timeout":3000000000,"StartPeriod":10000000000,"Retries":3}
```
```bash
docker inspect candidate-api --format "{{.State.Health.Status}}"
```
```text
healthy
```
## G. 安全與最佳實務檢核

✅ 撰寫並使用 .dockerignore

✅ 設定 NODE_ENV=production

✅ final image 僅保留執行所需檔案

✅ 移除 npm / npx 等不必要工具

✅ 限制檔案權限（避免 world-writable）

✅ 僅暴露必要 port（3000）

✅ 未安裝多餘系統套件

### .dockerignore 節錄

```.dockerignore
**/node_modules
.git
.vscode
.env
*.md
Dockerfile
docker-compose*.yml
```
## H. 驗收指令執行確認

以下指令皆已實際執行並確認結果正確：
```bash
docker build -t candidate-api:challenge .
```
```text
PS C:\Users\Emily\Desktop\docker apply> docker build -t candidate-api:challenge .                             
[+] Building 2.6s (16/16) FINISHED                                                       docker:desktop-linux
 => [internal] load build definition from Dockerfile                                                     0.0s
 => => transferring dockerfile: 1.89kB                                                                   0.0s 
 => [internal] load metadata for docker.io/library/node:20-alpine                                        2.1s 
 => [internal] load .dockerignore                                                                        0.0s
 => => transferring context: 266B                                                                        0.0s 
 => [deps 1/4] FROM docker.io/library/node:20-alpine@sha256:09e2b3d9726018aecf269bd35325f46bf75046a643a  0.0s 
 => => resolve docker.io/library/node:20-alpine@sha256:09e2b3d9726018aecf269bd35325f46bf75046a643a66d28  0.0s 
 => [internal] load build context                                                                        0.0s 
 => => transferring context: 166B                                                                        0.0s 
 => CACHED [deps 2/4] WORKDIR /app                                                                       0.0s
 => CACHED [runner 3/9] RUN addgroup -S nodeapp && adduser -S nodeapp -G nodeapp                         0.0s 
 => CACHED [deps 3/4] COPY app/package.json app/package-lock.json ./                                     0.0s 
 => CACHED [deps 4/4] RUN npm ci --omit=dev                                                              0.0s 
 => CACHED [runner 4/9] COPY --from=deps /app/node_modules ./node_modules                                0.0s 
 => CACHED [runner 5/9] COPY app/src ./src                                                               0.0s 
 => CACHED [runner 6/9] COPY app/package.json ./package.json                                             0.0s 
 => CACHED [runner 7/9] RUN chown -R nodeapp:nodeapp /app   && chmod -R go-w /app                        0.0s 
 => CACHED [runner 8/9] RUN rm -rf /usr/local/lib/node_modules/npm   && rm -f /usr/local/bin/npm /usr/l  0.0s 
 => CACHED [runner 9/9] RUN rm -rf   /usr/local/lib/node_modules/npm   /usr/local/lib/node_modules/core  0.0s 
 => exporting to image                                                                                   0.2s 
 => => exporting layers                                                                                  0.0s 
 => => exporting manifest sha256:e4923586f89cb978c6deff5da4ac47c58b1a861bd9ac4e188de5fbfca635ea0c        0.0s 
 => => exporting attestation manifest sha256:4c427550dc5c66111eb2d56df7bdd8fa931ee344cac93c37941f278777  0.0s
                   0.0s
 => => unpacking to docker.io/library/candidate-api:challenge                                            0.0s
                   0.0s
 => => unpacking to docker.io/library/candidate-api:challenge                                            0.0s

```
```bash
docker run --rm -p 8080:3000 --name candidate-api candidate-api:challenge
```
```text
Server listening on port 3000
```
```bash
curl -i http://localhost:8080/
```
```text
HTTP/1.1 200 OK
X-Powered-By: Express
Content-Type: text/html; charset=utf-8
Content-Length: 3
ETag: W/"3-CftlTBfMBbEe9TvTWqcB9tVQ6OE"
Date: Fri, 06 Feb 2026 06:14:23 GMT
Connection: keep-alive
Keep-Alive: timeout=5

OK
```
```bash
docker exec -it candidate-api sh -lc "whoami && id"
```
```text
nodeapp
uid=100(nodeapp) gid=101(nodeapp) groups=101(nodeapp)
```
```bash
docker inspect candidate-api | grep -i -A5 health
```
```text
            "Health": {
                "Status": "healthy",
                "FailingStreak": 0,
                "Log": [
                    {
                        "Start": "2026-02-06T06:13:50.467246916Z",
                        "End": "2026-02-06T06:13:50.597819789Z",
--
            "Healthcheck": {
                "Test": [
                    "CMD-SHELL",
                    "node -e \"const http=require('http');const req=http.get({host:'127.0.0.1',port:3000,path:'/'},res=\u003eprocess.exit(res.statusCode\u003e=200\u0026\u0026res.statusCode\u003c500?0:1));req.on('error',()=\u003eprocess.exit(1));req.setTimeout(2000,()=\u003e{req.destroy();process.exit(1);});\""
                ],
                "Interval": 10000000000,
```
```bash
6.docker stop candidate-api
```
```text
candidate-api
```
