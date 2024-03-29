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

@description('repository branch name')
param branchName string

@description('enable redis cache')
param enableRedis bool
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

@description('bultin roles')
var builtinRoles = loadJsonContent('../../modules/builtinRoles.json')

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

@description('redis cache used by the AzFinSim application')
resource redisCache 'Microsoft.Cache/redis@2022-06-01' = if (enableRedis) {
  name: '${rsPrefix}-redis'
  location: location
  properties: {
    // ref: https://learn.microsoft.com/en-us/azure/azure-cache-for-redis/cache-planning-faq#azure-cache-for-redis-performance
    sku: {
      capacity: 1
      family: 'C'
      name: 'Basic'
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

@description('storage account for data files')
resource sa 'Microsoft.Storage/storageAccounts@2022-05-01' = {
  name: take('sa1${join(split(guid('sa', rsPrefix, resourceGroup().id), '-'), '')}', 24)
  location: location
  sku: {
    name:  'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: false
    accessTier: 'Hot'
    publicNetworkAccess: 'Enabled'
    allowBlobPublicAccess: true
    allowSharedKeyAccess: true
    isNfsV3Enabled: true
    isHnsEnabled: true
    networkAcls: {
      defaultAction: 'Deny' // required for NFS enabled
      bypass: 'AzureServices'
    }
  }

  resource blobServices 'blobServices' existing = {
    name: 'default'
  }
}

resource saContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2022-05-01' = {
  name: 'trades'
  parent: sa::blobServices
  properties: {
    publicAccess: 'Container'
  }
}

@description('role assignment for datasets storage account')
resource roleAssignmentSA 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(managedIdentity.id, sa.id, 'StorageBlobDataContributor')
  scope: sa
  properties: {
    principalId: managedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', builtinRoles.StorageBlobDataContributor)
  }
}

var envVars = {
  CONTAINER_REGISTRY: acr.name
  RESOURCE_GROUP: acrInfo.group
  TEMP_CONTAINER_REGISTRY: take('temp${acr.name}', 50)

  NUMBER_OF_IMAGES: '2'

  SOURCE_LOCATION_1: 'https://github.com/utkarshayachit/azfinsim#main'
  IMAGE_TAG_1: 'azfinsim/azfinsim:latest'
  DOCKER_FILE_1: 'Dockerfile'

  SOURCE_LOCATION_2: 'https://github.com/utkarshayachit/simplified-batch#${branchName}'
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
      saInfo: {
        name: sa.name
        group: resourceGroup().name
        container: saContainer.name
      }
  }
}

@description('application-specific secrets that will be stored in the KeyVault')
var batchSecrets = {
  'azfinsim-appinsights-id': empty(appInsightsInfo) ? '' : appInsights.properties.ApplicationId
  'azfinsim-appinsights-key': empty(appInsightsInfo) ? '' : appInsights.properties.InstrumentationKey
  'azfinsim-app-insights': empty(appInsightsInfo) ? '' : appInsights.properties.ConnectionString
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

var endpoints = union(enableRedis ? [
  // Redis Cache
  {
    name: redisCache.name
    group: resourceGroup().name
    privateLinkServiceId: redisCache.id
    groupIds: ['redisCache']
    privateDnsZoneName: 'privatelink.redis.cache.windows.net'
  }
] : [], [
  // Storage Account
  {
    name: sa.name
    group: resourceGroup().name
    privateLinkServiceId: sa.id
    groupIds: ['blob']
    privateDnsZoneName: 'privatelink.blob.${az.environment().suffixes.storage}'
  }
])

@description('private endpoints')
output endpoints array = endpoints
