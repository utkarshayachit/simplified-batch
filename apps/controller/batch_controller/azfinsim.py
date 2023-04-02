import argparse
import math
import os.path

from . import utils

def get_parser():
    parser = argparse.ArgumentParser(description='FinTech Risk Simulator')
    subparsers = parser.add_subparsers(title='command', description='valid commands')

    poolParser = subparsers.add_parser('pool', help='pool operations')
    poolParser.add_argument('-e', '--batch-endpoint',
        type=str, help='batch account endpoint [REQUIRED]', required=True)
    poolParser.add_argument('-i', '--info', action='store_true', help='print pool information')
    poolParser.add_argument('-r','--resize', type=int, help='resize pool', metavar='SIZE', default=-1)
    poolParser.set_defaults(command_execute=execute_pool)

    cacheParser = subparsers.add_parser('cache', help='cache operations')
    cacheParser.add_argument('-e', '--batch-endpoint',
        type=str, help='batch account endpoint [REQUIRED]', required=True)
    cacheParser.add_argument('-c','--container-registry-name',type=str, help='container registry url [REQUIRED]', required=True)
    cacheParser.add_argument('-t','--tasks', type=int, help='total number of tasks', default=1)
    cacheParser.add_argument('-s','--start-trade', type=int, help='start trade number', default=0)
    cacheParser.add_argument('-w','--trade-window', type=int, help='trade window i.e. total number of trades', default=0)
    cacheParser.set_defaults(command_execute=execute_cache)

    jobParser = subparsers.add_parser('job', help='job operations')
    jobParser.add_argument('-e', '--batch-endpoint',
        type=str, help='batch account endpoint [REQUIRED]', required=True)
    jobParser.add_argument('-c','--container-registry-name',type=str, help='container registry url [REQUIRED]', required=True)
    jobParser.add_argument('-t','--tasks', type=int, help='total number of tasks', default=1)
    jobParser.add_argument('-s','--start-trade', type=int, help='start trade number', default=0)
    jobParser.add_argument('-w','--trade-window', type=int, help='trade window i.e. total number of trades', default=0)
    jobParser.add_argument('-a','--algorithm', choices=['deltavega', 'pvonly'], default='deltavega', help='pricing algorithm')
    jobParser.add_argument("--failure", type=float, default=0.0, help="inject random task failure with this probability (default: 0.0)")
    jobParser.set_defaults(command_execute=execute_job)

    workflowParser = subparsers.add_parser('workflow', help='workflow operations')
    workflowParser.add_argument('-e', '--batch-endpoint',
        type=str, help='batch account endpoint [REQUIRED]', required=True)
    workflowParser.add_argument('-c','--container-registry-name',type=str, help='container registry url [REQUIRED]', required=True)
    workflowParser.add_argument('-t','--tasks', type=int, help='total number of tasks', default=1)
    workflowParser.add_argument('-s','--start-trade', type=int, help='start trade number', default=0)
    workflowParser.add_argument('-w','--trade-window', type=int, help='trade window i.e. total number of trades', default=0)
    workflowParser.add_argument('-a','--algorithm', choices=['deltavega', 'pvonly'], default='deltavega', help='pricing algorithm')
    workflowParser.add_argument("--failure", type=float, default=0.0, help="inject random task failure with this probability (default: 0.0)")
    workflowParser.set_defaults(command_execute=execute_workflow)

    cacheFSParser = subparsers.add_parser('cache-fs', help='file cache operations')
    cacheFSParser.add_argument('-e', '--batch-endpoint',
        type=str, help='batch account endpoint [REQUIRED]', required=True)
    cacheFSParser.add_argument('-c','--container-registry-name',type=str, help='container registry url [REQUIRED]', required=True)
    cacheFSParser.add_argument('-w','--trade-window', type=int, help='trade window i.e. total number of trades', default=0)
    cacheFSParser.add_argument('--file', type=str, help='file name', default='trades.csv')
    cacheFSParser.set_defaults(command_execute=execute_cache_fs)

    jobFSParser = subparsers.add_parser('job-fs', help='file job operations')
    jobFSParser.add_argument('-e', '--batch-endpoint',
        type=str, help='batch account endpoint [REQUIRED]', required=True)
    jobFSParser.add_argument('-c','--container-registry-name',type=str, help='container registry url [REQUIRED]', required=True)
    jobFSParser.add_argument('-a','--algorithm', choices=['deltavega', 'pvonly'], default='deltavega', help='pricing algorithm')
    jobFSParser.add_argument("--failure", type=float, default=0.0, help="inject random task failure with this probability (default: 0.0)")
    jobFSParser.add_argument('--file', type=str, help='file name', default='trades.csv')
    jobFSParser.set_defaults(command_execute=execute_job_fs)

    workflowFSParser = subparsers.add_parser('workflow-fs', help='file workflow operations')
    workflowFSParser.add_argument('-e', '--batch-endpoint',
        type=str, help='batch account endpoint [REQUIRED]', required=True)
    workflowFSParser.add_argument('-c','--container-registry-name',type=str, help='container registry url [REQUIRED]', required=True)
    workflowFSParser.add_argument('-t','--tasks', type=int, help='total number of tasks', default=1)
    workflowFSParser.add_argument('-w','--trade-window', type=int, help='trade window i.e. total number of trades', default=1000)
    workflowFSParser.add_argument('-a','--algorithm', choices=['deltavega', 'pvonly'], default='deltavega', help='pricing algorithm')
    workflowFSParser.add_argument("--failure", type=float, default=0.0, help="inject random task failure with this probability (default: 0.0)")
    workflowFSParser.add_argument('--file', type=str, help='file name', default='trades.csv')
    workflowFSParser.set_defaults(command_execute=execute_workflow_fs)


    return parser

