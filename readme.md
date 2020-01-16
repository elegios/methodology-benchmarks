# Parser benchmarks

```fish
source bench.fish  # load the benchmarking functions
bench              # run all benchmarks
timings            # compile all benchmark results to csv's
metrics            # compile metrics for all used sources under sources/
update_db          # clear the db, then load all csv files with timings and metrics into it
csv tool           # print all the datapoints for a single tool in csv format
results            # output all timing data for all tools as csv's in results/

compile_everything # runs timings; update_db; results
```

`bench`, `timings`, `metrics`, and `results` can take a list of
arguments for which tools (languages for `metrics`) to
benchmark/compile results for. No argument implies all.

`bench` and `metrics` are the commands that are slow (the latter
because `cloc` is moderately slow). Expected usage is thus the
following:

```fish
source bench.fish
bench
metrics
compile_everything
```

As a helper in case you want to re-run everything, run
`compile-everything bench`.

## Generating graphs

The graphs are generate using `matplotlib` and `scikit-learn` inside a jupyter lab notebook.

```
pip3 install jupyterlab
pip3 install matplotlib
pip3 install scikit-learn
jupyter lab
```

Just run the entire notebook to produce all the graphs.

## Adding stuff

To add a new project to be parsed for benchmarking, add it in the
correct folder under `sources/` (e.g. `sources/javascript`). All
files with the appropriate extension (e.g. `.js`) in any subdirectory
will be parsed.

To add a new tool, add it to the list in the beginning of `bench`,
then add a new if block for it at the end of `bench`.

To add a new language, add the directory under sources, then add a new
if block in `metrics`.
