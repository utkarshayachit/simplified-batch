/**
    Deploys a vnet with subnets
*/

@description('location for the resources')
param location string = resourceGroup().location

@description('tags for the resources')
param tags object = {}

@description('name for the vnet')
param vnetName string = 'vnet-batch'

@description('just a default NSG')
resource defaultNSG 'Microsoft.Network/networkSecurityGroups@2022-05-01' = {
  name: 'default-nsg'
  location: location
  tags: tags
  properties: {
    securityRules: [
    ]
  }
}

@description('nsg for batch-pool subnet')
resource batchPoolNSG 'Microsoft.Network/networkSecurityGroups@2022-05-01' = {
  name: 'batch-nsg'
  location: location
  tags: tags
  properties: {
     securityRules: [
      {
        name: 'AllowBatchNodeManagement'
        properties: {
          protocol: 'Tcp'
          sourcePortRange: '*'
          sourceAddressPrefix: 'BatchNodeManagement.${location}'
          destinationPortRange: '29876-29877'
          destinationAddressPrefix: '*'
          access: 'Allow'
          direction: 'Inbound'
          description: 'allow batch service to communicate with nodes'
          priority: 100
        }
      }
     ]
  }
}

resource publicip 'Microsoft.Network/publicIPAddresses@2021-05-01' = {
  name: 'nat-pip'
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAddressVersion: 'IPv4'
    publicIPAllocationMethod: 'Static'
    idleTimeoutInMinutes: 4
  }
}

// batch pools need internet access when mouting shared file systems
// using NFS, etc.
@description('natgateway for outbound connectivity to the pools')
resource natgateway 'Microsoft.Network/natGateways@2021-05-01' = {
  name: 'nat-gateway'
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    idleTimeoutInMinutes: 4
    publicIpAddresses: [
      {
        id: publicip.id
      }
    ]
  }
}

@description('the virtual network')
resource vnet 'Microsoft.Network/virtualNetworks@2022-05-01' = {
  name: vnetName
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.10.0.0/16'
      ]
    }

    subnets: [
      {
        name: 'snet-resources'
        properties: {
          addressPrefix: '10.10.0.0/24'
          privateEndpointNetworkPolicies: 'Disabled' 
          privateLinkServiceNetworkPolicies: 'Disabled'
          networkSecurityGroup: {
            id: defaultNSG.id
          }
       }
      }
      {
        name: 'snet-pool'
        properties: {
          addressPrefix: '10.10.1.0/24'
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Disabled'
          networkSecurityGroup: {
            id: defaultNSG.id
          }
          natGateway: {
            id: natgateway.id
          }
        }
      }
      {
        name: 'snet-web-serverfarms'
        properties: {
          addressPrefix: '10.10.2.0/24'
          networkSecurityGroup: {
            id: defaultNSG.id
          }
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Disabled'
          delegations: [
            {
              name: 'Microsoft.Web.serverFarms'
              properties: {
                serviceName: 'Microsoft.Web/serverFarms'
              }
            }
          ]
        }
      }
    ]
  }

  resource snetResources 'subnets' existing = {
    name: 'snet-resources'
  }

  resource snetPool 'subnets' existing = {
    name: 'snet-pool'
  }

  resource snetWebServerfarms 'subnets' existing = {
    name: 'snet-web-serverfarms'
  }
}

@description('virtual network')
output vnet object = {
  id: vnet.id
  name: vnet.name
  group: resourceGroup().name

  snetResources: {
    name: vnet::snetResources.name
    id: vnet::snetResources.id
  }

  snetPool: {
    name: vnet::snetPool.name
    id: vnet::snetPool.id
  }

  snetWebServerfarms: {
    name: vnet::snetWebServerfarms.name
    id: vnet::snetWebServerfarms.id
  }
}

@description('resources for which diagnostic settings can be added')
output diagnosableResoures array = [
  {
    id: vnet.id
    name: vnet.name
    group: resourceGroup().name
    type: vnet.type
  }
  {
    id: defaultNSG.id
    name: defaultNSG.name
    group: resourceGroup().name
    type: defaultNSG.type
  }
  {
    id: batchPoolNSG.id
    name: batchPoolNSG.name
    group: resourceGroup().name
    type: batchPoolNSG.type
  }
]
