package haxe.frontend;

import hxml.ds.BuildFiles;
import hxml.ds.BuildSet;
import hxml.Hxml;
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

    public function library(name:String, cb:Callback<Dependency>) {
        switch name {
            case 'haxec':
                cb.fail(new Exception('"haxec" is a special library reserved for compiler'));
            case _:
                lockfile.resolve(name, cb);
        }
    }

    public function haxec(cb:Callback<Compiler>) {
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

    public function compile(arguments:Array<String>, cb:Callback<NoData>) {
        haxec((compiler, error) -> {
            if (error != null) {
                cb.fail(error);

                return;
            }

            final expanded = [];

            function expandDependency(dependency:Dependency) {
                expanded.push('-p');
                expanded.push(dependency.classPath);
                expanded.push('-D');
                expanded.push('${dependency.name}=${dependency.version}');

                for (extra in dependency.extraArguments) {
                    expanded.push(extra);
                }

                for (transient in dependency.dependencies) {
                    expandDependency(transient);
                }
            }

            function isLibraryFlag(flag:String) {
                if (flag == '-L') {
                    return true;
                }
                if (flag == '--lib') {
                    return true;
                }
                if (flag == '--library') {
                    return true;
                }

                return false;
            }

            function addHxml(path:String, cb:Callback<NoData>) {
                FileSystem.readString(path, (data, error) -> {
                    if (error != null) {
                        cb.fail(error);

                        return;
                    }

                    switch Hxml.parse(data).sets {
                        case [ set ]:

                            function processSet() {
                                while (set.lines.length > 0) {
                                    switch set.lines.shift() {
                                        case Flag(flag):
                                            expanded.push(flag);
                                        case Command(flag, lib) if (isLibraryFlag(flag)):
                                            library(lib, (dependency, error) -> {
                                                if (error != null) {
                                                    cb.fail(error);
                
                                                    return;
                                                }
                
                                                expandDependency(dependency);
                                                processSet();
                                            });

                                            return;
                                        case Command(flag, parameter):
                                            expanded.push(flag);
                                            expanded.push(parameter);
                                        case HxmlFile(path):
                                            addHxml(path, (_, error) -> {
                                                if (error != null) {
                                                    cb.fail(error);

                                                    return;
                                                }

                                                processSet();
                                            });

                                            return;
                                        case _:
                                            throw new Exception("Invalid hxml contents");
                                    }
                                }

                                cb.success(null);
                            }

                            processSet();
                        case _:
                            throw new Exception("Invalid hxml contents");
                    }
                });
            }

            function processArguments() {
                while (arguments.length > 0) {
                    switch arguments.shift() {
                        case flag if (isLibraryFlag(flag)):
                            library(arguments.shift(), (dependency, error) -> {
                                if (error != null) {
                                    cb.fail(error);

                                    return;
                                }

                                expandDependency(dependency);
                                processArguments();
                            });

                            return;
                        case hxml if (haxe.io.Path.extension(hxml) == 'hxml'):
                            addHxml(hxml, (_, error) -> {
                                if (error != null) {
                                    cb.fail(error);

                                    return;
                                }

                                processArguments();
                            });

                            return;
                        case other:
                            expanded.push(other);
                    }
                }

                trace(expanded);

                Process.open(
                    compiler.path.add('haxe'),
                    { env: [ 'HAXE_STD_PATH' => compiler.path.add('std') ], args: expanded, stdio: [ Ignore, Inherit, Inherit ] },
                    (proc, error) -> {
                    switch error {
                        case null:
                            proc.exitCode((code, error) -> {
                                proc.close((_, _) -> {
                                    cb.success(null);
                                });
                            });
                        case exn:
                            cb.fail(exn);
                    }
                });
            }

            processArguments();
        });
	}

    function find(cb:Callback<FilePath>) {
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