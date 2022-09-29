import argparse
import sys

from . import azfinsim

parser = argparse.ArgumentParser(prog='batch_controller',
    description='Azure Batch controller')
parser.add_argument('-e', '--batch-endpoint',
    type=str, help='batch account endpoint', required=True)
subparsers = parser.add_subparsers(title='applications', description='valid applications')

# for each application, we add sub-parsers
azfinsimParser = subparsers.add_parser('azfinsim', help='AzFinSim: Financial Risk Simulator')
azfinsim.add_arguments(azfinsimParser)
azfinsimParser.set_defaults(execute=azfinsim.execute)

args = parser.parse_args()
if hasattr(args, 'execute'):
    args.execute(args)
