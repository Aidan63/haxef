package haxe.frontend;

import haxe.io.Bytes;
import json2object.JsonParser;
import asys.native.filesystem.FileSystem;
import asys.native.filesystem.FilePath;
import asys.native.system.Process;
import haxe.frontend.LockFile;

using haxe.frontend.LibraryResolution;

class Container {
    static final parser = new JsonParser<LockFile>();

    private static function populateFromGlobalLock(container:LockFile, cb:Callback<Container>) {
        // 3. Update the container from the global lock file.

        final global = switch Sys.getEnv('HAXELIB_OVERRIDE_PATH') {
            case null:
                Paths.getHomeFolder().add('haxelib-global-lock.json');
            case path:
                path;
        }

        FileSystem.readString(global, (data, error) -> {
            if (error == null) {
                for (name => lib in parser.fromJson(data)) {
                    container[name] = lib;
                }
            }

            cb.success(new Container(container));
        });
    }

    private static function populateFromLockFile(container:LockFile, lock:FilePath, cb:Callback<Container>) {
        // 2. Update the container with the provided lock files content.

        if (null == lock) {
            populateFromGlobalLock(container, cb);

            return;
        }

        FileSystem.readString(lock, (data, error) -> {
            switch error {
                case null:
                    for (name => lib in parser.fromJson(data)) {
                        container[name] = lib;
                    }

                    populateFromGlobalLock(container, cb);
                case exn:
                    cb.fail(exn);
            }
        });
    }

    public static function populate(search:FilePath, lock:FilePath, cb:Callback<Container>) {
        final container = new LockFile();

        // 1. Look for a lock file starting at the search path and working upwards.

        var toSearch = search;

        function searchResult(data : String, error : Exception) {
            switch error {
                case null:
                    for (name => lib in parser.fromJson(data)) {
                        container[name] = lib;
                    }

                    populateFromLockFile(container, lock, cb);
                case exn:
                    toSearch = toSearch.parent();

                    if ('' == toSearch) {
                        populateFromLockFile(container, lock, cb);
                    } else {
                        FileSystem.readString(toSearch.add('haxelib-lock.json'), searchResult);
                    }
            }
        }

        FileSystem.readString(search.add('haxelib-lock.json'), searchResult);
    }

    final lockfile:LockFile;

    function new(lockfile) {
        this.lockfile = lockfile;
    }

    public function resolve(name:String, cb:Callback<Dependency>) {
        lockfile.resolve(name, cb);
    }

    public function compiler(cb:Callback<Compiler>) {
        switch lockfile['haxec'] {
            case null:
                switch Sys.getEnv('HAXEC_PATH') {
                    case null:
                        find((path, error) -> {
                            switch error {
                                case null:
                                    cb.success(new Compiler(None, path));
                                case exn:
                                    cb.fail(exn);
                            }
                        });
                    case path:
                        cb.success(new Compiler(None, path));
                }
            case found:
                LibraryResolution.resolvePath(found.path, (resolved, error) -> {
                    switch error {
                        case null:
                            cb.success(new Compiler(Some(found.version), resolved));
                        case exn:
                            cb.fail(exn);
                    }
                });
        }
    }

    private function find(cb:Callback<FilePath>) {
        Process.open(
            'powershell', {
                args: [ '-command', '(Get-Command haxe.exe).Path' ],
                stdio : [ Ignore, PipeWrite, Ignore ]
            },
            (proc, error) -> {
                switch error {
                    case null:
                        final buffer = Bytes.alloc(8196);

                        proc.stdout.read(buffer, 0, buffer.length, (count, error) -> {
                            switch error {
                                case null:
                                    proc.exitCode((code, error) -> {
                                        switch error {
                                            case null:
                                                proc.close((_, _) -> {
                                                    if (code == 0) {
                                                        cb.success(buffer.sub(0, count).toString());
                                                    } else {
                                                        cb.fail(new Exception('Non zero exit code $code'));
                                                    }
                                                });
                                            case exn:
                                                proc.close((_, _) -> {
                                                    cb.fail(exn);
                                                });
                                        }
                                    });
                                case exn:
                                    proc.exitCode((_, _) -> {
                                        proc.close((_, _) -> {
                                            cb.fail(exn);
                                        });
                                    });
                            }
                        });
                    case exn:
                        cb.fail(exn);
                }
            });
    }
}