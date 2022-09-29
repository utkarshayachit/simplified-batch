# Simplified Azure Batch Deployment for HPC use-cases

This project demonstrates how to setup an Azure environment that uses Azure Batch
managed service for typical HPC use-cases. This can serve as the starting point for
production deployments for similar applications and use-cases applicable to wide
variety of domains.

## Applications / Demos

This project currently includes the following demos.

### AzFinSim: Fintech Risk Simulation

`azfinsim` is a simple application that models a typical trade
risk analysis in fintech. While the application provided is a synthetic risk
simulation designed to demonstrate high throughput in a financial risk/grid
scenario, the actual framework is generic enough to be applied to any
embarrassingly parallel / high-throughput computing style scenario. If you have
a large scale computing challenge to solve, deploying this example is a
good place to start, and once running it's easy enough to insert your own code
and libraries in place of azfinsim.

Key features:

* application containerized using `Docker`
* executed by performing a parameter sweep in an embarrassingly parallel mode
* `todo-->`: add more stuff that mentions important aspects of this demo

## Deployment

Before you can try any of the demos, you first need to deploy the infrastructure on Azure.
This section takes you through the steps involved in making a deployment.

### Prerequisites

1. **Ensure valid subscription**: Ensure that you a chargeable Azure subscription that you can use and your have
   `Owner` access to the subscription. 

2. **Accept legal terms**: The demos use container images that require you to accept
   legal terms. This only needs to be done once for the subscription. To accept these legal terms,
   you need to execute the following Azure CLI command once. You can do this using the 
   [Azure Cloud Shell](https://ms.portal.azure.com/#cloudshell/) in the [Azure portal](https://ms.portal.azure.com)
   or your local computer. To run these commands on your local computer, you must have Azure CLI installed.

   ```sh
   # For Azure Cloud Shell, pick Bash (and not powershell)
   # If not using Azure Cloud Shell, use `az login` to login if needed.

   # accept image terms
   az vm image terms accept --urn microsoft-azure-batch:ubuntu-server-container:20-04-lts:latest
   ```

3. **Get Batch Service Id**: Based on your tenant, which may be different, hence it's
   best to confirm. In [Azure Cloud Shell](https://ms.portal.azure.com/#cloudshell/),
   run the following:

   ```sh
    az ad sp list --display-name "Microsoft Azure Batch" --filter "displayName eq 'Microsoft Azure Batch'" | jq -r '.[].id'

    # output some alpha numeric string e.g.
    f520d84c-3fd3-4cc8-88d4-2ed25b00d27a
   ```

   Save the value shown then you will need to enter that value,
   instead of the default, for `batchServiceObjectId` (shown as **Batch Service Object Id**,
   if deploying using the portal) when deploying the infrastructure.

   If the above returns an empty string, you may have to register "Microsoft.Batch" as a registered
   resource provider for your subscription. You can do that using the portal, browse to your `Subscription >
   Resource Providers` and then search for `Microsoft.Batch`. Or use the following command and then try
   the `az ad sp list ...` command again

   ```sh
   az provider register -n Microsoft.Batch --subscription <your subscription name> --wait
   ```

## Issues

1. Getting a deployment script to execute `az ad sp ...` fails with insuffient
   permissions so for now users have to manually run and enter the batch service
   object id.

## TODOs

1. [x] `endpoints` need to created in the same resource group as the resource to which
   we are adding that endpoint. Currently, they are all created under the same
   resource-group. FIXME: doesn't work as expected (see redis)
2. [ ] Add un-secured mode; this should make it easier for someone to try out the
       application quickly; avoiding need for jumpboxes or vpn-gateways
3. [ ] pools with different managed identities with access to different resources.
4. [ ] spot-vm reclaming and checkpointing
5. [x] redeployment fails due to some redis + endpoit error. -- fixed by ensuring setting
       publicNetworkAccess to false on the cache by default. We may need to fix this when #2 is fixed

## Acknowledgements

* The deployment architecture is based on [AzureBatch-Secured](https://github.com/mocelj/AzureBatch-Secured).
* The AzFinSim application is forked from [AzFinSim](https://github.com/mkiernan/azfinsim).
