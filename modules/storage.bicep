/**
  This module deploys storage accounts.
*/

@description('location for the resources')
param location string = resourceGroup().location

@description('prefix string')
param prefix string
param tags object

@description('unique name for the container registry; must be unique across Azure and container alphanumerics only')
@minLength(5)
@maxLength(50)
param saName string = take('sa0${join(split(guid('sa', prefix, resourceGroup().id), '-'), '')}', 24)

@description('enable public network access to storage accounts')
param enablePublicNetworkAccess bool = false

resource sa 'Microsoft.Storage/storageAccounts@2022-05-01' = {
  name: saName
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    supportsHttpsTrafficOnly: false
    accessTier: 'Hot'
    publicNetworkAccess: enablePublicNetworkAccess ? 'Enabled': 'Disabled'
    allowBlobPublicAccess: enablePublicNetworkAccess
    allowSharedKeyAccess: true // required
    minimumTlsVersion: 'TLS1_2'
    networkAcls: {
      defaultAction: enablePublicNetworkAccess ? 'Allow' : 'Deny'
      bypass: 'AzureServices'
      ipRules: null
    }
  }
  tags: tags

  resource blobServices 'blobServices' existing = {
    name: 'default'
  }
}

resource saContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2022-05-01'= {
  name: 'container0'
  parent: sa::blobServices
  properties: {
    publicAccess: enablePublicNetworkAccess? 'Container' : 'None'
  }
}

var endpoints = [
  {
    name: sa.name
    group: resourceGroup().name
    privateLinkServiceId: sa.id
    groupIds: ['blob']
    privateDnsZoneName: 'privatelink.blob.${environment().suffixes.storage}'
  }
]

@description('storage accounts')
output storageAccounts array = [
  {
    name: sa.name
    id: sa.id
  }
]

@description('endpoints')
output endpoints array = endpoints
