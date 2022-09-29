@description('location where all resources should be deployed')
param location string = resourceGroup().location

param prefix string = uniqueString(resourceGroup().id, deployment().name)

@minLength(4)
@maxLength(63)
@description('name for the workspace; valid chars are alphanum and hyphen (except start/end)')
param workspaceName string = '${prefix}-wks'

param tags object = {}

@allowed([
  'CapacityReservation'
  'Free'
  'LACluster'
  'PerGB2018'
  'PerNode'
  'Premium'
  'Standalone'
  'Standard'
])
param workspaceSkuName string = 'PerGB2018'

param appInsightsName string = '${prefix}-appinsights'

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2020-10-01' = {
  name: workspaceName
  location: location
  properties: {
    sku: {
      name: workspaceSkuName
    }
  }
  tags: tags
}

resource appInsightsComponents 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsName 
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalyticsWorkspace.id
  }
  tags: tags
}

output logAnalyticsWorkspace object = {
  name: logAnalyticsWorkspace.name
  id: logAnalyticsWorkspace.id
}

output appInsights object = {
  name: appInsightsComponents.name
}
