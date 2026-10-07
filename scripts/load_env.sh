# Source this (". scripts/load_env.sh") to export the settings in .env that have a value.
# Empty lines in .env (copied from .env.example) are skipped, so they never blank out a
# setting the shell already has (e.g. JAC_BUN on CPUs without AVX2, JI-002).
if [[ -f .env ]]; then
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%$'\r'}"
        [[ -z "$line" || "$line" == \#* || "$line" != *=* ]] && continue
        name="${line%%=*}"
        value="${line#*=}"
        value="${value%%[[:space:]]#*}"
        value="${value%"${value##*[![:space:]]}"}"
        value="${value#\"}"; value="${value%\"}"
        [[ -z "$value" ]] && continue
        export "$name=$value"
    done < .env
fi
