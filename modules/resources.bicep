/**
  This module deploys supplementary resources needed for the environment.
  These include:
    1. Key Vault: used to store secrets
    2. Azure Container Registry: used to store container images
    3. Batch account: the batch account in user-subscription pool allocation mode
    4. A User-MI for the batch account

  Additionally, if enabled, this registers diagnostics settings for the resources
  created to populate logs/metrics.
*/

param prefix string
param location string = resourceGroup().location
param tags object
param logAnalyticsWorkspaceId string = ''

@description('globally unique name for the container registry; must be unique across Azure and container alphanumerics only')
@minLength(5)
@maxLength(50)
param acrName string = take('acr${join(split(guid('acr', prefix, resourceGroup().id), '-'), '')}', 50)

@description('globally unique name for the batch account. Lowercase letters and numbers only')
@minLength(3)
@maxLength(24)
param baName string = take('ba${join(split(guid('ba', prefix, resourceGroup().id), '-'), '')}', 24)

@description('globally unique name for the key-vault. alphanumerics and hyphens only')
@minLength(3)
@maxLength(24)
param kvName string = take('kv-${guid('kv', prefix, resourceGroup().id)}', 24)

@description('id for storage account to associated with batch account as auto-storage')
param baStorageAccount object = {
  name: null
  id: null
}

@description('true if diagnostics are enabled')
var enableDiagnostics = logAnalyticsWorkspaceId != '' ? true : false

@description('Batch Service Object Id (az ad sp show --id "ddbf3205-c6bd-46ae-8127-60eb93363864" --query id)')
param batchServiceObjectId string

@description('enable public network access to  the batch account for control')
param enableBatchAccountPublicNetworkAccess bool

//------------------------------------------------------------------------------
@description('bultin roles')
var builtinRoles = loadJsonContent('builtinRoles.json')

//------------------------------------------------------------------------------
/*
 Setup key vault to store all secrets.

 KeyVault is also required when using Batch with 'User Subscription' pool allocation
 mode. In that case, we need to assign access policy to the key valut so that
 batch service can access/modify it.
 Currently, it doesn't seem like we can use RBAC to grant Batch Service access to the
 key-vault.
*/
resource keyVault 'Microsoft.KeyVault/vaults@2022-07-01' = {
  name: kvName
  location: location
  properties: {
    enabledForDeployment: true
    enabledForTemplateDeployment: true
    enabledForDiskEncryption: true
    enableRbacAuthorization: false /*see note above */
    enableSoftDelete: true
    enablePurgeProtection: true
    publicNetworkAccess: 'disabled'
    tenantId: tenant().tenantId
    sku: {
      name: 'standard'
      family: 'A'
    }
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Deny'
    }
    accessPolicies: [
      {
        /* for 'user subscription' pool allocation mode, we need these access policies */
        objectId: batchServiceObjectId
        tenantId: tenant().tenantId
        permissions: {
          secrets: [
            'get'
            'set'
            'list'
            'delete'
            'recover'
          ]
        }
      }

      {
        /* access policy for MI */
        objectId: batchManagedIdentity.properties.principalId
        tenantId: batchManagedIdentity.properties.tenantId
        permissions: {
          secrets: [
            'get'
            'set'
            'list'
            'delete'
            'recover'
          ]
        }
      }

    ]
  }
  tags: tags
}

resource kvdiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (enableDiagnostics) {
  name: '${keyVault.name}-diag'
  scope: keyVault
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
     {
      category: 'AuditEvent'
      enabled: true
      retentionPolicy: {
        days: 1
        enabled: true
      }
     } 
    ]
  }
}


//------------------------------------------------------------------------------
/**
  Container registry to store all contaier images.
*/
resource acr 'Microsoft.ContainerRegistry/registries@2021-06-01-preview' = {
  name: acrName
  location: location
  sku: {
    name: 'Premium' // premium SKU is needed for ACR with private endpoint.
  }
  properties: {
    adminUserEnabled: false // only RBAC
    publicNetworkAccess: 'Disabled'
    zoneRedundancy: 'Disabled'
    networkRuleBypassOptions: 'AzureServices'
  }
}

resource acr_diagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (enableDiagnostics) {
  name: '${acr.name}-diag'
  scope: acr
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      {
        category: 'ContainerRegistryRepositoryEvents'
        enabled: true
        retentionPolicy: {
          days: 1
          enabled:  true
        }
      }
      {
        category: 'ContainerRegistryLoginEvents'
        enabled: true
        retentionPolicy: {
          days: 1
          enabled:  true
        }
      }
    ]
  }
}

//------------------------------------------------------------------------------
/**
  Batch account with a User Managed Identity for the account.
*/
resource batchManagedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2018-11-30' = {
  name: '${baName}-identity'
  location: location
  tags: tags
}

