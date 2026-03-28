set shell := ["bash", "-euo", "pipefail", "-c"]

drop-local-db:
    direnv exec . bash -lc 'psql -h "$PGHOST" -p "$PGPORT" postgres -v ON_ERROR_STOP=1 -c "DROP DATABASE IF EXISTS app WITH (FORCE);"'

create-local-db:
    direnv exec . bash -lc 'psql -h "$PGHOST" -p "$PGPORT" postgres -v ON_ERROR_STOP=1 -c "CREATE DATABASE app;"'

reset-local-db:
    direnv exec . bash -lc 'psql -h "$PGHOST" -p "$PGPORT" postgres -v ON_ERROR_STOP=1 -c "DROP DATABASE IF EXISTS app WITH (FORCE);" && psql -h "$PGHOST" -p "$PGPORT" postgres -v ON_ERROR_STOP=1 -c "CREATE DATABASE app;"'

format-haskell:
    direnv exec . ./scripts/format-haskell.sh

check-haskell-format:
    direnv exec . ./scripts/check-haskell-format.sh

install-hooks:
    direnv exec . ./scripts/install-hooks.sh

deploy:
    direnv exec . ./scripts/workflows/deploy.sh
