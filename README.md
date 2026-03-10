mongodb_record_release
=====

A rebar plugin

Build
-----

    $ rebar3 compile

Use
---

Add the plugin to your rebar config:

    {plugins, [
        {mongodb_record_release, {git, "https://host/user/mongodb_record_release.git", {tag, "0.1.0"}}}
    ]}.

Then just call your plugin directly in an existing application:


    $ rebar3 mongodb_record_release
    ===> Fetching mongodb_record_release
    ===> Compiling mongodb_record_release
    <Plugin Output>
# mongodb_record_release
