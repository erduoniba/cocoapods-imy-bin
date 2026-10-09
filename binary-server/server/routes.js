const Router = require('@koa/router')
const multer = require('@koa/multer')

const frameworks = require('./controllers/frameworks')
const { createMutationAuthenticator } = require('./middleware/auth')

function createRouter({ config, storage }) {
  const router = new Router()
  const upload = multer({
    storage: multer.diskStorage({
      destination: (_request, _file, callback) => {
        storage.createUploadDirectory().then(
          (directory) => callback(null, directory),
          (error) => callback(error)
        )
      },
      filename: (_request, _file, callback) => {
        callback(null, storage.createTemporaryFilename())
      },
    }),
    limits: {
      fileSize: config.maxUploadBytes,
      files: 1,
      fields: 3,
    },
    fileFilter: (_request, file, callback) => {
      callback(null, storage.isZipFilename(file.originalname))
    },
  })
  const authenticateMutation = createMutationAuthenticator(config)

  router.get('/healthz', frameworks.health)
  router.get('/frameworks/:name/:version/zip', frameworks.download)
  router.get('/frameworks/:name/:version', frameworks.show)
  router.get('/frameworks/:name', frameworks.show)
  router.get('/frameworks', frameworks.show)
  router.post('/frameworks', authenticateMutation, upload.single('file'), frameworks.create)
  router.delete('/frameworks/:name/:version', authenticateMutation, frameworks.destroy)

  return router
}

module.exports = createRouter
