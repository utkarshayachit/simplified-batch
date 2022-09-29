import argparse

from . import keyvault_utils as kv

parser = argparse.ArgumentParser(prog='grabber', description='Azure Key Valut secrets grabber')
parser.add_argument('-u', '--key-vault-uri', help='Azure Key Vault URI', type=str, required=True)
parser.add_argument('-o', '--output', help="output file name")
parser.add_argument('-f', '--format', help='output format', choices=['json', 'pickle', 'raw'], default='raw')
parser.add_argument('-p', '--print', help='print secrets to stdout', action='store_true', default=False)
parser.add_argument('-k', '--key', help='print value for a specific secret')

args = parser.parse_args()
secrets = kv.read_secrets(args.key_vault_uri, key=args.key)

if args.format == 'json':
    import json
    data = json.dumps(secrets)
elif args.format == 'pickle':
    import pickle
    data = pickle.dumps(secrets)
elif args.format == 'raw':
    data = str(secrets)
else:
    raise RuntimeError('format not valid: {}'.format(args.format))

if args.output is None and not args.print:
    from pprint import pprint
    pprint(secrets)
if args.print:
    print(data)
if args.output:
    with open(args.output, 'w') as f:
        f.write(data)


