# ---- deps stage: install ONLY production deps (cache friendly) ----
FROM node:20-alpine AS deps
WORKDIR /app

# cache-friendly: only changes when deps change
COPY app/package.json app/package-lock.json ./
# production-only dependencies
ENV NODE_ENV=production
RUN npm ci --omit=dev

# ---- runner stage: production runtime ----
FROM node:20-alpine AS runner
WORKDIR /app

# Best practice: set production env
ENV NODE_ENV=production

# Create non-root user
RUN addgroup -S nodeapp && adduser -S nodeapp -G nodeapp

# Copy prod node_modules first (smaller diff surface)
COPY --from=deps /app/node_modules ./node_modules

# Copy app source (this is the layer you'll change most often)
COPY app/src ./src
COPY app/package.json ./package.json

# Ensure ownership & tighten permissions
RUN chown -R nodeapp:nodeapp /app \
  && chmod -R go-w /app

# Remove npm/npx from final image (per requirement: final image must not contain npm)
RUN rm -rf /usr/local/lib/node_modules/npm \
  && rm -f /usr/local/bin/npm /usr/local/bin/npx

# Remove node toolchain (npm / corepack / yarn)
RUN rm -rf \
  /usr/local/lib/node_modules/npm \
  /usr/local/lib/node_modules/corepack \
  /usr/local/bin/npm \
  /usr/local/bin/npx \
  /usr/local/bin/corepack \
  /usr/local/bin/yarn



USER nodeapp

EXPOSE 3000

# Real healthcheck (no fake sleep/echo). Uses node to hit localhost.
HEALTHCHECK --interval=10s --timeout=3s --start-period=10s --retries=3 \
  CMD node -e "const http=require('http');const req=http.get({host:'127.0.0.1',port:3000,path:'/'},res=>process.exit(res.statusCode>=200&&res.statusCode<500?0:1));req.on('error',()=>process.exit(1));req.setTimeout(2000,()=>{req.destroy();process.exit(1);});"

# IMPORTANT: exec form so node becomes PID 1 and receives SIGTERM directly
CMD ["node", "src/index.js"]
