package haxe.cli;

import haxe.io.Path;
import hxml.Hxml;
import hxargs.Args;

using StringTools;
using Lambda;

function main() {
    final collected = [];
    final handler   = Args.generate([
        [ '--lock-file' ] => (path:String) -> {
            trace('lock file at $path');
        },

        _ => (arg:String) -> {
            collected.push(arg);
        }
    ]);

    switch Sys.args() {
        case []:
            trace('help');
        case input:
            handler.parse(input);

            while (collected.length > 0) {
                switch collected.shift() {
                    case '-L', '-lib', '--library':
                        //
                    case hxml if (Path.extension(hxml) == 'hxml'):
                        //
                    case other:
                        //
                }
            }

            final hxml = Hxml.parse(collected.join(' '));

            trace(hxml.sets);
    }
}
