/**
  Deploy private endpoints for given endpoints. This also updates
  private DNS zone name records using privateDnsZoneGroups.
*/

@description('location for all resources')
param location string = resourceGroup().location

@description('the subnet under which to deploy the private endpoints')
@metadata({
  group: 'name of the vnet group'
  name: 'name of the vnet resource'
  subnet: 'name of the subnet'
})
param vnet object

// @allowed([
//   {
//     name: ''
//     group: ''
//     privateLinkServiceId: ''
//     groupIds: []
//     privateDnsZoneName: ''
//   }
// ])
@description('array of endpoints to deploy. Each endpoint is defined by an object with necessary properties')
param endpoints array

@description('name of the group under which all private DNS zones are defined')
param dnsZoneGroupName string

// note: we ensure that we deploy endpoints in the same resource group as the resource,
// if possible, to make cleanup easier.
module dplEndpoints 'helpers/privateEndpoint.bicep' = [for (item, idx) in endpoints: {
  name: '${deployment().name}-${item.name}-${idx}-eps'
  scope: contains(item, 'group') ? resourceGroup(item.group) : resourceGroup()
  params: {
    name: '${item.name}-${idx}-pl'
    location: location

    privateDnsZone: {
      group: dnsZoneGroupName
      name: item.privateDnsZoneName
    } 
    privateLinkServiceId: item.privateLinkServiceId
    groupIds: item.groupIds
    vnet: vnet
  }
}]
