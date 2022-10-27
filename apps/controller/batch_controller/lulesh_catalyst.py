import argparse
from multiprocessing import pool

from . import utils

def get_parser():
    parser = argparse.ArgumentParser(description='Catalyst-enabled LULESH')
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
    jobParser.add_argument('-s', '--size', help='size of the grid (default=30)', type=int, default=30)
    jobParser.add_argument('-i', '--iterations', help='number of iterations (default=50)', type=int, default=50)
    jobParser.set_defaults(command_execute=execute_job)
 
    return parser

def execute_pool(args)->None:
    if args.resize >= 0:
        utils.pool_resize(endpoint=args.batch_endpoint, pool_id='lulesh-catalyst-pool', targetSize=args.resize)
    else:
        utils.print_pool_info(endpoint=args.batch_endpoint, pool_id='lulesh-catalyst-pool')

def execute_job(args)->None:
    cmd = '-p -s {size} -i {iterations} -x /opt/input/script.py'.format(size=args.size, iterations=args.iterations)
    utils.submit_job(endpoint=args.batch_endpoint, pool_id='lulesh-catalyst-pool',
        num_tasks=1, task_command_lines=[cmd],
        task_container_image='{}.azurecr.io/lulesh/lulesh-catalyst:latest'.format(args.container_registry_name),
        job_id_prefix='lulesh-catalyst')

def execute(args)->None:
    if hasattr(args, 'command_execute'):
        args.command_execute(args)
    else:
        print('missing required command')

if __name__ == '__main__':
    parser = get_parser()
    execute(parser.parse_args())
