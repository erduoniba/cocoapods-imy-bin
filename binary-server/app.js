const Koa = require('koa')
const mongoose = require('mongoose')

const { loadConfig } = require('./server/config')
const createRouter = require('./server/routes')
const { errorHandler, securityHeaders } = require('./server/middleware/http')
const { createStorage } = require('./server/utils/dir')
const Component = require('./server/models/component')

function createApp(config = loadConfig()) {
  const app = new Koa()
  const storage = createStorage(config.storageRoot)
  const router = createRouter({ config, storage })

  app.context.config = config
  app.context.storage = storage
  app.use(errorHandler)
  app.use(securityHeaders)
  app.use(router.routes())
  app.use(router.allowedMethods())
  app.on('error', (error, ctx) => {
    console.error(JSON.stringify({
      message: error.message,
      method: ctx?.method,
      path: ctx?.path,
      status: ctx?.status,
    }))
  })

  return app
}

async function start() {
  const config = loadConfig()
  const storage = createStorage(config.storageRoot)

  await storage.ensureStorageRoot()
  await mongoose.connect(config.mongodbUri, {
    serverSelectionTimeoutMS: config.mongodbServerSelectionTimeoutMs,
  })
  await Component.init()

  const app = createApp(config)
  const server = app.listen(config.port, config.host, () => {
    console.log(`binary-server listening on http://${config.host}:${config.port}`)
  })

  const shutdown = async () => {
    server.close()
    await mongoose.disconnect()
  }

  process.once('SIGINT', shutdown)
  process.once('SIGTERM', shutdown)
}

if (require.main === module) {
  start().catch((error) => {
    console.error(error)
    process.exitCode = 1
  })
}

module.exports = {
  createApp,
  start,
}
