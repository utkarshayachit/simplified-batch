from azure.batch import BatchServiceClient, models
from azure.identity import DefaultAzureCredential

from . import azure_identity_credential_adapter


def login(endpoint):
    credentials = DefaultAzureCredential()
    wrapper = azure_identity_credential_adapter.AzureIdentityCredentialAdapter(credentials, resource_id='https://batch.core.windows.net/')
    batch_client = BatchServiceClient(wrapper, batch_url="https://{}".format(endpoint))
    return batch_client

def pool_resize(endpoint, pool_id, targetSize):
    """Resize a pool"""
    client = login(endpoint)
    client.pool.resize(pool_id, models.PoolResizeParameter(target_dedicated_nodes=targetSize))
