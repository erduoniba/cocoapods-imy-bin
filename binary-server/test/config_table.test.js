'use strict'

const test = require('node:test')
const assert = require('node:assert/strict')
const { createApp } = require('../app')
const { loadConfig } = require('../server/config')
const configTableService = require('../server/enterprise/config_table_service')

test('config table service performs CRUD and column synchronization', async () => {
  // 1. List tables (includes initial seed)
  const initialList = await configTableService.listConfigTables()
  assert.ok(Array.isArray(initialList))
  assert.ok(initialList.length >= 1)
  assert.equal(initialList.some(t => t.project === 'HDImyBinApp'), true)

  // 2. Create a new config table
  const testProject = 'TestApp_' + Date.now()
  const created = await configTableService.createConfigTable({
    project: testProject,
    environment: 'dev',
    defaultMode: 'binary',
    activeColumn: '1.0.0',
    columns: [
      {
        name: '1.0.0',
        description: 'TestApp 1.0.0 基线',
        components: [
          { name: 'CoreSDK', version: '1.0.0', mode: 'binary', enabled: true },
        ],
      },
    ],
  })

  assert.equal(created.project, testProject)
  assert.equal(created.activeColumn, '1.0.0')
  assert.equal(created.columns.length, 1)
  assert.equal(created.components.length, 1)
  assert.equal(created.components[0].name, 'CoreSDK')

  // Reject duplicate creation
  await assert.rejects(
    () => configTableService.createConfigTable({ project: testProject }),
    (err) => err.status === 409
  )

  // 3. Update config table
  const updated = await configTableService.updateConfigTable(testProject, {
    environment: 'release_iphoneos',
    components: [
      { name: 'CoreSDK', version: '1.0.1', mode: 'source', enabled: true },
      { name: 'UIModule', version: '2.0.0', mode: 'binary', enabled: true },
    ],
  })
  assert.equal(updated.environment, 'release_iphoneos')
  assert.equal(updated.components.length, 2)
  assert.equal(updated.columns[0].components.length, 2)
  assert.equal(updated.columns[0].components[0].version, '1.0.1')

  // 4. Duplicate column within the table (e.g. 1.0.0 -> 1.1.0)
  const colDuplicated = await configTableService.duplicateConfigTable(testProject, {
    sourceColumn: '1.0.0',
    targetColumn: '1.1.0',
    description: '1.1.0 迭代发版基线',
    setActive: true,
  })
  assert.equal(colDuplicated.columns.length, 2)
  assert.equal(colDuplicated.activeColumn, '1.1.0')
  const newCol = colDuplicated.columns.find(c => c.name === '1.1.0')
  assert.ok(newCol)
  assert.equal(newCol.components.length, 2)
  assert.equal(newCol.components[0].name, 'CoreSDK')

  // 5. Duplicate whole config table to another project
  const targetProject = testProject + '_Cloned'
  const cloned = await configTableService.duplicateConfigTable(testProject, {
    targetProject,
  })
  assert.equal(cloned.project, targetProject)
  assert.equal(cloned.columns.length, 2)
  assert.equal(cloned.activeColumn, '1.1.0')

  // 6. Delete config tables
  await configTableService.deleteConfigTable(testProject)
  await configTableService.deleteConfigTable(targetProject)

  const checkDeleted = await configTableService.getConfigTable(testProject)
  assert.equal(checkDeleted, null)
})

