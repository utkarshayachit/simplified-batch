const { BatchServiceClient } = require('@azure/batch')
const { loginWithVmMSI } = require('@azure/ms-rest-nodeauth')
const { getBatchCredentials } = require('./utils.cjs')

test('batch-credentials', async ()=>{
    // console.log('create VmMSI creds')
    // let creds = await loginWithVmMSI({
    //     clientId: '....',
    //     resource: "https://batch.core.windows.net/",
    // })
    // console.log('create batch service client', creds)
    // let client = new BatchServiceClient(creds, 'https://<...>.<...>.batch.azure.com')
    // let pools = client.pool.list()
    // console.log('pools', pools)
})