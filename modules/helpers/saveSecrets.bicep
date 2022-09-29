/**
  A module to save secrets stored in an object/dictionary to a key vault.
*/

@description('name of the key vault')
param keyVaultName string

@secure()
@description('the dictionary of secrets to store')
param secrets object

resource keyVault 'Microsoft.KeyVault/vaults@2021-06-01-preview' existing = {
  name: keyVaultName
}

resource asecret 'Microsoft.KeyVault/vaults/secrets@2022-07-01' = [for item in items(secrets): {
  parent: keyVault
  name: item.key
  properties: {
    value: item.value
  }
}]
