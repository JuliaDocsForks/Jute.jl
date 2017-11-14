_get_iterable(global_fixtures, fx::AbstractGlobalFixture) = global_fixtures[fx]
_get_iterable(global_fixtures, fx::ConstantFixture) = setup(fx)
_get_iterable(global_fixtures, fx::LocalFixture) =
    rowmajor_product([_get_iterable(global_fixtures, param) for param in parameters(fx)]...)

get_iterable(global_fixtures) = fx -> _get_iterable(global_fixtures, fx)


struct DelayedTeardownValue
    lval :: LabeledValue
    rff :: Nullable{RunningFixtureFactory}
    subvalues :: Array{DelayedTeardownValue, 1}
end


function setup(fx::LocalFixture, lvals)
    to_release = DelayedTeardownValue[]
    processed_args = []
    for (p, lval) in zip(parameters(fx), lvals)
        if typeof(p) == LocalFixture
            dval = setup(p, lval)
            push!(to_release, dval)
            lval = dval.lval
        end
        push!(processed_args, lval.value)
    end
    lval, rff = setup(fx.ff, processed_args)
    DelayedTeardownValue(lval, rff, to_release)
end


function release(val::DelayedTeardownValue)
    if !isnull(val.rff)
        for v in val.subvalues
            release(v)
        end
        teardown(get(val.rff))
    end
end


unwrap_value(val::DelayedTeardownValue) = unwrap_value(val.lval)
unwrap_label(val::DelayedTeardownValue) = unwrap_label(val.lval)

instantiate(fx::LocalFixture, lval) = setup(fx, lval)
instantiate(fx, lval) = DelayedTeardownValue(lval, nothing, DelayedTeardownValue[])


function instantiate_global(global_fixtures, fx::GlobalFixture)

    for_teardown = RunningFixtureFactory[]

    iterables = Array{LabeledValue, 1}[_get_iterable(global_fixtures, p) for p in parameters(fx)]

    all_lvals = LabeledValue[]
    for lvals in rowmajor_product(iterables...)
        args = map(unwrap_value, lvals)
        lval, rff = setup(fx, args)

        push!(all_lvals, lval)
        if instant_teardown(rff)
            teardown(rff)
        else
            push!(for_teardown, rff)
        end
    end
    all_lvals, for_teardown
end


function run_testcases(run_options, tcs, doctest)

    global_fixtures = Dict{AbstractGlobalFixture, Array{LabeledValue, 1}}()
    gi = get_iterable(global_fixtures)
    for_teardown = DefaultDict{Int, Array{RunningFixtureFactory, 1}}(() -> RunningFixtureFactory[])

    test_outcomes = []

    progress = progress_reporter([tcinfo for (tcinfo, tc) in tcs], run_options[:verbosity], doctest)

    progress_start!(progress)

    capture_output = run_options[:capture_output] :: Bool
    fails_num = 0
    max_fails = run_options[:max_fails] :: Int
    max_fails_reached = false

    for (i, entry) in enumerate(tcs)

        tcinfo, tc = entry

        for fx in dependencies(tc)
            if !haskey(global_fixtures, fx)
                if isa(fx, RunOptionsFixture)
                    global_fixtures[fx] = [LabeledValue(run_options, "run_options")]
                else
                    lvals, ftd = instantiate_global(global_fixtures, fx)
                    global_fixtures[fx] = lvals

                    if length(ftd) > 0
                        last_usage_idx = findlast(tcs) do entry
                            _, tcc = entry
                            fx in dependencies(tcc)
                        end
                        append!(for_teardown[last_usage_idx], ftd)
                    end
                end
            end
        end


        fixture_iterables = map(gi, parameters(tc))
        iterable_permutations = rowmajor_product(fixture_iterables...)

        progress_start_testcases!(progress, tcinfo, length(iterable_permutations))

        for lvals in iterable_permutations
            dvals = map(instantiate, parameters(tc), lvals)
            args = map(unwrap_value, dvals)
            labels = map(unwrap_label, dvals)
            progress_start_testcase!(progress, tcinfo, labels)
            outcome = run_testcase(tc, args, capture_output)
            map(release, dvals)
            push!(test_outcomes, (tcinfo, labels, outcome))
            progress_finish_testcase!(progress, tcinfo, labels, outcome)

            if is_failed(outcome)
                fails_num += 1
            end

            if max_fails > 0 && fails_num == max_fails
                max_fails_reached = true
                break
            end
        end

        if haskey(for_teardown, i)
            map(teardown, for_teardown[i])
            delete!(for_teardown, i)
        end

        progress_finish_testcases!(progress, tcinfo)

        if max_fails_reached
            # Call all remaining teardowns
            for (i, rffs) in for_teardown
                map(teardown, rffs)
            end
            break
        end
    end

    progress_finish!(progress, test_outcomes)
