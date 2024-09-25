package haxe.cli;

import haxe.io.Bytes;
import asys.native.system.Process;
import haxe.frontend.Container;
import asys.native.filesystem.FilePath;
import hxargs.Args;

using StringTools;
using Lambda;

function main() {
    var lockFile  = null;

    final collected = [];
    final handler   = Args.generate([
        [ '--lock-file' ] => (path:String) -> {
            lockFile = FilePath.ofString(path);
        },

        _ => (arg:String) -> {
            collected.push(arg);
        }
    ]);

    switch Sys.args() {
        case []:
            trace('todo: help');
        case input:
            handler.parse(input);

            Container.populate(Sys.getCwd(), lockFile, (container, error) -> {
                switch error {
                    case null:   
                        container.compile(collected, (_, error) -> {
                            switch error {
                                case null:
                                    Sys.exit(0);
                                case exn:
                                    final bytes = Bytes.ofString(exn.message);

                                    Process.current.stdout.write(bytes, 0, bytes.length, (_, error) -> {
                                        Sys.exit(1);
                                    });
                            }
                        });
                    case exn:
                        final bytes = Bytes.ofString(exn.message);

                        Process.current.stdout.write(bytes, 0, bytes.length, (_, error) -> {
                            Sys.exit(1);
                        });
                }
            });
    }
}
