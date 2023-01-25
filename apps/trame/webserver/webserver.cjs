const args = require('./args.cjs')
const express = require('express')
const utils = require('./utils.cjs')

const { createProxyMiddleware } = require('http-proxy-middleware')


var opts = args.parse()

function router(req) {
    let components = req.url.split('/').filter(e=>e)
    if (components.length >=2) {
        return `http://${components[1]}`
    }
}

const app = express()
app.use(express.json())
app.use('/static', express.static('static', { index: false, }))
app.use(express.static('html'))
app.use('/proxy', createProxyMiddleware({
    changeOrigin: true,
    ws: true,
    router: router,
    pathRewrite: {
        // remove the '/proxy/host:port' component
        // from the path.
        '^/proxy/[^/]+/': '/',
    },
}))

/// returns a listing of the datasets
app.get('/datasets', async (req, res, next) => {
    try {
        let data = await utils.getDatasets(opts.blobStorageEndpoint)
        res.json({ success: true, data: data })
    } catch (error) {
        next(error)
    }
})

/// start a new job
app.post('/job', async (req, res, next) => {
    try {
        let job = await utils.submitJob(req.body.datasets, req.body.options,
            opts.batchEndpoint, opts.containerRegistry)
        res.json({ success: true, job: job })
    } catch (error) {
        next (error)
    }
})

/// get information about compute node for a job
app.post('/compute_node', async (req, res, next) => {
    try {
        let info = await utils.getComputeNode(req.body.job, opts.batchEndpoint)
        res.json({success: true, path: `/proxy/${info.host}:${info.port}/`})
    } catch (error) {
        next(error)
    }
})

/// cancel job
app.post('/terminate_job', async (req, res, next) => {
    try {
        await utils.terminateJob(req.body.job, opts.batchEndpoint)
        res.json({})
    } catch (error) {
        next(error)
    }
})

app.get('/test', async (req, res, next) => {
    try {
        await utils.testBatch(opts.batchEndpoint)
        res.json({success: true})
    } catch (error) {
        next(error)
    }
})

//----------------------------------------------------------------------------
app.use((error, req, res, next)=> {
    console.log(`error: ${error.message}`)
    next(error)
})

app.use((error, req, res, next) => {
    res.header('Content-Type', 'application/json')
    res.status(error.status || 400).json({
        message: error.message,
        success: false
    })
})

app.listen(opts.port, ()=>{
    console.log('Server started')
    console.log(`   - listening on port ${opts.port}`)
})

process.on('SIGTERM', () => {
    console.log('Server shutting down')
    process.exit(0);
})

process.on('SIGINT', () => {
    console.log('Server shutting down')
    process.exit(0);
})