end


function is_testcase_included(e_paths, i_paths, e_tags, i_tags, tcinfo::TestcaseInfo)
    full_tag = path_string(tcinfo)
    (
        (isnull(e_paths) || !ismatch(get(e_paths), full_tag))
        && (isnull(i_paths) || ismatch(get(i_paths), full_tag))
        && (isempty(e_tags) || isempty(intersect(e_tags, tcinfo.tags)))
        && (isempty(i_tags) || !isempty(intersect(i_tags, tcinfo.tags)))
        )
end


function filter_testcases(run_options, tcs)
    e_paths = run_options[:exclude]
    i_paths = run_options[:include_only]
    e_tags = Set(run_options[:exclude_tags])
    i_tags = Set(run_options[:include_only_tags])
    filter(p -> is_testcase_included(e_paths, i_paths, e_tags, i_tags, p[1]), tcs)
end


function runtests_internal(run_options, tcs, doctest=false)
    if run_options[:verbosity] > 0
        println("Collecting testcases...")
    end
    all_testcases = get_testcases(tcs)
    testcases = filter_testcases(run_options, all_testcases)

    if length(testcases) == 0 && run_options[:verbosity] > 0
        println("All $(length(all_testcases)) testcases were filtered out, nothing to run")
        return 0
    end

    if run_options[:verbosity] > 0
        println("Running $(length(testcases)) out of $(length(all_testcases)) testcases...")
        println("=" ^ 80)
    end
    all_successful = run_testcases(run_options, testcases, doctest)
    Int(!all_successful)
end


struct TestcaseAccumID
end


const TESTCASE_ACCUM_ID = TestcaseAccumID()


struct DoctestsFlagID
end


const DOCTESTS_FLAG_ID = DoctestsFlagID()


"""
Enable doctest mode for the reporting.
Replaces all variable parts of the reports (timings, module versions etc) with placeholders.
Warning: non-pure, sets a global flag.
"""
function jute_doctest()
    task_local_storage(DOCTESTS_FLAG_ID, true)
end


"""
    runtests(; options=nothing)

Run the test suite.

This function has several side effects:

* it parses the command-line arguments, using them to build the dictionary of run options
  (see [Run options](@ref run_options_manual) in the manual for the list);
* it picks up and includes the test files, selected according to the options.

`options` must be a dictionary with the keys corresponding to some of the options
from the above list. If `options` is given, command-line arguments are not parsed.

Returns `0` if there are no failed tests, `1` otherwise.
"""
function runtests(tcs=nothing; options=nothing)
    run_options = build_run_options(args=ARGS, options=options)

    if tcs === nothing

        if haskey(task_local_storage(), TESTCASE_ACCUM_ID)
            tcs = task_local_storage(TESTCASE_ACCUM_ID)
            delete!(task_local_storage(), TESTCASE_ACCUM_ID)
        else
            runtests_dir = get_runtests_dir()
            test_files = find_test_files(runtests_dir, run_options[:test_file_postfix])

            if run_options[:verbosity] > 0
                println("Loading test files...")
            end

            tcs = task_local_storage(TESTCASE_ACCUM_ID, Any[]) do
                include_test_files!(
                    test_files, run_options[:dont_add_runtests_path] ? nothing : runtests_dir)
                task_local_storage(TESTCASE_ACCUM_ID)
            end
        end
    end

    doctest = haskey(task_local_storage(), DOCTESTS_FLAG_ID) && task_local_storage(DOCTESTS_FLAG_ID)

    res = runtests_internal(run_options, tcs, doctest)

    if doctest
        nothing
    else
        res
    end
end
