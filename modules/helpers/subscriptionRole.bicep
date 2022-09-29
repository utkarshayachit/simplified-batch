targetScope = 'subscription'

param principalId string
param principalType string
param roleDefinitionId string

resource miSubscriptionReaderRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id, principalId, roleDefinitionId)
  scope: subscription()
  properties: {
    principalId: principalId
    principalType: principalType
    roleDefinitionId: roleDefinitionId
  }
}
