/**
  Entry point to deploy the infrastructure.
*/
targetScope = 'subscription'

@description('location where all resources should be deployed')
param location string = deployment().location

@allowed([
  'dev'
  'prod'
])
@description('the environment to deploy under')
param environment string = 'dev'

@description('a prefix used for all resources')
@minLength(5)
@maxLength(13)
param prefix string = uniqueString(environment, subscription().id, location)

@description('identifier/email for user deploying the infrastructure')
param deployer string = 'someone@somedomain.com'

@description('Batch Service Object Id (az ad sp show --id "ddbf3205-c6bd-46ae-8127-60eb93363864" --query id)')
param batchServiceObjectId string

@description('deploy all resources to same resource-group')
param useSingleResourceGroup bool = false

@description('enable diagnostics/logging')
param enableDiagnostics bool = true

@description('enable hub and spoke network deployment')
param enableHubAndSpoke bool = false

@description('When `enableHubAndSpoke` is true, this enable deployment of VPN gateway')
param enableVPNGateway bool = false

@description('enable AzFinSim demo')
param enableAzFinSim bool = false

@description('enable LULESH-Catalyst demo')
param enableLuleshCatalyst bool = false

@description('enable trame demo')
param enableTrame bool = false

@description('repository branch name')
param branchName string = 'main'

param timestamp string = utcNow('g')

//-----------------------------------------------------------------------------

var rsPrefix = '${environment}-${prefix}'
var dplPrefix = 'dpl-${environment}-${prefix}'

@description('tags added to resource groups')
var tags = {
  'last deployed' : timestamp
  'deployed by': deployer
}

var resourceGroupNamesMultiple = {
  mainRG: 'rg-${rsPrefix}'
  diagnosticsRG: 'rg-${rsPrefix}-diagnostics'
  networkRG: 'rg-${rsPrefix}-network'
  azfinsimRG: 'rg-${rsPrefix}-azfinsim'
  luleshCatalystRG: 'rg-${rsPrefix}-lulesh-catalyst'
  trameRG: 'rg-${rsPrefix}-trame'
}

var resourceGroupNamesSingle = {
  mainRG: 'rg-${rsPrefix}'
  diagnosticsRG: 'rg-${rsPrefix}'
  networkRG: 'rg-${rsPrefix}'
  azfinsimRG: 'rg-${rsPrefix}'
  luleshCatalystRG: 'rg-${rsPrefix}'
  trameRG: 'rg-${rsPrefix}'
}

var resourceGroupNames = useSingleResourceGroup ? resourceGroupNamesSingle : resourceGroupNamesMultiple

// TODO: handle useSingleResourceGroup==true properly

//------------------------------------------------------------------------------
/**
  If diagnostics/logging is enabled, deploy resources for those.
*/
@description('resource group to place all diagnostics resources')
resource appInsightsRG 'Microsoft.Resources/resourceGroups@2021-04-01' = if (enableDiagnostics) {
  name: resourceGroupNames.diagnosticsRG
  location: location
  tags: tags
}

@description('deployment for diagnostic resources/workspaces')
module dplApplicationInsights 'modules/applicationInsights.bicep' = if (enableDiagnostics) {
  name: '${dplPrefix}-appinsights'
  scope: appInsightsRG
  params: {
    prefix: rsPrefix
    location: location
    tags: tags
  }
}

//------------------------------------------------------------------------------
/**
  Deploy the network topology. We deploy a hub-spoke(s) network setup.
  The hub is deployed, however spokes are added as needed.
*/
resource networkRG 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: resourceGroupNames.networkRG
  location: location
  tags: tags
}

@description('deployment for network (hub/spoke)')
module dplHubSpoke 'modules/hub_and_spoke.bicep' = if (enableHubAndSpoke) {
  name: '${dplPrefix}-hubspoke'
  scope: networkRG
  params: {
    location: location
    deployVpnGateway: enableVPNGateway
    deployVirtualMachines: false
    adminPassword: 'notused'
    logAnalyticsWorkspaceId: (enableDiagnostics ? dplApplicationInsights.outputs.logAnalyticsWorkspace.id: '')
  }
}

