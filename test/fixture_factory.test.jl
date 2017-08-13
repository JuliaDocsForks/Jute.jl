module FixtureFactory

using Jute


struct MyType
    x :: Int
end

Base.show(io::IO, val::MyType) = print(io, "MyType($(val.x))")


# Return one value, create label automatically
return_value = testcase() do
    ff = Jute.fixture_factory(; instant_teardown=true) do produce, v
        produce(v)
    end
    val = MyType(1)
    lval, rff = Jute.setup(ff, [val])
    @test Jute.unwrap_value(lval) == val
    @test Jute.unwrap_label(lval) == string(val)
end


# Return one value with a custom label
return_value_and_label = testcase() do
    ff = Jute.fixture_factory(; instant_teardown=true) do produce, v
        produce(v, "one")
    end
    val = MyType(1)
    lval, rff = Jute.setup(ff, [val])
    @test Jute.unwrap_value(lval) == val
    @test Jute.unwrap_label(lval) == "one"
end


# Return several values, create labels automatically
return_values = testcase() do
    ff = Jute.fixture_factory(; returns_iterable=true, instant_teardown=true) do produce, v1, v2
        produce([v1, v2])
    end
    val1 = MyType(1)
    val2 = MyType(2)
    lvals, rff = Jute.setup(ff, [val1, val2])
    @test map(Jute.unwrap_value, lvals) == [val1, val2]
    @test map(Jute.unwrap_label, lvals) == [string(val1), string(val2)]
end


# Return several values with custom labels
return_values_and_labels = testcase() do
    ff = Jute.fixture_factory(; returns_iterable=true, instant_teardown=true) do produce, v1, v2
        produce([v1, v2], ["one", "two"])
    end
    val1 = MyType(1)
    val2 = MyType(2)
    lvals, rff = Jute.setup(ff, [val1, val2])
    @test map(Jute.unwrap_value, lvals) == [val1, val2]
    @test map(Jute.unwrap_label, lvals) == ["one", "two"]
end


# Check that if delayed_teardown=true, teardown is not called right away
delayed_teardown = testcase() do
    teardown_started = false
    ff = Jute.fixture_factory() do produce, v
        produce(v)
        teardown_started = true
    end
    lval, rff = Jute.setup(ff, [MyType(1)])

    @test !teardown_started
    Jute.teardown(rff)
    @test teardown_started
end


# Check that if delayed_teardown=true, and the teardown part takes a long time,
# teardown() waits for it to finish.
long_delayed_teardown = testcase() do
    teardown_ended = false
    ff = Jute.fixture_factory() do produce, v
        produce(v)
        sleep(2)
        teardown_ended = true
    end
    lval, rff = Jute.setup(ff, [MyType(1)])

    @test !teardown_ended
    Jute.teardown(rff)
    @test teardown_ended
end


end