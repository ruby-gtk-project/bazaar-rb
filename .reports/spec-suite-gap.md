# RSpec suite — cannot load, and has no examples anyway

The dev-shell banner names:

```sh
ruby -e 'require "rspec/core"; exit RSpec::Core::Runner.run(["--format", "progress", "--require", "spec_helper", "spec"])'
```

Running it fails before any example runs:

```
Failure/Error: require "kettle/test/rspec"
LoadError:
  cannot load such file -- kettle/test/rspec
# ./spec/spec_helper.rb:23:in '<top (required)>'
```

`spec/spec_helper.rb` requires `kettle/test/rspec` (from the `kettle-test`
gem, a dev dependency declared in `bazaar-rb.gemspec`). `flake.nix`'s
devShell only installs `pkgs.rubyPackages_3_4.rspec` — it does not install
`kettle-test`, `kettle-soup-cover`, or anything else from the gemspec's
`kettle-dev`/`kettle-test` development-dependency stack, and `nix/Gemfile`
(what `bundlerEnv` actually builds, per the flake's own comment) is deliberately
runtime-only, so `bundle exec rspec` fails too (`rspec-core is not currently
included in the bundle`).

This is an environment/scaffolding gap, not a port regression: `spec/`
contains only `spec_helper.rb` and `README.md` — **zero `*_spec.rb` files**
exist on this branch. Even with `kettle/test/rspec` loadable, the run would
report "0 examples, 0 failures". No port behavior is gated on this suite
today; all behavioral coverage lives in `test/drive_bazaar.rb` and
`test/drive_library.rb`, which this round ran successfully (see
`test-parity.md` and this round's drive output: `DRIVE OK`, 44 plain checks
+ 42 driven checks, all passing).

Left as-is rather than silently patched around: adding `kettle-test` (and
`kettle-soup-cover`) to the flake's devShell, or writing `*_spec.rb` files, is
future work for whoever owns the kettle-jem scaffolding on this fork, not
something to paper over here.