@description('deployment of simply spoke-only network')
module dplSpoke 'modules/spoke.bicep' = if (!enableHubAndSpoke) {
  name: '${dplPrefix}-spoke'
  scope: networkRG
  params: {
    location: location
  }
}

//------------------------------------------------------------------------------
/*
  This is the resource group under which all main resources in the infrastructure
  are deployed.
*/
resource mainRG 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: resourceGroupNames.mainRG
  location: location
  tags: tags
}

/*
  Deploy storage accounts
*/
module dplStorage 'modules/storage.bicep' = {
  name: '${dplPrefix}-storage'
  scope: mainRG
  params: {
    location: location
    prefix: rsPrefix
    tags: tags
  }
}

/*
  Deploy resources under main
*/
module dplResources 'modules/resources.bicep' = {
  name: '${dplPrefix}-resources'
  scope: mainRG
  params: {
    location: location
    prefix: rsPrefix
    tags: tags
    enableBatchAccountPublicNetworkAccess: true
    logAnalyticsWorkspaceId: (enableDiagnostics ? dplApplicationInsights.outputs.logAnalyticsWorkspace.id : '')
    baStorageAccount: dplStorage.outputs.storageAccounts[0]
    batchServiceObjectId: batchServiceObjectId
  }
}

//------------------------------------------------------------------------------
resource azfinsimRG 'Microsoft.Resources/resourceGroups@2021-04-01' = if (enableAzFinSim) {
  name: resourceGroupNames.azfinsimRG
  location: location
  tags: tags
}

module dplAzFinSim 'apps/azfinsim/resources.bicep' = if (enableAzFinSim) {
  name: '${dplPrefix}-azfinsim-resources'
  scope: azfinsimRG
  params: {
    location: location
    environment: environment
    prefix: prefix
    branchName: branchName
    keyVaultInfo: {
      name: dplResources.outputs.keyVault.name
      group: mainRG.name
    }
    batchAccountInfo: {
      name: dplResources.outputs.batchAccount.name
      group: mainRG.name
    }
    acrInfo: {
      name: dplResources.outputs.acr.name
      group: mainRG.name
    }
    miInfo: {
      name: dplResources.outputs.batchManagedIdentity.name
      group: mainRG.name
    }
    appInsightsInfo: (enableDiagnostics ? {
      name: dplApplicationInsights.outputs.appInsights.name
      group: appInsightsRG.name
    } : {})
    poolSubnetId: enableHubAndSpoke? dplHubSpoke.outputs.vnetSpokeOne.snetPool.id : dplSpoke.outputs.vnet.snetPool.id

    logAnalyticsWorkspaceId: (enableDiagnostics ? dplApplicationInsights.outputs.logAnalyticsWorkspace.id : '')
  }
}

//------------------------------------------------------------------------------
resource luleshCatalystRG 'Microsoft.Resources/resourceGroups@2021-04-01' = if (enableLuleshCatalyst) {
  name: resourceGroupNames.luleshCatalystRG
  location: location
}

module dplLuleshCatalyst 'apps/lulesh-catalyst/resources.bicep' = if (enableLuleshCatalyst) {
  name: '${dplPrefix}-lulesh-catalyst-resources'
  scope: luleshCatalystRG
  params: {
    location: location
    environment: environment
    prefix: prefix
    poolSubnetId: enableHubAndSpoke? dplHubSpoke.outputs.vnetSpokeOne.snetPool.id : dplSpoke.outputs.vnet.snetPool.id
    batchAccountInfo: {
      name: dplResources.outputs.batchAccount.name
      group: mainRG.name
    }
    acrInfo: {
      name: dplResources.outputs.acr.name
      group: mainRG.name
    }
    miInfo: {
      name: dplResources.outputs.batchManagedIdentity.name
      group: mainRG.name
    }
  }
}

