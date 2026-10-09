const multer = require('@koa/multer')

async function errorHandler(ctx, next) {
  try {
    await next()
  } catch (error) {
    const isMulterError = error instanceof multer.MulterError
    const status = isMulterError ? 400 : error.status || error.statusCode || 500
    const code = isMulterError ? 'INVALID_UPLOAD' : error.code || 'INTERNAL_ERROR'
    const message = status >= 500 ? 'Internal server error' : error.message

    ctx.status = status
    ctx.body = {
      error: {
        code,
        message,
      },
    }
    ctx.app.emit('error', error, ctx)
  }
}

async function securityHeaders(ctx, next) {
  ctx.set('Cache-Control', 'no-store')
  ctx.set('Referrer-Policy', 'no-referrer')
  ctx.set('X-Content-Type-Options', 'nosniff')
  await next()
}

module.exports = {
  errorHandler,
  securityHeaders,
}