def task_command_line_generator(args):
    command = '-m azfinsim.azfinsim --config /opt/secrets/config.json --start-trade {start} --trade-window {delta} --failure {failure} --algorithm {algorithm}'
    command_synthetic = ' --delay-start {delay_start} --mem-usage {mem_usage} --task-duration {task_duration}'

    delta = args.trade_window // args.tasks
    assert delta >= 0

    counter = 0
    for start in range(args.start_trade, args.start_trade + args.trade_window,  delta):
        cmd = command.format(start=start, delta=delta, algorithm=args.algorithm,
            failure=args.failure)
        if args.algorithm == 'synthetic':
            cmd + command_synthetic.format(delay_start=args.delay_start, mem_usage=args.mem_usage, task_duration=args.task_duration)
        yield cmd
        counter += 1

def populate_command_line_generator(args):
    command = '-m azfinsim.generator --config /opt/secrets/config.json --start-trade {start} --trade-window {delta}'

    delta = args.trade_window // args.tasks
    assert delta >= 0

    counter = 0
    for start in range(args.start_trade, args.start_trade + args.trade_window,  delta):
        cmd = command.format(start=start, delta=delta)
        yield cmd
        counter += 1


def execute_pool(args)->None:
    if args.resize >= 0:
        utils.pool_resize(endpoint=args.batch_endpoint, pool_id='azfinsim-pool', targetSize=args.resize)
    else:
        utils.print_pool_info(endpoint=args.batch_endpoint, pool_id='azfinsim-pool')

def execute_job(args)->None:
    utils.submit_job(endpoint=args.batch_endpoint, pool_id='azfinsim-pool',
        num_tasks=args.tasks, task_command_lines=task_command_line_generator(args),
        task_container_image='{}.azurecr.io/azfinsim/azfinsim:latest'.format(args.container_registry_name),
        container_run_options='-v /opt/azfinsim-secrets:/opt/secrets',
        job_id_prefix='azfinsim')

def execute_cache(args)->None:
    utils.submit_job(endpoint=args.batch_endpoint, pool_id='azfinsim-pool',
        num_tasks=args.tasks, task_command_lines=populate_command_line_generator(args),
        task_container_image='{}.azurecr.io/azfinsim/azfinsim:latest'.format(args.container_registry_name),
        container_run_options='-v /opt/azfinsim-secrets:/opt/secrets',
        job_id_prefix='cache')

def execute_workflow(args)->None:
    # create tasks for generator
    gen_tasks = utils.create_tasks(task_command_lines=populate_command_line_generator(args),
                task_container_image='{}.azurecr.io/azfinsim/azfinsim:latest'.format(args.container_registry_name),
                container_run_options='-v /opt/azfinsim-secrets:/opt/secrets',
                task_id_prefix='generator')

    # create tasks for pricing
    pricing_tasks = utils.create_tasks(task_command_lines=task_command_line_generator(args),
                task_container_image='{}.azurecr.io/azfinsim/azfinsim:latest'.format(args.container_registry_name),
                container_run_options='-v /opt/azfinsim-secrets:/opt/secrets',
                task_id_prefix='pricing',
                get_dependencies=lambda idx: [gen_tasks[idx].id])

    utils.submit_workflow(endpoint=args.batch_endpoint, pool_id='azfinsim-pool',
        tasks=gen_tasks + pricing_tasks,
        job_id_prefix='workflow')

def cache_fs_command_lines(args):
    task_cmd = f'-m azfinsim.generator --config /opt/secrets/config.json --trade-window {args.trade_window} ' + \
               f'--cache-type filesystem --cache-path /mnt/batch/tasks/fsmounts/trades/{args.file}'
    return [task_cmd]

