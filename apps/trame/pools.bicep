param batchAccountName string

param miInfo object = {
  name: null
  group: resourceGroup().name
}

@description('block storage account info where all datasets are stored')
param saInfo object = {
  group: null
  name: null
  container: null
}

@allowed([ 
  'Standard_D2s_V3'
  'Standard_D2s_V4'
  'Standard_D2s_V5'
  'Standard_F2s_v2'
  'Standard_F4s_v2'
  'Standard_F8s_v2'
  'Standard_DS5_v2'
]) 
param batchNodeSku  string = 'Standard_DS5_v2'

param containerImageNames array

param acrInfo object = {
  name: null
  group: resourceGroup().name
}

@description('pool subnet id')
param subnetId string

var taskSlotsPerNode = {
  Standard_D2s_V3: 2
  Standard_D2s_V4: 2
  Standard_D2s_V5: 2
  Standard_F2s_v2: 2
  Standard_F4s_v2: 4
  Standard_F8s_v2: 8
  Standard_DS5_v2: 8 // has 16 vCPUs
}

resource batchAccount 'Microsoft.Batch/batchAccounts@2022-06-01' existing = {
  name: batchAccountName
}

@description('managed identity for this application')
resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2022-01-31-preview' existing = {
  name: miInfo.name
  scope: resourceGroup(miInfo.group)
}

resource acr 'Microsoft.ContainerRegistry/registries@2021-06-01-preview' existing = {
  name: acrInfo.name
  scope: resourceGroup(acrInfo.group)
}

resource sa 'Microsoft.Storage/storageAccounts@2022-05-01' existing = {
  name: saInfo.name
  scope: resourceGroup(saInfo.group)
}

resource pool 'Microsoft.Batch/batchAccounts/pools@2022-06-01' = {
  name: 'trame-pool'
  parent: batchAccount
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentity.id}': {}
    }
  }
  properties: {
    vmSize: batchNodeSku
    taskSlotsPerNode: taskSlotsPerNode[batchNodeSku]
    taskSchedulingPolicy: {
      nodeFillType:  'Spread' // or 'Pack'
    }
    deploymentConfiguration: {
      virtualMachineConfiguration: {
        imageReference: {
          publisher: 'microsoft-azure-batch'
          offer: 'ubuntu-server-container'
          sku: '20-04-lts'
          version: 'latest'
        }
        nodeAgentSkuId: 'batch.node.ubuntu 20.04'
        containerConfiguration: {
          type: 'DockerCompatible'
          containerImageNames: containerImageNames
          containerRegistries: [
            {
              registryServer: acr.properties.loginServer
              identityReference: {
                resourceId: managedIdentity.id
              }
            }
          ]
        }
      }
    }
    scaleSettings: {
      fixedScale: {
        targetDedicatedNodes: 0
        targetLowPriorityNodes: 0
        resizeTimeout: 'PT15M'
      }
    }
    interNodeCommunication: 'Disabled'
    networkConfiguration: {
      subnetId: subnetId
      publicIPAddressConfiguration: {
        provision:  'NoPublicIPAddresses'
      }
    }
    mountConfiguration: [
      {
        //  azureBlobFileSystemConfiguration: {
        //   accountName: saInfo.name
        //   containerName: saInfo.container
        //   relativeMountPath: 'datasets'
        //   accountKey: sa.listKeys().keys[0].value
        // }

        nfsMountConfiguration: {
          relativeMountPath: 'datasets'
          source: '${sa.name}.blob.${az.environment().suffixes.storage}:/${sa.name}/datasets'
          mountOptions: '-o sec=sys,vers=3,nolock,proto=tcp,ro'
          // ref: https://learn.microsoft.com/en-us/azure/storage/blobs/network-file-system-protocol-support-how-to
        }
      }
    ]
  }
}
