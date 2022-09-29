/**
  Entry point to deploy the infrastructure.
*/
targetScope = 'subscription'

@description('location where all resources should be deployed')
param location string = deployment().location

@allowed([
  'dev'
  'test'
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

@description('enable deployment of the VPN gateway')
param enableVPNGateway bool = true

@description('enable jumbox deployment; primarily intended for debugging')
param enableJumpbox bool = true

@description('enable AzFinSim demo')
param enableAzFinSim bool = true

@minLength(4)
@maxLength(20)
@description('Username for both the Linux and Windows VM. Must only contain letters, numbers, hyphens, and underscores and may not start with a hyphen or number. Only needed when providing enableJumpbox=true.')
param adminUsername string = 'azureadmin'

@secure()
// @minLength(12) -- Ideally we'd have this here, but to support the multiple varients we will remove it.
@maxLength(70)
@description('Password for both the Linux and Windows VM. Password must have 3 of the following: 1 lower case character, 1 upper case character, 1 number, and 1 special character. Must be at least 12 characters. Only needed when providing enableJumpbox=true.')
param adminPassword string

@description('deploy infrastructure in a locked-down mode')
var deploySecured = (environment != 'dev')

var rsPrefix = '${environment}-${prefix}'
var dplPrefix = 'dpl-${environment}-${prefix}'

param timestamp string = utcNow('g')

var tags = {
  'last deployed' : timestamp
  'deployed by': deployer
  uda_deleteme: 'true'
}

var resourceGroupNamesMultiple = {
  mainRG: 'rg-${rsPrefix}'
  diagnosticsRG: 'rg-${rsPrefix}-diagnostics'
  networkRG: 'rg-${rsPrefix}-network'
  jumpboxRG: 'rg-${rsPrefix}-jumpboxes'
  azfinsimRG: 'rg-${rsPrefix}-azfinsim'
}

var resourceGroupNamesSingle = {
  mainRG: 'rg-${rsPrefix}'
  diagnosticsRG: 'rg-${rsPrefix}'
  networkRG: 'rg-${rsPrefix}'
  jumpboxRG: 'rg-${rsPrefix}'
  azfinsimRG: 'rg-${rsPrefix}'
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
resource networkRG 'Microsoft.Resources/resourceGroups@2021-04-01' = if (deploySecured) {
  name: resourceGroupNames.networkRG
  location: location
  tags: tags
}

@description('deployment for network (hub/spoke)')
module dplHubSpoke 'modules/hub_and_spoke.bicep' = if (deploySecured) {
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
    enablePublicNetworkAccess: !deploySecured
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
    enablePublicNetworkAccess: !deploySecured
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
    poolSubnetId: deploySecured? dplHubSpoke.outputs.vnetSpokeOne.snetPool.id : ''
    logAnalyticsWorkspaceId: (enableDiagnostics ? dplApplicationInsights.outputs.logAnalyticsWorkspace.id : '')
  }
}

//------------------------------------------------------------------------------
/**
  Next we setup private endpoints. This is a two step process;
  first, we deploy private DNS zones and virtual network links
*/
var endpoints = concat(dplResources.outputs.endpoints, dplStorage.outputs.endpoints, (enableAzFinSim ? dplAzFinSim.outputs.endpoints: []))
var dnszones = union(map(endpoints, arg => arg.privateDnsZoneName), [])

module dplDNSZones 'modules/dnsZonesAndLinks.bicep' = if (deploySecured) {
  scope: networkRG
  name: '${dplPrefix}-dnszones'
  params: {
    prefix: prefix
    dnsZones: dnszones
    vnetLinks: deploySecured ? [
        dplHubSpoke.outputs.vnetHub.id
        dplHubSpoke.outputs.vnetSpokeOne.id
    ] : []
    tags: tags
  }
}

module dplEndpoints 'modules/privateEndpoints.bicep' = if (deploySecured) {
  scope: mainRG
  name: '${dplPrefix}-eps'
  params: {
    location: location
    endpoints: endpoints
    dnsZoneGroupName: networkRG.name
    vnet: deploySecured ? {
      group: networkRG.name
      name: dplHubSpoke.outputs.vnetSpokeOne.name
      subnet: dplHubSpoke.outputs.vnetSpokeOne.snetResources.name
    } : {}
  }
  dependsOn: [
    dplDNSZones
  ]
}

//------------------------------------------------------------------------------
/**
  Deploy jumpbox.
*/
resource jumpboxRG 'Microsoft.Resources/resourceGroups@2021-04-01' = if (enableJumpbox && deploySecured) {
  name: resourceGroupNames.jumpboxRG
  location: location
  tags: tags
}

module dplJumpboxes 'modules/jumpboxes.bicep' = if (enableJumpbox && deploySecured) {
  scope: jumpboxRG
  name: '${dplPrefix}-jumpboxes'
  params: {
    location: location
    vnet: deploySecured ? {
      group: networkRG.name
      name: dplHubSpoke.outputs.vnetHub.name
      subnet: dplHubSpoke.outputs.vnetHub.snetResources.name
    } : {}
    adminUsername: adminUsername
    adminPassword: adminPassword
    logAnalyticsWorkspaceId: (enableDiagnostics ? dplApplicationInsights.outputs.logAnalyticsWorkspace.id : '')
    tags: tags
  }
}
