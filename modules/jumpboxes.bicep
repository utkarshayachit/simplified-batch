param location string = resourceGroup().location
@metadata({
  group: 'name of the vnet group'
  name: 'name of the vnet resource'
  subnet: 'name of the subnet'
})
param vnet object

@minLength(4)
@maxLength(20)
@description('Username for both the Linux and Windows VM. Must only contain letters, numbers, hyphens, and underscores and may not start with a hyphen or number. Only needed when providing deployVirtualMachines=true.')
param adminUsername string = 'azureadmin'

@secure()
// @minLength(12) -- Ideally we'd have this here, but to support the multiple varients we will remove it.
@maxLength(70)
@description('Password for both the Linux and Windows VM. Password must have 3 of the following: 1 lower case character, 1 upper case character, 1 number, and 1 special character. Must be at least 12 characters. Only needed when providing deployVirtualMachines=true.')
param adminPassword string

@description('Log Analytics Workspace id; if empty, analytics are dsiabled.')
param logAnalyticsWorkspaceId string = ''

param tags object = {}

resource virtualNetwork 'Microsoft.Network/virtualNetworks@2022-01-01' existing = {
  name: vnet.name
  scope: resourceGroup(vnet.group)
}

resource subnet 'Microsoft.Network/virtualNetworks/subnets@2022-05-01' existing = {
  name: vnet.subnet
  parent: virtualNetwork
}

@description('The private Network Interface Card for the linux VM.')
resource nicVmLinux 'Microsoft.Network/networkInterfaces@2022-01-01' = {
  name: 'nic-vm-${location}-linux'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'default'
        properties: {
          subnet: {
            id: subnet.id
          }
          privateIPAllocationMethod: 'Dynamic'
        }
      }
    ]
    enableAcceleratedNetworking: true
  }
  tags: tags
}

resource nicVmLinux_diagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (logAnalyticsWorkspaceId != '') {
  scope: nicVmLinux
  name: 'to-hub-la'
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

var vmName = 'vm-${location}-linux'

@description('A basic Linux virtual machine.')
resource vmLinux 'Microsoft.Compute/virtualMachines@2022-03-01' = {
  name: vmName
  location: location
  properties: {
    hardwareProfile: {
      vmSize: 'Standard_D2ds_v4'
    }
    storageProfile: {
      osDisk: {
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'Standard_LRS'
        }
        caching: 'ReadOnly'
        diffDiskSettings: {
          option: 'Local'
          placement: 'CacheDisk'
        }
        deleteOption: 'Delete'
      }
      imageReference: {
        publisher: 'canonical'
        offer: '0001-com-ubuntu-server-jammy'
        sku: '22_04-lts-gen2'
        version: 'latest'
      }
      dataDisks: []
    }
    diagnosticsProfile: {
      bootDiagnostics: {
        enabled: true
        storageUri: null
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nicVmLinux.id
          properties: {
            deleteOption: 'Delete'
            primary: true
          }
        }
      ]
    }
    osProfile: {
      computerName: vmName
      adminUsername: adminUsername
      adminPassword: adminPassword
      customData: loadFileAsBase64('helpers/linux-cloud-init.yaml')
      linuxConfiguration: {
        disablePasswordAuthentication: false
        patchSettings: {
          patchMode: 'ImageDefault'
          assessmentMode: 'ImageDefault'
        }
      }
    }
    priority: 'Regular'
  }
  
  tags: tags
}
