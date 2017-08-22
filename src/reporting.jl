const BT = Base.Test


struct Verbosity{T}
end


result_color(::Any, ::Any) = :default
result_color(::BT.Pass, ::Verbosity{2}) = :green
result_color(::BT.Fail, ::Any) = :red
result_color(::BT.Error, ::Any) = :yellow
result_color(::BT.Broken, ::Verbosity{2}) = :green
result_color(::ReturnValue, ::Verbosity{2}) = :blue


result_show(::BT.Pass, ::Verbosity{1}) = "."
result_show(::BT.Pass, ::Verbosity{2}) = "PASS"
result_show(::BT.Broken, ::Verbosity{1}) = "B"
result_show(::BT.Broken, ::Verbosity{2}) = "BROKEN"
result_show(::ReturnValue, ::Verbosity{1}) = "*"
# Since the `show` method for the result type will probably be defined in the test file,
# we need to use `invokelatest` here for it to be picked up.
result_show(result::ReturnValue, ::Verbosity{2}) = Base.invokelatest(string, result.value)
result_show(::BT.Fail, ::Verbosity{1}) = "F"
result_show(::BT.Fail, ::Verbosity{2}) = "FAIL"
result_show(::BT.Error, ::Verbosity{1}) = "E"
result_show(::BT.Error, ::Verbosity{2}) = "ERROR"


mutable struct ProgressReporter
    verbosity :: Int
    just_started :: Bool
    current_group :: Array{String, 1}
end


function progress_reporter(tcinfos, verbosity)
    ProgressReporter(verbosity, true, String[])
end


function common_elems_num(l1, l2)
    res = 0
    for i in 1:min(length(l1), length(l2))
        if l1[i] != l2[i]
            return res
        end
        res = i
    end
    return res
end


function progress_start_testcases!(progress::ProgressReporter, tcinfo::TestcaseInfo, fixtures_num)
    path, name = path_pair(tcinfo)
    verbosity = progress.verbosity

    if verbosity > 0 && path != progress.current_group

        if verbosity == 1 && !progress.just_started
            println()
        end

        if length(path) > 0
            cn = common_elems_num(progress.current_group, path)
            for i in cn+1:length(path)
                print("  " ^ (i - 1), path[i], verbosity == 1 ? ":" : "/")
                if verbosity == 1
                    if i != length(path)
                        print("\n")
                    else
                        print(" ")
                    end
                elseif verbosity == 2
                    print("\n")
                end
            end
        end

        progress.current_group = path
    end

    progress.just_started = false
end


function progress_start_testcase!(progress::ProgressReporter, tcinfo::TestcaseInfo, labels)
    if progress.verbosity >= 2
        tctag = tag_string(tcinfo, labels)
        path, name = path_pair(tcinfo)
        print("  " ^ length(path), tctag, " ")
    end
end


function progress_finish_testcase!(
        progress::ProgressReporter, tcinfo::TestcaseInfo, labels, outcome)

    verbosity = progress.verbosity
    if verbosity == 1
        for result in outcome.results
            print_with_color(
                result_color(result, Verbosity{verbosity}()),
                result_show(result, Verbosity{verbosity}()))
        end
    elseif verbosity >= 2
        elapsed_time = pprint_time(outcome.elapsed_time)

        print("($elapsed_time)")

        for result in outcome.results
            result_str = result_show(result, Verbosity{verbosity}())
            print_with_color(
                result_color(result, Verbosity{verbosity}()),
                " [$result_str]")
        end
        println()
    end
end


function progress_finish_testcases!(progress::ProgressReporter, tcinfo::TestcaseInfo)

end


function progress_start!(progress::ProgressReporter)
    if progress.verbosity > 0
        println("Platform: Julia $VERSION, Jute $(Pkg.installed("Jute"))")
        println("-" ^ 80)
    end

    tic()
end


function progress_finish!(progress::ProgressReporter, outcomes)

    full_time = toq()

    outcome_objs = [outcome for (tcinfo, labels, outcome) in outcomes]

    all_results = mapreduce(outcome -> outcome.results, vcat, [], outcome_objs)
    num_results = Dict(
        key => length(filter(result -> isa(result, tp), all_results))
        for (key, tp) in [
            (:pass, Union{BT.Pass, ReturnValue}), (:fail, BT.Fail), (:error, BT.Error)])

    all_success = (num_results[:fail] + num_results[:error] == 0)

    if progress.verbosity == 1
        println()
    end

    if progress.verbosity >= 1
        full_test_time = mapreduce(outcome -> outcome.elapsed_time, +, outcome_objs)
        full_time_str = pprint_time(full_time, meaningful_digits=3)
        full_test_time_str = pprint_time(full_test_time, meaningful_digits=3)

        println("-" ^ 80)
        println(
            "$(num_results[:pass]) tests passed, " *
            "$(num_results[:fail]) failed, " *
            "$(num_results[:error]) errored " *
            "in $full_time_str (total test time $full_test_time_str)")
    end

    for (tcinfo, labels, outcome) in outcomes
        if is_failed(outcome)
            println("=" ^ 80)
            println(tag_string(tcinfo, labels; full=true))

            if length(outcome.output) > 0
                println("Captured output:")
                println(outcome.output)
            end

            for result in outcome.results
                if is_failed(result)
                    println(result)
                end
            end
        end
    end

    all_success
end
