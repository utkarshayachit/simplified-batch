from azure.batch import BatchServiceClient, models
from azure.identity import DefaultAzureCredential

from . import azure_identity_credential_adapter


def login(endpoint):
    credentials = DefaultAzureCredential()
    wrapper = azure_identity_credential_adapter.AzureIdentityCredentialAdapter(credentials, resource_id='https://batch.core.windows.net/')
    batch_client = BatchServiceClient(wrapper, batch_url="https://{}".format(endpoint))
    return batch_client

def unique_id():
    import time
    return time.strftime("%Y%m%d-%H%M%S")

def pool_resize(endpoint, pool_id, targetSize):
    """Resize a pool"""
    client = login(endpoint)
    client.pool.resize(pool_id, models.PoolResizeParameter(target_dedicated_nodes=targetSize))

def print_pool_info(endpoint, pool_id):
    """Print information about a pool"""
    client = login(endpoint)
    info = client.pool.get(pool_id=pool_id)
    print("""=============================================
{id} (display name: '{display_name}')
=============================================
State: {state} (allocation state: {allocation_state})
Current Dedicated Size: {size}
Current Spot Size: {spot_size}
""".format(id=info.id, 
    display_name=info.display_name if info.display_name else '<n/a>',
    state=info.state, size=info.current_dedicated_nodes,
    spot_size=info.current_low_priority_nodes,
    allocation_state=info.allocation_state))

def submit_job(endpoint, pool_id, num_tasks, task_command_lines, task_container_image=None,
    container_run_options=None, job_id_prefix='job',
    elevatedUser=False):
    """submit a new job"""
    client = login(endpoint)
    job_id = "{}-{}".format(job_id_prefix, unique_id())

    pool_info=models.PoolInformation(pool_id=pool_id)
    client.job.add(models.JobAddParameter(id=job_id, pool_info=pool_info))

    user = models.UserIdentity(\
        auto_user=models.AutoUserSpecification(scope='pool',
            elevation_level='admin')) if elevatedUser else None

    task_container_settings = models.TaskContainerSettings(image_name=task_container_image,
        container_run_options=container_run_options) if task_container_image else None
    tasks = [models.TaskAddParameter(id="task_{}".format(index),
                command_line=cmd,
                user_identity=user,
                container_settings=task_container_settings) for index, cmd in enumerate(task_command_lines)]
    res = client.task.add_collection(job_id, tasks)
    # print(res)

    # once tasks are added to job, update the job to terminate the job
    # once all tasks complete
    client.job.update(job_id=job_id,
        job_update_parameter=models.JobUpdateParameter(on_all_tasks_complete='terminateJob',
        pool_info=pool_info))

    return {
        'job_id': job_id,
        'task_ids': ['task_{}'.format(index) for index in range(num_tasks)],
        'pool_id': pool_id,
    }