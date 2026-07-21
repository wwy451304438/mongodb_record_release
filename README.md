# mongodb_record_release

A rebar3 plugin that recursively scans Erlang header directories and generates a
record metadata module for `MongodbReleaseUtils`.

```erlang
{project_plugin_dirs, ["../mongodb_record_release"]},
{project_plugins, [mongodb_record_release]},

{mongodb_record_release_plugin, [
    {header_paths, ["include", "apps/game_server/include"]},
    {output_path, "apps/game_server/data"},
    {macros, []}
]}.
```

Run it directly with:

```shell
rebar3 mongodb_record_release
```

Run the generator before `rebar3 compile`. The consumer project intentionally
does not install a compile hook, so a plugin loading error cannot block unrelated
rebar3 commands.

The generator fails when no records are found or when the same record name is
defined by multiple scanned files. Header paths and optional EPP macros are used
while parsing included files. The output is only rewritten when its content has
changed.
# mongodb_record_release
