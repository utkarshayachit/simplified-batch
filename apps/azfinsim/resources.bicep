/**
  AzFinSim
  ========

  This example demonstrates how we can setup applications on top of the basic
  infrastructure. It leverages core resources set up in `infrastructure.bicep`.

  Additional resources deployed by this application are as follows:
  1. redis cache
*/

///@{
/**
  These should match values specified when deploying the infrastructure.
*/
@description('location for all resources')
param location string = resourceGroup().location

@allowed([
  'dev'
  'test'
  'prod'
])
@description('the environment to deploy under')
param environment string

@description('a prefix used for all resources')
@minLength(5)
@maxLength(13)
param prefix string
///@}

///@{
/**
  These are resource definitions.
*/
param keyVaultInfo object = {
  name: null
  group: resourceGroup().name
}

param batchAccountInfo object = {
  name: null
  group: resourceGroup().name
}

param acrInfo object = {
  name: null
  group: resourceGroup().name
}

param miInfo object = {
  name: null
  group: resourceGroup().name
}

param appInsightsInfo object = {
  name: null
  group: resourceGroup().name
}

param poolSubnetId string

@description('log analytics workspace id, if any')
param logAnalyticsWorkspaceId string = ''

var rsPrefix = '${environment}-${prefix}-azfinsim'
var dplPrefix = 'dpl-${environment}-${prefix}-azfinsim'
var enableDiagnostics = logAnalyticsWorkspaceId != ''
var deploySecured = (environment != 'dev')

resource acr 'Microsoft.ContainerRegistry/registries@2021-06-01-preview' existing = {
  name: acrInfo.name
  scope: resourceGroup(acrInfo.group)
}

resource appInsights 'Microsoft.Insights/components@2020-02-02' existing = if (!empty(appInsightsInfo)) {
  name: appInsightsInfo.name
  scope: resourceGroup(appInsightsInfo.group)
}

@description('managed identity for this application')
resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2022-01-31-preview' existing = {
  name: miInfo.name
  scope: resourceGroup(miInfo.group)
}

var enableRedis = true

@description('redis cache used by the AzFinSim application')
resource redisCache 'Microsoft.Cache/redis@2022-06-01' = if (enableRedis) {
  name: '${rsPrefix}-redis'
  location: location
  properties: {
    sku: {
      capacity: 1
      family: 'C'
      name: 'Standard'
    }
    publicNetworkAccess: deploySecured ? 'Disabled' : 'Enabled'
  }
}

resource redisCache_diagnosticsSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (enableDiagnostics && enableRedis) {
  scope: redisCache
  name: 'redis-la'
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
      }
    ]
  }
}

var envVars = {
  CONTAINER_REGISTRY: acr.name
  RESOURCE_GROUP: acrInfo.group
  TEMP_CONTAINER_REGISTRY: take('temp${acr.name}', 50)

  NUMBER_OF_IMAGES: '2'

  SOURCE_LOCATION_1: 'https://github.com/utkarshayachit/azfinsim#refactor'
  IMAGE_TAG_1: 'azfinsim/azfinsim:latest'
  DOCKER_FILE_1: 'Dockerfile'

  SOURCE_LOCATION_2: 'https://github.com/utkarshayachit/simplified-batch#main'
  IMAGE_TAG_2: 'azfinsim/tools:latest'
  DOCKER_FILE_2: 'Dockerfile.apps'
}

@description('deployment script to build and push container image')
resource buildnpushContainerImage 'Microsoft.Resources/deploymentScripts@2020-10-01' = {
  name: '${rsPrefix}-pushimages'
  location: location
  kind: 'AzureCLI'
  properties: {
    azCliVersion: '2.30.0'
    retentionInterval: 'PT1H' // 1 hour
    cleanupPreference: 'OnExpiration'
    environmentVariables: map(items(envVars), item => {
        name: item.key
        value: item.value
    })
    scriptContent: loadTextContent('../../modules/helpers/buildContainerImage.sh', 'utf-8')
    timeout: 'PT20M' // 20 min
  }
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentity.id}': {}
    }
  }
}

@description('deploy pool(s)')
module dplPools 'pools.bicep' = {
  name: '${dplPrefix}-pools'
  scope: resourceGroup(batchAccountInfo.group)
  params: {
      batchAccountName: batchAccountInfo.name
      miInfo: miInfo
      acrInfo: acrInfo
      keyVaultInfo: keyVaultInfo
      containerImageNames: [
        '${acr.properties.loginServer}/${envVars.IMAGE_TAG_1}'
        '${acr.properties.loginServer}/${envVars.IMAGE_TAG_2}'
      ]
      subnetId: poolSubnetId
  }
}

@description('application-specific secrets that will be stored in the KeyVault')
var batchSecrets = {
  'azfinsim-appinsights-id': !empty(appInsightsInfo) ? '' : appInsights.properties.ApplicationId
  'azfinsim-appinsights-key': !empty(appInsightsInfo) ? '' : appInsights.properties.InstrumentationKey
  'azfinsim-cache-key': enableRedis ? redisCache.listKeys().primaryKey : ''
  'azfinsim-cache-name': enableRedis ? redisCache.properties.hostName : ''
  // 'azfinsim-cache-port': enableRedis ? redisCache.properties.port : '' // non SSL-port
  'azfinsim-cache-port': '6380' // SSL-port
  'azfinsim-cache-ssl': 'yes'
}

module dplSaveSecrets '../../modules/helpers/saveSecrets.bicep' = {
  name: '${dplPrefix}-azfinsimSaveSecrets'
  scope: resourceGroup(keyVaultInfo.group)
  params: {
    keyVaultName: keyVaultInfo.name
    secrets: batchSecrets
  }
}

var endpoints = enableRedis ? [
  // Redis Cache
  {
    name: redisCache.name
    group: resourceGroup().name
    privateLinkServiceId: redisCache.id
    groupIds: ['redisCache']
    privateDnsZoneName: 'privatelink.redis.cache.windows.net'
  }
] : []

@description('private endpoints')
output endpoints array = endpoints
