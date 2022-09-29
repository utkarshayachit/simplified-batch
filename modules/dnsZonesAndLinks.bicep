@description('array of DNS zones to create')
param dnsZones array

@description('array of vnet ids to link to')
param vnetLinks array

@description('prefix')
param prefix string

param tags object = {}

resource privateDnsZones 'Microsoft.Network/privateDnsZones@2020-06-01' = [for z in dnsZones: {
  name: z
  location: 'global'
  properties: {}
}]

module dplVNetLinks 'helpers/vnetLink.bicep' = [for (zoneName, idx) in dnsZones: {
  name: 'dpl-${prefix}-link${idx}'
  params: {
    dnsZoneName: privateDnsZones[idx].name
    vnetLinks: vnetLinks
    tags: tags
  }
}]
