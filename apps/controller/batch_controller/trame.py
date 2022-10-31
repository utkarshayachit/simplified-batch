import argparse
import datetime
import io
import time

from multiprocessing import pool
from . import utils

def get_parser():
    parser = argparse.ArgumentParser(description='trame: web visualization')
    subparsers = parser.add_subparsers(title='command', description='valid commands')

    poolParser = subparsers.add_parser('pool', help='pool operations')
    poolParser.add_argument('-e', '--batch-endpoint',
        type=str, help='batch account endpoint [REQUIRED]', required=True)
    poolParser.add_argument('-i', '--info', action='store_true', help='print pool information')
    poolParser.add_argument('-r','--resize', type=int, help='resize pool', metavar='SIZE', default=-1)
    poolParser.set_defaults(command_execute=execute_pool)

    return parser

def execute_pool(args)->None:
    if args.resize >= 0:
        utils.pool_resize(endpoint=args.batch_endpoint, pool_id='trame-pool', targetSize=args.resize)
    else:
        utils.print_pool_info(endpoint=args.batch_endpoint, pool_id='trame-pool')

def execute(args)->None:
    if hasattr(args, 'command_execute'):
        args.command_execute(args)
    else:
        print('missing required command')

if __name__ == '__main__':
    parser = get_parser()
    execute(parser.parse_args())
