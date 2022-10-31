/**
  Deploy resources that need private end points to have
  been setup first.
*/

///@{
/**
  These should match values specified when deploying the infrastructure.
*/
@description('location for all resources')
param location string = resourceGroup().location

@description('prefix to use for all deployments')
param dplPrefix string

@description('prefix to use for all resources')
param rsPrefix string 
///@}

///@{
/// resource information
param batchAccountInfo object = {
  name: null
  group: resourceGroup().name
}

param miInfo object = {
  name: null
  group: resourceGroup().name
}

@description('datasets blob/container storage account info')
param saInfo object = {
  name: null
  group: resourceGroup().name
  container: null
}

param acrInfo object = {
  name: null
  group: resourceGroup().name
}

@description('subnet to use for the batch pool')
param poolSubnetId string

@description('webapp subnet id')
param appServiceSubnetId string

@description('container image for trame')
param containerImages object = {
  trame: null
  webserver: null
}
///@}

///@{
// Existing resources
@description('batch account')
resource batchAccount 'Microsoft.Batch/batchAccounts@2022-06-01' existing = {
  name: batchAccountInfo.name
  scope: resourceGroup(batchAccountInfo.group)
}

@description('managed identity for this application')
resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2022-01-31-preview' existing = {
  name: miInfo.name
  scope: resourceGroup(miInfo.group)
}

@description('datasets storage account')
resource sa 'Microsoft.Storage/storageAccounts@2022-05-01' existing = {
  name: saInfo.name
  scope: resourceGroup(saInfo.group)
}

@description('container registry')
resource acr 'Microsoft.ContainerRegistry/registries@2021-06-01-preview' existing = {
  name: acrInfo.name
  scope: resourceGroup(acrInfo.group)
}
///@}

@description('deploy pool(s)')
module dplPools './pools.bicep' = {
  name: '${dplPrefix}-pools'
  scope: resourceGroup(batchAccountInfo.group)
  params: {
      batchAccountName: batchAccountInfo.name
      miInfo: miInfo
      acrInfo: acrInfo
      saInfo: saInfo
      containerImageNames: [ containerImages.trame ]
      subnetId: poolSubnetId
  }
}

@description('app service plan for web app')
resource appServicePlan 'Microsoft.Web/serverfarms@2022-03-01' = {
  name: '${rsPrefix}-plan'
  location: location
  properties: {
    reserved: true
  }
  sku: {
    name: 'B1'
  }
  kind: 'linux'
}

@description('app-service')
resource appService 'Microsoft.Web/sites@2022-03-01' = {
  name: '${rsPrefix}-trame-website'
  location: location
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentity.id}': {}
    }
  }
  properties: {
    enabled: true
    serverFarmId: appServicePlan.id
    httpsOnly: true
    reserved: true
    hyperV: false
    vnetRouteAllEnabled: true
    vnetImagePullEnabled: true
    vnetContentShareEnabled: false
    virtualNetworkSubnetId: appServiceSubnetId
    publicNetworkAccess: 'Enabled'
    siteConfig: {
      acrUseManagedIdentityCreds: true
      acrUserManagedIdentityID: managedIdentity.properties.clientId
      appCommandLine: '-s ${sa.properties.primaryEndpoints.blob} -e https://${batchAccount.properties.accountEndpoint} -c ${acr.properties.loginServer} -i ${managedIdentity.properties.clientId}'
      alwaysOn: true
      linuxFxVersion: 'DOCKER|${containerImages.webserver}'
      numberOfWorkers: 1
      vnetName: null
      appSettings: [
        {
          // this is still needed; vnetImagePullEnabled is not working
          name: 'WEBSITE_PULL_IMAGE_OVER_VNET'
          value: 'true'
        }
        {
          name: 'WEBSITES_PORT'
          value: '80'
        }
      ]
    }
  }
}

output websiteURL string = 'https://${appService.properties.defaultHostName}'