test('config table HTTP endpoints handle list, get, create, update, duplicate, and export', async () => {
  const server = createApp(loadConfig({})).listen(0, '127.0.0.1')
  try {
    await new Promise((resolve) => server.once('listening', resolve))
    const base = `http://127.0.0.1:${server.address().port}`

    // GET /api/v1/config-tables
    const listRes = await fetch(`${base}/api/v1/config-tables`)
    assert.equal(listRes.status, 200)
    const list = await listRes.json()
    assert.ok(Array.isArray(list))
    assert.ok(list.length >= 1)

    // GET /api/v1/config-tables/HDImyBinApp
    const getRes = await fetch(`${base}/api/v1/config-tables/HDImyBinApp`)
    assert.equal(getRes.status, 200)
    const table = await getRes.json()
    assert.equal(table.project, 'HDImyBinApp')
    assert.ok(table.columns.length >= 2)

    // GET /api/v1/config-tables/HDImyBinApp/export
    const exportRes = await fetch(`${base}/api/v1/config-tables/HDImyBinApp/export`)
    assert.equal(exportRes.status, 200)
    assert.ok(exportRes.headers.get('content-disposition').includes('attachment'))
    const exportJson = await exportRes.json()
    assert.equal(exportJson.project, 'HDImyBinApp')

    // POST /api/v1/config-tables (Create)
    const httpProject = 'HttpApp_' + Date.now()
    const createRes = await fetch(`${base}/api/v1/config-tables`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({
        project: httpProject,
        activeColumn: '1.0.0',
        columns: [
          { name: '1.0.0', description: 'Initial', components: [{ name: 'A', mode: 'binary', version: '0.1', enabled: true }] },
        ],
      }),
    })
    assert.equal(createRes.status, 201)
    const createdData = await createRes.json()
    assert.equal(createdData.project, httpProject)

    // PUT /api/v1/config-tables/:project (Update)
    const updateRes = await fetch(`${base}/api/v1/config-tables/${httpProject}`, {
      method: 'PUT',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({
        defaultMode: 'local',
      }),
    })
    assert.equal(updateRes.status, 200)
    const updatedData = await updateRes.json()
    assert.equal(updatedData.defaultMode, 'local')

    // POST /api/v1/config-tables/:project/duplicate (Duplicate Column)
    const dupColRes = await fetch(`${base}/api/v1/config-tables/${httpProject}/duplicate`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({
        sourceColumn: '1.0.0',
        targetColumn: '2.0.0',
      }),
    })
    assert.equal(dupColRes.status, 201)
    const dupColData = await dupColRes.json()
    assert.equal(dupColData.columns.length, 2)
    assert.ok(dupColData.columns.some(c => c.name === '2.0.0'))

    // POST /api/v1/config-tables/:project/duplicate (Duplicate Table)
    const dupTableProj = httpProject + '_Cloned'
    const dupTableRes = await fetch(`${base}/api/v1/config-tables/${httpProject}/duplicate`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({
        targetProject: dupTableProj,
      }),
    })
    assert.equal(dupTableRes.status, 201)
    const dupTableData = await dupTableRes.json()
    assert.equal(dupTableData.project, dupTableProj)

    // POST /api/v1/config-tables/:project/sync (Atomic delta sync: component version update & column ops)
    // Developer A updates Component A version in 1.0.0
    const syncCompRes1 = await fetch(`${base}/api/v1/config-tables/${httpProject}/sync`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({
        action: 'update_component',
        columnName: '1.0.0',
        component: { name: 'A', mode: 'binary', version: '0.2.0', enabled: true },
      }),
    })
    assert.equal(syncCompRes1.status, 200)
    const syncCompData1 = await syncCompRes1.json()
    assert.equal(syncCompData1.columns.find(c => c.name === '1.0.0').components.find(c => c.name === 'A').version, '0.2.0')

    // Developer B concurrently adds Component B in 1.0.0 without overwriting Component A's 0.2.0 update
    const syncCompRes2 = await fetch(`${base}/api/v1/config-tables/${httpProject}/sync`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({
        action: 'update_component',
        columnName: '1.0.0',
        component: { name: 'B', mode: 'source', version: '1.5.0', enabled: true },
      }),
    })
    assert.equal(syncCompRes2.status, 200)
    const syncCompData2 = await syncCompRes2.json()
    const col100 = syncCompData2.columns.find(c => c.name === '1.0.0')
    assert.equal(col100.components.length, 2)
    assert.equal(col100.components.find(c => c.name === 'A').version, '0.2.0')
    assert.equal(col100.components.find(c => c.name === 'B').version, '1.5.0')

    // Developer adds a new version column 3.0.0 via sync
    const syncAddColRes = await fetch(`${base}/api/v1/config-tables/${httpProject}/sync`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({
        action: 'add_column',
        columnName: '3.0.0',
        sourceColumn: '1.0.0',
        description: '3.0.0 发版列',
        activeColumn: '3.0.0',
      }),
    })
    assert.equal(syncAddColRes.status, 200)
    const syncAddColData = await syncAddColRes.json()
    assert.equal(syncAddColData.activeColumn, '3.0.0')
    assert.ok(syncAddColData.columns.some(c => c.name === '3.0.0'))

    // Developer deletes version column 2.0.0 via sync
    const syncDelColRes = await fetch(`${base}/api/v1/config-tables/${httpProject}/sync`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({
        action: 'delete_column',
        columnName: '2.0.0',
      }),
    })
    assert.equal(syncDelColRes.status, 200)
    const syncDelColData = await syncDelColRes.json()
    assert.equal(syncDelColData.columns.some(c => c.name === '2.0.0'), false)

    // DELETE /api/v1/config-tables/:project
    const delRes1 = await fetch(`${base}/api/v1/config-tables/${httpProject}`, { method: 'DELETE' })
    assert.equal(delRes1.status, 200)
    const delRes2 = await fetch(`${base}/api/v1/config-tables/${dupTableProj}`, { method: 'DELETE' })
    assert.equal(delRes2.status, 200)

    // Verify 404 after deletion
    const getDeleted = await fetch(`${base}/api/v1/config-tables/${httpProject}`)
    assert.equal(getDeleted.status, 404)
  } finally {
    await new Promise((resolve) => server.close(resolve))
  }
})
