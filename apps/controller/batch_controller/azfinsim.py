import argparse

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

    jobParser = subparsers.add_parser('job', help='job operations')
    jobParser.add_argument('-e', '--batch-endpoint',
        type=str, help='batch account endpoint [REQUIRED]', required=True)
    jobParser.add_argument('-c','--container-registry-name',type=str, help='container registry url [REQUIRED]', required=True)
    jobParser.add_argument('-s','--start-trade', type=int, help='start trade number', default=0)
    jobParser.add_argument('-w','--trade-window', type=int, help='trade window i.e. total number of trades', default=0)
    jobParser.add_argument('-t','--tasks', type=int, help='total number of tasks', default=1)
    jobParser.add_argument('-a','--algorithm', choices=['deltavega', 'pvonly', 'synthetic'], default='deltavega', help='pricing algorithm')
    jobParser.add_argument("--failure", type=float, default=0.0, help="inject random task failure with this probability (default: 0.0)")

    tg = jobParser.add_argument_group('synthetic', 'arguments with algorithm=\'synthetic\'')
    tg.add_argument("-d", "--delay-start", type=int, default=0, help="delay startup time in seconds (default: 0)")
    tg.add_argument("-m", "--mem-usage", type=int, default=16, help="memory usage for task in MB (default: 16)")
    tg.add_argument("--task-duration", type=int, default=20, help="task duration in milliseconds (default: 20)")

    jobParser.set_defaults(command_execute=execute_job)

    cacheParser = subparsers.add_parser('cache', help='cache operations')
    cacheParser.add_argument('-e', '--batch-endpoint',
        type=str, help='batch account endpoint [REQUIRED]', required=True)
    cacheParser.add_argument('-c','--container-registry-name',type=str, help='container registry url [REQUIRED]', required=True)
    cacheParser.add_argument('-s','--start-trade', type=int, help='start trade number', default=0)
    cacheParser.add_argument('-w','--trade-window', type=int, help='trade window i.e. total number of trades', default=0)
    cacheParser.add_argument('-t','--tasks', type=int, help='total number of tasks', default=1)
    cacheParser.set_defaults(command_execute=execute_cache)
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

def execute(args)->None:
    if hasattr(args, 'command_execute'):
        args.command_execute(args)
    else:
        print('missing required command')

if __name__ == '__main__':
    parser = get_parser()
    execute(parser.parse_args())