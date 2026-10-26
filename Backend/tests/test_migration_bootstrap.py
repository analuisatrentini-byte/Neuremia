"""Exercise the real migration chain, rather than metadata.create_all."""
import os
from pathlib import Path
import subprocess
import sys

import sqlalchemy as sa

from app.models import Base


def test_empty_database_has_all_model_columns(tmp_path):
    url = f"sqlite:///{tmp_path / 'bootstrap.db'}"
    backend = Path(__file__).resolve().parents[1]
    subprocess.run(
        [sys.executable, "-m", "alembic", "upgrade", "head"],
        cwd=backend, env={**os.environ, "DATABASE_URL": url}, check=True,
        capture_output=True, text=True,
    )
    engine = sa.create_engine(url)
    inspector = sa.inspect(engine)
    for table in Base.metadata.sorted_tables:
        assert inspector.has_table(table.name), table.name
        actual = {column["name"] for column in inspector.get_columns(table.name)}
        assert set(table.columns.keys()) <= actual, table.name
    engine.dispose()
