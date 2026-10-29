# Market (bundled copy)

Market is developed in its own repository, github.com/tsryzenstech/astra-market,
whose GitHub Actions publish a release (and an update on Market itself) whenever
the app or its server address (config.json) changes. This directory is the copy
built into astraOS images; refresh it with:

    python3 tools/market/update.py ../astra-market
