local gogs = import 'components/gogs/gogs.jsonnet';

local utils = {
    makeKey(key):: std.join('', std.flattenArrays([
        if std.codepoint(c) >= 97 then [std.asciiUpper(c)]
        else ['_', c]
        for c in std.stringChars(key)
    ])),

    toDot(key):: std.join('', 
        std.flattenArrays(
            [
                if std.codepoint(c) >= 97 then [c]
                else ['.', std.asciiLower(c)]
                for c in std.stringChars(key)
            ]
        )
    ),

    makeSection(key):: 
        local toDot = $.toDot(key);
        local split = std.split(toDot, '.');
        local length = std.length(split);
        if length <= 2 then toDot
        else std.format('%s.%s', [split[0], std.join('_', std.slice(split, 1, length, 1))]),

    walkConfig(config, parent):: if parent == '' then {
        main: {
            [$.makeKey(key)]: config[key]
            for key in std.objectFields(config)
            if std.type(config[key]) != 'object'
        },
        sections: {
            [$.makeSection(key)]: $.walkConfig(config, key)
            for key in std.objectFields(config)
            if std.type(config[key]) == 'object'
        },
    } else {
        [$.makeKey(key)]: config[parent][key],
        for key in std.objectFields(config[parent])
    },

    makeIniConfig(config):: std.manifestIni($.walkConfig(config, '')),
};

{
    out: utils.makeIniConfig(gogs.config.format()),
}