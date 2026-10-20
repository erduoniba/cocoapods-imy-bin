# Binary Server

Binary Server stores component archives for `cocoapods-imy-bin`. It retains the existing read API used by generated podspecs:

- `GET /frameworks`
- `GET /frameworks/:name`
- `GET /frameworks/:name/:version`
- `GET /frameworks/:name/:version/zip`

`POST /frameworks` and `DELETE /frameworks/:name/:version` are mutating operations. In production they require a `BINARY_SERVER_TOKEN` with either `Authorization: Bearer <token>` or `X-Binary-Server-Token: <token>`.

New experimental `/api/v1` routes are documented in [the platform foundation guide](../docs/platform-foundation.md). They are disabled by default and **cannot be enabled in production** until OIDC and durable artifact storage are implemented.

## Prerequisites

- Node.js 22 or later
- MongoDB with a dedicated application account
- A persistent storage directory outside the checkout

## Configuration

Copy `.env.example` to a deployment-specific secret store or environment configuration. Do not commit `.env`.

| Variable | Required | Purpose |
| --- | --- | --- |
| `NODE_ENV` | yes | Set to `production` for deployed instances. |
| `HOST` / `PORT` | yes | Bind address and port. The default host is loopback-only. |
| `MONGODB_URI` | yes | MongoDB connection URI, including production credentials. |
| `BINARY_STORAGE_ROOT` | yes | Persistent archive storage directory. |
| `BINARY_SERVER_TOKEN` | production | At least 32 characters; protects upload and delete operations. |
| `MAX_UPLOAD_BYTES` | no | Maximum archive upload size, default `524288000`. |

The server refuses to start in production without a sufficiently long `BINARY_SERVER_TOKEN`.

## Install and run

```sh
npm ci
npm test
NODE_ENV=production npm start
```

Expose the service through a TLS-terminating reverse proxy. Keep MongoDB private, run the service with a least-privilege account, and back up both MongoDB and `BINARY_STORAGE_ROOT` together.

## Upload and delete

```sh
curl --fail-with-body \
  --header "Authorization: Bearer $BINARY_SERVER_TOKEN" \
  --form 'name=PodA' \
  --form 'version=0.2.4' \
  --form 'annotate=release build' \
  --form 'file=@PodA.framework.zip' \
  http://127.0.0.1:8080/frameworks

curl --fail-with-body \
  --header "Authorization: Bearer $BINARY_SERVER_TOKEN" \
  --request DELETE \
  http://127.0.0.1:8080/frameworks/PodA/0.2.4
```

The service accepts one `.zip` file per upload, calculates and stores its SHA-256 hash, and writes the file only after the component/version reservation succeeds. Deleting `PodA/0.2.4` removes only that version's directory.

## Health check

`GET /healthz` returns `200` only while the MongoDB connection is ready; otherwise it returns `503`.