//------------------------------------------------------------------------------
resource trameRG 'Microsoft.Resources/resourceGroups@2021-04-01' = if (enableTrame) {
  name: resourceGroupNames.trameRG
  location: location
}

module dplTrame 'apps/trame/resources.bicep' = if (enableTrame) {
  name: '${dplPrefix}-trame-resources'
  scope: trameRG
  params: {
    location: location
    rsPrefix: rsPrefix
    branchName: branchName
   acrInfo: {
      name: dplResources.outputs.acr.name
      group: mainRG.name
    }
    miInfo: {
      name: dplResources.outputs.batchManagedIdentity.name
      group: mainRG.name
    }
  }
}

module dplTrameWebsite 'apps/trame/websites.bicep' = if (enableTrame) {
  name: '${dplPrefix}-trame-websites'
  scope: trameRG
  params: {
    location: location
    dplPrefix: dplPrefix
    rsPrefix: rsPrefix
    batchAccountInfo: {
      name: dplResources.outputs.batchAccount.name
      group: mainRG.name
    }
    miInfo: {
      name: dplResources.outputs.batchManagedIdentity.name
      group: mainRG.name
    }
    saInfo: enableTrame? dplTrame.outputs.saInfo : {}
    acrInfo: {
      name: dplResources.outputs.acr.name
      group: mainRG.name
    }
    poolSubnetId: enableHubAndSpoke? dplHubSpoke.outputs.vnetSpokeOne.snetPool.id : dplSpoke.outputs.vnet.snetPool.id
    appServiceSubnetId: enableHubAndSpoke? dplHubSpoke.outputs.vnetSpokeOne.snetWebServerfarms.id : dplSpoke.outputs.vnet.snetWebServerfarms.id
    containerImages: enableTrame? dplTrame.outputs.containerImages : {}
  }
  dependsOn: [
    dplEndpoints
  ]
}
//------------------------------------------------------------------------------
/**
  Next we setup private endpoints. This is a two step process;
  first, we deploy private DNS zones and virtual network links
*/
var endpoints = concat(dplResources.outputs.endpoints, dplStorage.outputs.endpoints,
     (enableAzFinSim ? dplAzFinSim.outputs.endpoints: []),
     (enableTrame? dplTrame.outputs.endpoints : []))

var dnszones = union(map(endpoints, arg => arg.privateDnsZoneName), [])

module dplDNSZones 'modules/dnsZonesAndLinks.bicep' = {
  scope: networkRG
  name: '${dplPrefix}-dnszones'
  params: {
    prefix: prefix
    dnsZones: dnszones
    vnetLinks: enableHubAndSpoke ? [
      dplHubSpoke.outputs.vnetHub.id
      dplHubSpoke.outputs.vnetSpokeOne.id
    ] : [
      dplSpoke.outputs.vnet.id
    ]
    tags: tags
  }
}

module dplEndpoints 'modules/privateEndpoints.bicep' = {
  scope: mainRG
  name: '${dplPrefix}-eps'
  params: {
    location: location
    endpoints: endpoints
    dnsZoneGroupName: networkRG.name
    vnet: enableHubAndSpoke ? {
      group: networkRG.name
      name: dplHubSpoke.outputs.vnetSpokeOne.name
      subnet: dplHubSpoke.outputs.vnetSpokeOne.snetResources.name
    } : {
      group: networkRG.name
      name: dplSpoke.outputs.vnet.name
      subnet: dplSpoke.outputs.vnet.snetResources.name
    }
  }
  dependsOn: [
    dplDNSZones
  ]
}

@description('Batch account endpoint')
output batchAccountEndpoint string = dplResources.outputs.batchAccount.accountEndpoint

@description('Container Registry name')
output containerRegistryName string = dplResources.outputs.acr.name

@description('trame website URL')
output trameURL string = enableTrame ? dplTrameWebsite.outputs.websiteURL : ''

@description('datasets storage account')
output datasetsSAName string = enableTrame ? dplTrame.outputs.saInfo.name : ''