def execute_cache_fs(args)->None:
    utils.submit_job(endpoint=args.batch_endpoint, pool_id='azfinsim-pool',
        num_tasks=1, task_command_lines=cache_fs_command_lines(args),
        task_container_image='{}.azurecr.io/azfinsim/azfinsim:latest'.format(args.container_registry_name),
        container_run_options='-v /opt/azfinsim-secrets:/opt/secrets',
        job_id_prefix='cache-fs',
        elevatedUser=True)

def execute_fs_command_lines_generator(args):
    name, ext = os.path.splitext(args.file)
    for i in range(args.tasks):
        task_cmd = f'-m azfinsim.azfinsim --config /opt/secrets/config.json ' + \
                   f'--cache-type filesystem --cache-path /mnt/batch/tasks/fsmounts/trades/{name}.{i}{ext} ' + \
                   f'--algorithm {args.algorithm} --failure {args.failure}'
        yield task_cmd

def execute_job_fs(args)->None:
    args.tasks = 1
    utils.submit_job(endpoint=args.batch_endpoint, pool_id='azfinsim-pool',
        num_tasks=1, task_command_lines=execute_fs_command_lines_generator(args),
        task_container_image='{}.azurecr.io/azfinsim/azfinsim:latest'.format(args.container_registry_name),
        container_run_options='-v /opt/azfinsim-secrets:/opt/secrets',
        job_id_prefix='azfinsim-fs',
        elevatedUser=True)

def execute_workflow_fs(args)->None:
    work_dir = f'tmp-{utils.unique_id()}' # create a unique work directory

    # create 1 task for generator
    gen_tasks = utils.create_tasks(task_command_lines=cache_fs_command_lines(args),
                task_container_image='{}.azurecr.io/azfinsim/azfinsim:latest'.format(args.container_registry_name),
                container_run_options='-v /opt/azfinsim-secrets:/opt/secrets',
                task_id_prefix='generator-fs',
                elevatedUser=True)

    # create 1 task for splitting
    split_tasks = utils.create_tasks(task_command_lines=split_fs_command_lines(args, work_dir),
                task_container_image='{}.azurecr.io/azfinsim/azfinsim:latest'.format(args.container_registry_name),
                container_run_options='-v /opt/azfinsim-secrets:/opt/secrets',
                task_id_prefix='split-fs',
                get_dependencies=lambda _: [gen_tasks[0].id],
                elevatedUser=True)

    # create n task for pricing
    s = args.file
    args.file = f'{work_dir}/{args.file}'
    pricing_tasks = utils.create_tasks(task_command_lines=execute_fs_command_lines_generator(args),
                task_container_image='{}.azurecr.io/azfinsim/azfinsim:latest'.format(args.container_registry_name),
                container_run_options='-v /opt/azfinsim-secrets:/opt/secrets',
                task_id_prefix='pricing-fs',
                get_dependencies=lambda idx: [split_tasks[0].id],
                elevatedUser=True)
    args.file = s

    # create 1 task for merging
    merge_tasks = utils.create_tasks(task_command_lines=merge_fs_command_lines(args, work_dir),
                task_container_image='{}.azurecr.io/azfinsim/azfinsim:latest'.format(args.container_registry_name),
                container_run_options='-v /opt/azfinsim-secrets:/opt/secrets',
                task_id_prefix='merge-fs',
                get_dependencies=lambda _: [t.id for t in pricing_tasks],
                elevatedUser=True)

    utils.submit_workflow(endpoint=args.batch_endpoint, pool_id='azfinsim-pool',
        tasks=gen_tasks + split_tasks + pricing_tasks + merge_tasks,
        job_id_prefix='workflow-fs')

def split_fs_command_lines(args, work_dir):
    tasks = args.tasks
    num_trades = args.trade_window
    trades_per_file = math.ceil(num_trades / tasks)
    task_cmd = f'-m azfinsim.split --config /opt/secrets/config.json --trade-window {trades_per_file} ' + \
               f'--cache-path /mnt/batch/tasks/fsmounts/trades/{args.file} ' \
               f'--output-path /mnt/batch/tasks/fsmounts/trades/{work_dir}'
    return [task_cmd]

def merge_fs_command_lines(args, work_dir):
    name, ext = os.path.splitext(args.file)
    task_cmd = f'-m azfinsim.concat --config /opt/secrets/config.json ' + \
               f'--cache-type filesystem --cache-path /mnt/batch/tasks/fsmounts/trades/{work_dir}/{name}.[0-9]*{ext} ' + \
               f'--output-path /mnt/batch/tasks/fsmounts/trades/{name}.result{ext}'
    return [task_cmd]

def execute(args)->None:
    if hasattr(args, 'command_execute'):
        args.command_execute(args)
    else:
        print('missing required command')

if __name__ == '__main__':
    parser = get_parser()
    execute(parser.parse_args())
