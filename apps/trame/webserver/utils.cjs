const { BlobServiceClient }  = require('@azure/storage-blob')
const { DefaultAzureCredential } = require('@azure/identity')
const { BatchServiceClient } = require('@azure/batch')
const { AzureCliCredentials, loginWithAppServiceMSI } = require("@azure/ms-rest-nodeauth")
const dayjs = require('dayjs')

const args = require('./args.cjs')

const GLOBALS = {
    TRAME_POOL_INFO: {
        poolId: 'trame-pool'
    },

    TASK_USER_IDENTITY: {
        autoUser: {
            elevationLevel: 'admin',
            scope: 'pool',
        }
    },

    PORTS: new Set(),
    PORTS_RANGE: [8000,9000]

}

function getCredentials() {
    let opts = args.opts()
    return new DefaultAzureCredential({
        managedIdentityClientId: opts.managedIdentityClientId
    })
}

async function getBatchCredentials() {
    let opts = args.opts()
    if (opts.managedIdentityClientId) {
       return await loginWithAppServiceMSI(
        { resource: "https://batch.core.windows.net/", clientId: opts.managedIdentityClientId })
    } else {
          return await AzureCliCredentials.create({ resource: "https://batch.core.windows.net/" });
    }
}

async function getDatasets(blobStorageEndpoint) {
    const blobServiceClient = new BlobServiceClient(blobStorageEndpoint, getCredentials())

    let result = []
    for await (const container of blobServiceClient.listContainers()) {
        const containerClient = blobServiceClient.getContainerClient(container.name)
        for await (const blob of containerClient.listBlobsFlat()) {
            result.push({
                name: blob.name,
                container: container.name,
            })
        }
    }
    return result
}

function getUniqueId() {
    let d = new Date();
    // batch job/task names can only have alphanumerics, -, and _. So we remove
    // : and .
    return d.toISOString().replaceAll(':','-').replaceAll('.','-')
}

function getRandomInt(min, max) {
    min = Math.ceil(min);
    max = Math.floor(max);
    return Math.floor(Math.random() * (max - min) + min); // The maximum is exclusive and the minimum is inclusive
}

function pickPort() {
    /// FIXME: this needs to be made more robust
    for (let attempt=0; attempt < 100; attempt +=1) {
        const p = getRandomInt(GLOBALS.PORTS_RANGE[0], GLOBALS.PORTS_RANGE[1])
        if (!GLOBALS.PORTS.has(p)) {
            GLOBALS.PORTS.add(p)
            return p
        }
    }
    throw Error('failed to find free port!')
}

async function submitJob(dataset, container, batchEndpoint, containerRegistryLoginServer, prefix) {
    let batchServiceClient = new BatchServiceClient(await getBatchCredentials(),
        batchEndpoint)

    const jobConfig = {
        id: `${prefix||'trame'}-${getUniqueId()}`,
        displayName: `trame (${dataset}:${container})`,
        poolInfo: GLOBALS.TRAME_POOL_INFO,
    }

    const port = pickPort();
    await batchServiceClient.job.add(jobConfig)

    const taskConfig = {
        id: 'task-0',
        displayName: `trame (${dataset}:${container}) on ${port}`,
        userIdentity: GLOBALS.TASK_USER_IDENTITY,
        containerSettings: {
            containerRunOptions: `-p ${port}:8080`,
            imageName: `${containerRegistryLoginServer}/trame/trame-paraview:latest`,
        },
        commandLine: '/bin/sh -c "/opt/paraview/bin/pvpython ' +
          '/opt/data_viewer/app.py --server --venv /opt/trame/env -i 0.0.0.0 -p 8080 ' +
          '--create-on-server-ready $AZ_BATCH_TASK_WORKING_DIR/server-ready.txt ' +
          `--dataset $AZ_BATCH_NODE_MOUNTS_DIR/${container}/${dataset}"`
    }

    // add task to the job
    await batchServiceClient.task.add(jobConfig.id, taskConfig);

    // update job to terminate when all tasks are done.
    await batchServiceClient.job.update(jobConfig.id, {
        onAllTasksComplete: 'terminatejob',
        poolInfo: GLOBALS.TRAME_POOL_INFO,
    })

    return {
        poolId: jobConfig.poolInfo.poolId,
        jobId: jobConfig.id,
        taskId: taskConfig.id,
        port: port,
    }
}

async function trameServerReady(batchServiceClient, jobId, taskId, timeout) {
    const expiration = dayjs().add(timeout || 1, 'minute')
    while (dayjs() < expiration) {
        let files = await batchServiceClient.file.listFromTask(jobId, taskId, {
            recursive: true,
            fileListFromTaskOptions: {
                'filter': "startswith(name, 'wd/server-ready.txt')",
            }
        })
        if (files.length > 0) {
            console.log('server is ready!')
            return true;
        }
    }
    throw Error('trame server ready timedout')
}

async function getComputeNode(jobInfo, batchEndpoint, timeout) {
    let batchServiceClient = new BatchServiceClient(await getBatchCredentials(), batchEndpoint)

    const expiration = dayjs().add(timeout || 5, 'minute')
    while (dayjs() < expiration) {
        let task = await batchServiceClient.task.get(jobInfo.jobId, jobInfo.taskId)
        if (task.state === 'active' || task.state === 'preparing') {
            await new Promise(r => setTimeout(r, 1000)); // sleep for a second
        } else if (task.state === 'completed') {
            throw Error('task has completed!')
        } else {
            let nodeInfo = await batchServiceClient.computeNode.get(task.nodeInfo.poolId, task.nodeInfo.nodeId)
            await trameServerReady(batchServiceClient, jobInfo.jobId, jobInfo.taskId)
            return {
                host: nodeInfo.ipAddress,
                port: jobInfo.port
            }
        }
    }
    throw Error('task start timed out!')
}

async function terminateJob(jobInfo, batchEndpoint) {
    let batchServiceClient = new BatchServiceClient(await getBatchCredentials(), batchEndpoint)
    
    // explicitly terminate task to otherwise status doesn't change for active tasks
    // when job is terminated.
    await batchServiceClient.task.terminate(jobInfo.jobId, jobInfo.taskId)
    await batchServiceClient.job.terminate(jobInfo.jobId)
}

async function testBatch(batchEndpoint) {
    let batchServiceClient = new BatchServiceClient(await getBatchCredentials(), batchEndpoint)
    let pools = await batchServiceClient.pool.list()
    return pools.length
}

module.exports.getDatasets = getDatasets
module.exports.submitJob = submitJob
module.exports.getComputeNode = getComputeNode
module.exports.terminateJob = terminateJob
module.exports.testBatch = testBatch