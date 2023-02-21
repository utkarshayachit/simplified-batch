/**
  trame: 3D web visualization
  ===========================
*/

///@{
/**
  These should match values specified when deploying the infrastructure.
*/
@description('location for all resources')
param location string = resourceGroup().location

@description('prefix to use for all resources')
param rsPrefix string 

@description('repository branch name')
param branchName string
///@}

///@{
/**
  These are resource definitions.
*/
param acrInfo object = {
  name: null
  group: resourceGroup().name
}

param miInfo object = {
  name: null
  group: resourceGroup().name
}
//@}

@description('bultin roles')
var builtinRoles = loadJsonContent('../../modules/builtinRoles.json')

///@{
// existing resources
@description('container registry')
resource acr 'Microsoft.ContainerRegistry/registries@2021-06-01-preview' existing = {
  name: acrInfo.name
  scope: resourceGroup(acrInfo.group)
}

@description('managed identity for this application')
resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2022-01-31-preview' existing = {
  name: miInfo.name
  scope: resourceGroup(miInfo.group)
}
///@}

var envVars = {
  CONTAINER_REGISTRY: acr.name
  RESOURCE_GROUP: acrInfo.group
  TEMP_CONTAINER_REGISTRY: take('temptr${acr.name}', 50)

  NUMBER_OF_IMAGES: '2'

  SOURCE_LOCATION_1: 'https://github.com/utkarshayachit/vizer#main'
  IMAGE_TAG_1: 'vizer/vizer:latest'
  DOCKER_FILE_1: 'Dockerfile.osmesa'

  SOURCE_LOCATION_2: 'https://github.com/utkarshayachit/simplified-batch#${branchName}'
  IMAGE_TAG_2: 'trame/webserver:latest'
  DOCKER_FILE_2: 'apps/trame/Dockerfile.webserver'
}


@description('deployment script to build and push container images')
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
    timeout: 'PT1H' // 1 hr
  }
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentity.id}': {}
    }
  }
}

@description('storage account for data files')
resource sa 'Microsoft.Storage/storageAccounts@2022-05-01' = {
  name: take('sa1${join(split(guid('sa', rsPrefix, resourceGroup().id), '-'), '')}', 24)
  location: location
  sku: {
    name:  'Premium_LRS'
  }
  kind: 'BlockBlobStorage'
  properties: {
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: false
    accessTier: 'Premium'
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
  name: 'datasets'
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

@description('information about datasets storage accout')
output saInfo object = {
  name: sa.name
  group: resourceGroup().name
  container: saContainer.name
}

@description('container images')
output containerImages object = {
  trame: '${acr.properties.loginServer}/${envVars.IMAGE_TAG_1}'
  webserver: '${acr.properties.loginServer}/trame/webserver:latest'
}

@description('private endpoint candidates')
output endpoints array = [
  {
    name: sa.name
    group: resourceGroup().name
    privateLinkServiceId: sa.id
    groupIds: ['blob']
    privateDnsZoneName: 'privatelink.blob.${az.environment().suffixes.storage}'
  }
]