// give batchManagedIdentity access to key-vault as "Key Vault Secrets User" and "Key Vault Reader"
resource roleAssignment 'Microsoft.Authorization/roleAssignments@2020-10-01-preview' = [for role in ['KeyVaultSecretsUser', 'KeyVaultReader']: {
  name: guid(batchManagedIdentity.id, keyVault.id, role)
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', builtinRoles[role])
    principalId: batchManagedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}]

// FIXME: both roleAssignmentACR and roleAssignmentRG are done so that we can create
// a temp ACR and the import that image when building applications. Avoid this.
// We should be able to use app-specific indentities for that.
// give batchManagedIdentity access to acr
resource roleAssignmentACR 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for role in ['AcrPull', 'AcrPush', 'AcrDelete', 'AcrImageSigner']: {
  name: guid(batchManagedIdentity.id, acr.id, role)
  scope: acr
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', builtinRoles[role])
    principalId: batchManagedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}]

// give batchManagedIdentity access to the group
resource roleAssignmentRG 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for role in ['Contributor']: {
  name: guid(batchManagedIdentity.id, resourceGroup().id, role)
  scope: resourceGroup()
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', builtinRoles[role])
    principalId: batchManagedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}]

// give batchManagedIdentity access to the storage account, if any
resource storageAccount 'Microsoft.Storage/storageAccounts@2021-02-01' existing = if (baStorageAccount.name != null) {
  name: baStorageAccount.name
}

resource roleAssignmentSA 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (baStorageAccount.name != null) {
  name: guid(batchManagedIdentity.id, storageAccount.id, 'StorageBlobDataContributor')
  scope: storageAccount
  properties: {
    principalId: batchManagedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', builtinRoles.StorageBlobDataContributor)
  }
}

//------------------------------------------------------------------------------
// Create the batch account
resource batchAccount 'Microsoft.Batch/batchAccounts@2022-06-01' = {
  name: baName
  location: location
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${batchManagedIdentity.id}': {}
    }
  }
  properties: {
    allowedAuthenticationModes: [
      'AAD'
      'TaskAuthenticationToken'
    ]

    autoStorage: (baStorageAccount.name != '') ? {
      storageAccountId: storageAccount.id
      authenticationMode: 'BatchAccountManagedIdentity'
      nodeIdentityReference: {
        resourceId: batchManagedIdentity.id
      }
    } : {}

    poolAllocationMode: 'UserSubscription'
    publicNetworkAccess: enableBatchAccountPublicNetworkAccess ? 'Enabled' : 'Disabled'
    networkProfile: {
       accountAccess: {
        /* we want to let user manage pools etc from the Internet */
        defaultAction: 'Deny'
         ipRules: [
          {
            action: 'Allow'
            value: '0.0.0.0/0'
          }
         ]
       }
       nodeManagementAccess: {
        // FIXME: limit to pool subnet
        defaultAction: 'Allow'
        
       }
    }

    // for user-subscription pools, a key vault is needed
    keyVaultReference: {
      id: keyVault.id
      url: keyVault.properties.vaultUri
    }
  }

  dependsOn: [
    roleAssignment
    roleAssignmentSA
  ]
}

// References:
//  https://learn.microsoft.com/en-us/azure/private-link/private-endpoint-dns#azure-services-dns-zone-configuration
//  https://learn.microsoft.com/en-us/azure/private-link/private-endpoint-overview#private-link-resource

var endpoints = [
  {
    // Key Vault
    name: keyVault.name
    group: resourceGroup().name
    privateLinkServiceId: keyVault.id
    groupIds: ['vault']
    privateDnsZoneName: 'privatelink.vaultcore.azure.net'// 'privatelink${environment().suffixes.keyvaultDns}'
  }
  {
    // Batch Account
    name: batchAccount.name
    group: resourceGroup().name
    privateLinkServiceId: batchAccount.id
    groupIds: ['batchAccount']
    privateDnsZoneName: 'privatelink.batch.azure.com'
  }

  // // this may be needed in future once we add support
  // // for simplified batch node communication
  // {
  //   // Batch Account
  //   name: batchAccount.name
  //   group: resourceGroup().name
  //   privateLinkServiceId: batchAccount.id
  //   groupIds: ['nodeManagement']
  //   privateDnsZoneName: 'privatelink.batch.azure.com'
  // }

  {
    // ACR
    name :acr.name
    group: resourceGroup().name
    privateLinkServiceId: acr.id
    groupIds: ['registry']
    privateDnsZoneName: 'privatelink${environment().suffixes.acrLoginServer}'
  }
]

@description('Container Registry details')
output acr object = {
  name: acr.name
  id: acr.id
}

@description('Key Vault details')
output keyVault object = {
  name: keyVault.name
  id: keyVault.id
}

@description('managed identity details')
output batchManagedIdentity object = {
  name: batchManagedIdentity.name
  id: batchManagedIdentity.id
}

@description('batch account details')
output batchAccount object = {
  name: batchAccount.name
  id: batchAccount.id
  accountEndpoint: batchAccount.properties.accountEndpoint
}

@description('endpoints')
output endpoints array = endpoints
