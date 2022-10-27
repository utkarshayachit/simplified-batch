/**
  LULESH: Catalyst-enabled
  =========================


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

@description('subnet to use for the batch pool')
param poolSubnetId string
///@}

var rsPrefix = '${environment}-${prefix}-luleshcatalyst'
var dplPrefix = 'dpl-${environment}-${prefix}-luleshcatalyst'

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
  TEMP_CONTAINER_REGISTRY: take('templc${acr.name}', 50)

  NUMBER_OF_IMAGES: '1'

  SOURCE_LOCATION_1: 'https://github.com/utkarshayachit/LULESH.git#catalyst-2.0'
  IMAGE_TAG_1: 'lulesh/lulesh-catalyst:latest'
  DOCKER_FILE_1: 'Dockerfile'
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
    timeout: 'PT1H' // 1 hr
  }
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentity.id}': {}
    }
  }
}

@description('deploy pool(s)')
module dplPools './pools.bicep' = {
  name: '${dplPrefix}-pools'
  scope: resourceGroup(batchAccountInfo.group)
  params: {
      batchAccountName: batchAccountInfo.name
      miInfo: miInfo
      acrInfo: acrInfo
      containerImageNames: [
        '${acr.properties.loginServer}/${envVars.IMAGE_TAG_1}'
      ]
      subnetId: poolSubnetId
  }
}
