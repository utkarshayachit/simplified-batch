param principalId string
param principalType string
param roleDefinitionId string

param storageAccount object = {
  name: null
  group: null
}

// give batchManagedIdentity access to the storage account
resource sa 'Microsoft.Storage/storageAccounts@2021-02-01' existing = {
  name: storageAccount.name
}

resource roleAssignmentSA 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(principalId, sa.id, roleDefinitionId)
  scope: sa
  properties: {
    principalId: principalId
    principalType: principalType
    roleDefinitionId: roleDefinitionId
  }
}
