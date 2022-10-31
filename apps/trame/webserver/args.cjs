const { Command } = require('commander')

const program = new Command()
program.name('webserver')
    .description('Azure/trame Gateway Web-Server')
    .version('1.0.0')

program
    .option('-p,--port <number>', 'port number', 8000)
    .requiredOption('-e,--batch-endpoint <url>', 'batch account endpoint (required)')
    .requiredOption('-s,--blob-storage-endpoint <url>', 'blob storage account endpoint (required)')
    .requiredOption('-c,--container-registry <url>', 'container registry login server (required)')
    .option('-i,--managed-identity-client-id <id>', 'user managed identity client id')

/**
 * Parses command line arguments
 * @returns parsed command line options
 */
function parse() {
    program.parse()
    return program.opts()
}

function opts() {
    return program.opts()
}

module.exports.parse = parse
module.exports.opts = opts