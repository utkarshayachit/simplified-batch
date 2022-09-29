from azure.identity import DefaultAzureCredential
from azure.keyvault.secrets import SecretClient


def login(kv_uri):
    return SecretClient(vault_url=kv_uri, credential=DefaultAzureCredential())

def read_secrets(kv_uri, key=None):
    client = login(kv_uri)
    if key is None:
        return dict([ (secret.name, client.get_secret(secret.name).value,) \
                   for secret in client.list_properties_of_secrets()])
    return client.get_secret(key).value