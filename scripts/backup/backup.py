"""Encrypted application-schema backup; restore only to an empty scratch DB."""
import argparse
import base64
import hashlib
import json
import os
import re
from pathlib import Path
import subprocess
import tempfile
from datetime import datetime, timezone
from urllib.parse import urlsplit, unquote

from cryptography.fernet import Fernet


def pg_env(url, *, scratch=False):
    parsed = urlsplit(url.replace('postgresql+psycopg://', 'postgresql://', 1))
    if parsed.scheme not in ('postgres', 'postgresql') or not parsed.hostname:
        raise ValueError('Invalid PostgreSQL URL')
    return {**os.environ, 'PGHOST': parsed.hostname, 'PGPORT': str(parsed.port or 5432),
            'PGUSER': unquote(parsed.username or ''), 'PGPASSWORD': unquote(parsed.password or ''),
            'PGDATABASE': unquote(parsed.path.lstrip('/')), 'PGCONNECT_TIMEOUT': '20',
            'PGSSLMODE': 'disable' if scratch and parsed.hostname in ('localhost', '127.0.0.1', 'restore') else 'require'}


def run(args, env):
    result = subprocess.run(args, env=env, capture_output=True)
    if result.returncode:
        message = result.stderr.decode(errors='replace')
        if 'schema "public" already exists' in message:
            raise RuntimeError('Restore target already contains the public schema')
        # Database errors can contain clinical values. Keep logs free of them.
        raise RuntimeError(f'{args[0]} failed (exit {result.returncode}); no data logged')
    return result.stdout


def restore_check(dump, field_key, env):
    tables = run(['psql', '-X', '-At', '-v', 'ON_ERROR_STOP=1', '-c',
                  "SELECT count(*) FROM information_schema.tables WHERE table_schema='public' AND table_type='BASE TABLE'"], env)
    if int(tables.strip()) != 0:
        raise RuntimeError('Restore target must be empty; refusing to overwrite data')
    # A freshly created PostgreSQL database already has the public namespace.
    # Keep it and restore its contents; do not drop any destination objects.
    toc = run(['pg_restore', '--list', str(dump)], env).decode()
    entries = '\n'.join(line for line in toc.splitlines()
                        if not re.search(r'\bSCHEMA - public\b', line))
    listing = dump.with_suffix('.list')
    listing.write_text(entries + '\n')
    run(['pg_restore', '--exit-on-error', '--single-transaction', '--no-owner', '--no-privileges',
         '--use-list', str(listing), '--dbname', env['PGDATABASE'], str(dump)], env)
    run(['psql', '-X', '-At', '-v', 'ON_ERROR_STOP=1', '-c',
         'SELECT version_num FROM alembic_version; SELECT count(*) FROM users; SELECT count(*) FROM daily_checkins;'], env)
    # Validate the recovery key against an encrypted field if any account exists.
    names = run(['psql', '-X', '-At', '-v', 'ON_ERROR_STOP=1', '-c',
                 'SELECT full_name FROM users LIMIT 1'], env).strip()
    if names:
        Fernet(field_key.encode()).decrypt(names)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('mode', choices=['create', 'verify'])
    parser.add_argument('file', type=Path)
    args = parser.parse_args()
    cipher = Fernet(os.environ['BACKUP_ENCRYPTION_KEY'].encode())
    with tempfile.TemporaryDirectory(prefix='neuremia-backup-') as directory:
        dump = Path(directory) / 'database.dump'
        if args.mode == 'create':
            key = os.environ['NEUREMIA_FIELD_ENCRYPTION_KEY']
            Fernet(key.encode())
            run(['pg_dump', '--format=custom', '--schema=public', '--no-owner', '--no-privileges',
                 '--file', str(dump)], pg_env(os.environ['BACKUP_DATABASE_URL']))
            raw = dump.read_bytes()
            payload = {'format': 1, 'created_at': datetime.now(timezone.utc).isoformat(),
                       'sha256': hashlib.sha256(raw).hexdigest(), 'field_key': key,
                       'dump': base64.b64encode(raw).decode()}
            args.file.parent.mkdir(parents=True, exist_ok=True)
            with args.file.open('xb') as out:
                os.chmod(args.file, 0o600)
                out.write(cipher.encrypt(json.dumps(payload).encode()))
        else:
            payload = json.loads(cipher.decrypt(args.file.read_bytes()))
            if payload['format'] != 1:
                raise ValueError('Unsupported backup format')
            raw = base64.b64decode(payload['dump'], validate=True)
            if hashlib.sha256(raw).hexdigest() != payload['sha256']:
                raise ValueError('Backup checksum mismatch')
            dump.write_bytes(raw)
            if os.environ.get('RESTORE_DATABASE_URL') == os.environ.get('BACKUP_DATABASE_URL'):
                raise RuntimeError('Refusing to restore into the source database')
            restore_check(dump, payload['field_key'], pg_env(os.environ['RESTORE_DATABASE_URL'], scratch=True))
    print('Backup created' if args.mode == 'create' else 'Restore verified successfully')


if __name__ == '__main__':
    main()
