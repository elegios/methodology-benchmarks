function bench
    set -l tools ocamlc rustc node
    if test (count $argv) -eq 0
        set argv $tools
    end

    if contains ocamlc -- $argv
        echo Benchmarking ocamlc
        set -l info (string trim (ocamlc --version 2>&1))
        for f in (find sources/ocaml -type f -name "*.ml")
            _run_bench "timings/ocamlc/"(echo $f | cut -d'/' -f2-)".result" $info ocamlc -stop-after parsing $f
        end
    end

    if contains rustc -- $argv
        echo "Benchmarking rustc (using rustup to set to nightly, will try to revert after)"
        set -l prevchaincomplete (rustup show active-toolchain)
        echo "Previous toolchain: "$prevchaincomplete
        set -l prevchain (echo $prevchaincomplete | grep -oE "stable|beta|nightly")
        rustup default nightly 2> /dev/null > /dev/null

        set -l info (string trim (rustc --version 2>&1))
        for f in (find sources/rust -type f -name "*.rs")
            _run_bench "timings/rustc/"(echo $f | cut -d'/' -f2-)".result" $info rustc -Z parse-only $f
        end

        if test -n "$prevchain"
            rustup default $prevchain 2> /dev/null > /dev/null
            if test $prevchaincomplete = (rustup show active-toolchain)
                echo "Successfully restored previous toolchain."
            else
                echo "Failed to restore toolchain to: "$prevchaincomplete
            end
        else
            echo "Don't know how to switch back to the previous toolchain."
            echo "rustup show active-toolchain previously printed:"
            echo $prevchaincomplete
        end
    end

    if contains node -- $argv
        echo Benchmarking node
        set -l info (string trim (node --version 2>&1))
        for f in (find sources/javascript -type f -name "*.js")
            _run_bench "timings/node/"(echo $f | cut -d'/' -f2-)".result" $info node --check $f
        end
    end
end

function timings
    set -l tools (ls timings | tr -d '/')
    if test (count $argv) -eq 0
        set argv $tools
    end

    for tool in $tools
        echo "Compiling timing data for "$tool
        echo -n "" > "timings/"$tool"/times.csv"
        for f in (find "timings/"$tool -type f -name "*.result")
            tail -n 2 $f | tr -d '\n' | sed 's/^\([0-9]\+\),\([0-9]\+\) seconds time elapsed.*( +- *\([0-9]\+\),\([0-9]\+\).*$/\1.\2,\3.\4/' | sed "s#^\(.*\)#"$tool","(echo $f | cut -d'/' -f3- | sed 's/.result$//')",\1\n#" >> "timings/"$tool"/times.csv"
        end
    end
end

function metrics
    set -l languages (ls sources | tr -d '/')
    if test (count $argv) -eq 0
        set argv $languages
    end
    if contains ocaml -- $argv
        echo "Getting metrics for ocaml"
        _metrics_csv "ocaml" "*.ml" > metrics/ocaml.csv
        _cloc_csv "ocaml" "OCaml" > metrics/ocaml_cloc.csv
    end
    if contains rust -- $argv
        echo "Getting metrics for rust"
        _metrics_csv "rust" "*.rs" > metrics/rust.csv
        _cloc_csv "rust" "Rust" > metrics/rust_cloc.csv
    end
    if contains javascript -- $argv
        echo "Getting metrics for javascript"
        _metrics_csv "javascript" "*.js" > metrics/javascript.csv
        _cloc_csv "javascript" "JavaScript" > metrics/javascript_cloc.csv
    end
end

function _metrics_csv -a language ext
    for f in (find "sources/"$language -type f -name $ext)
        set -l src (echo -n $f | cut -d'/' -f2-)
        # print order: lines characters bytes
        set -l wcmetrics (wc --bytes --chars --lines $f | tr -d '\n' | sed 's/^[^0-9]*\([0-9]*\)[^0-9]*\([0-9]*\)[^0-9]*\([0-9]*\).*/\3,\2,\1/')
        echo $src","$wcmetrics
    end
end

function _cloc_csv -a language cloc_lang
    cloc sources/$language --by-file --csv --quiet --include-lang=$cloc_lang | tail -n +3 | sed "s#^"$cloc_lang",sources/##"
end

function update_db
    _update_db_helper | sqlite3 data
end

function _update_db_helper
    echo "drop table if exists timings;"
    echo "drop table if exists metrics;"
    echo "drop table if exists cloc;"
    echo "create table timings(tool TEXT, file TEXT, time REAL, stddev REAL);"
    echo "create table metrics(file TEXT, bytes INTEGER, chars INTEGER, lines INTEGER);"
    echo "create table cloc(file TEXT, blank INTEGER, comment INTEGER, code INTEGER);"

    echo ".mode csv"
    for f in (find timings -type f -name "*.csv")
        echo ".import "$f" timings"
    end
    for f in (find metrics -type f -name "*.csv")
        if echo $f | grep --quiet -E '_cloc.csv$'
            echo ".import "$f" cloc"
        else
            echo ".import "$f" metrics"
        end
    end
end

function csv -a tool
    _csv_helper $tool | sqlite3 data
end

function results
    set -l tools (ls timings | tr -d '/')
    if test (count $argv) -eq 0
        set argv $tools
    end

    for tool in $argv
        csv $tool > "results/"$tool".csv"
    end
end

function compile_everything -a bench
    if test -n "$bench"
        bench
        metrics
    end
    timings
    update_db
    results
end

function _csv_helper -a tool
    echo ".mode csv"
    echo ".header on"
    echo "select distinct bytes,chars,metrics.lines,cloc.code,time,stddev,timings.file from timings join metrics on timings.file = metrics.file join cloc on timings.file = cloc.file where tool = '"$tool"';"
end

function _run_bench -a file info
    set -l warming 5
    set -l runs 50

    set -l stdout (mktemp)
    set -l stderr (mktemp)

    set --erase argv[1..2]
    if not perf stat --null -o /dev/null -- $argv > $stdout 2> $stderr
        echo
        echo Failed to run benchmark to produce file '"'$file'"'
        echo "Stdout:"
        cat $stdout
        echo
        echo "Stderr:"
        cat $stderr
        rm $stdout $stderr
        return 1
    end

    mkdir -p (dirname $file)
    date > $file
    uname -a >> $file
    lshw -short >> $file 2> /dev/null
    echo "----------------------------------------------------------" >> $file
    echo $info >> $file
    echo "----------------------------------------------------------" >> $file
    cat $stdout >> $file
    echo "----------------------------------------------------------" >> $file
    cat $stderr >> $file
    echo "----------------------------------------------------------" >> $file

    set -l output (mktemp)

    perf stat --repeat $warming -o $output --null $argv > /dev/null 2> /dev/null

    perf stat --repeat $runs -o $output --null $argv > /dev/null 2> /dev/null
    string trim (tail -n 2 $output) >> $file

    rm $stdout $stderr $output

    echo -n .
end
