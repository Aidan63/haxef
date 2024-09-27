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

using Lambda;
using haxe.frontend.LibraryResolution;

private typedef CompilationUnit = Array<String>;

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

            final builds: Array<CompilationUnit> = [];

            function latest() {
                if (builds.length == 0) {
                    return builds[0] = [];
                }

                return builds[builds.length - 1];
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

                                final array = latest();

                                function expand(d:Dependency) {
                                    array.push('-p');
                                    array.push(d.classPath);
                                    array.push('-D');
                                    array.push('${d.name}=${d.version}');

                                    for (extra in d.extraArguments) {
                                        switch extra {
                                            case Flag(flag):
                                                array.push(flag);
                                            case Command(flag, parameter):
                                                array.push(flag);
                                                array.push(parameter);
                                            case _:
                                                cb.fail(new Exception('Invalid hxml element in extra parameters'));

                                                return;
                                        }
                                    }

                                    for (transient in d.dependencies) {
                                        expand(d);
                                    }
                                }

                                expand(dependency);
                                processArguments();
                            });

                            return;
                        case hxml if (haxe.io.Path.extension(hxml) == 'hxml'):
                            resolveHxml(hxml, (sets, error) -> {
                                if (error != null) {
                                    cb.fail(error);

                                    return;
                                }

                                switch sets {
                                    case [ single ]:
                                        final array = latest();
                                        for (line in single.lines) {
                                            switch line {
                                                case Flag(flag):
                                                    array.push(flag);
                                                case Command(flag, parameter):
                                                    array.push(flag);
                                                    array.push(parameter);
                                                case _:
                                                    cb.fail(new Exception('Invalid hxml element in expanded hxml'));

                                                    return;
                                            }
                                        }
                                    case many:
                                        for (set in many) {
                                            final args = set.lines.map(line -> {
                                                return switch line {
                                                    case Flag(flag):
                                                        [ flag ];
                                                    case Command(flag, parameter):
                                                        [ flag, parameter ];
                                                    case _:
                                                        throw new Exception('Invalid hxml element in expanded hxml');
                                                }
                                            }).flatten();

                                            builds.push(args);
                                        }
                                }

                                processArguments();
                            });

                            return;
                        case other:
                            latest().push(other);
                    }
                }

                function build() {
                    switch builds.shift() {
                        case null:
                            cb.success(null);
                        case args:
                            Process.open(
                                compiler.path.add('haxe'),
                                { env: [ 'HAXE_STD_PATH' => compiler.path.add('std') ], args: args, stdio: [ Ignore, Inherit, Inherit ] },
                                (proc, error) -> {
                                switch error {
                                    case null:
                                        proc.exitCode((code, error) -> {
                                            proc.close((_, _) -> {
                                                switch code {
                                                    case 0:
                                                        build();
                                                    case errno:
                                                        cb.fail(new Exception('Compilation resulted in a non zero exit code'));
                                                }
                                            });
                                        });
                                    case exn:
                                        cb.fail(exn);
                                }
                            });
                    }
                }

                build();
            }

            processArguments();
        });
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

    function resolveHxml(path:FilePath, cb:Callback<Array<BuildSet>>) {
        FileSystem.readString(path, (data, error) -> {
            switch error {
                case null:
                    final hxml = Hxml.parse(data);
                    final sets = [];

                    function process() {
                        if (hxml.sets.length == 0) {
                            cb.success(sets);

                            return;
                        }

                        resolveBuildSet(hxml.sets.shift(), [], (build, error) -> {
                            switch error {
                                case null:
                                    sets.push(build);

                                    process();
                                case exn:
                                    cb.fail(exn);
                            }
                        });
                    }

                    process();
                case exn:
                    cb.fail(exn);
            }
        });
    }

    function expandDependency(dependency:Dependency, lines:Array<hxml.ds.Line>) {
        lines.push(Command('-p', dependency.classPath));
        lines.push(Command('-D', '${dependency.name}=${dependency.version}'));

        for (extra in dependency.extraArguments) {
            lines.push(extra);
        }

        for (transient in dependency.dependencies) {
            expandDependency(transient, lines);
        }
    }

    function resolveBuildSet(set:BuildSet, lines:Array<hxml.ds.Line>, cb:Callback<BuildSet>) {
        while (set.lines.length > 0) {
            switch set.lines.shift() {
                case Flag(flag):
                    lines.push(Flag(flag));
                case Command(flag, lib) if (isLibraryFlag(flag)):
                    library(lib, (dependency, error) -> {
                        if (error != null) {
                            cb.fail(error);

                            return;
                        }

                        expandDependency(dependency, lines);
                        resolveBuildSet(set, lines, cb);
                    });
                case Command(flag, parameter):
                    lines.push(Command(flag, parameter));
                case HxmlFile(path):
                    resolveHxml(path, (sets, error) -> {
                        if (error != null) {
                            cb.fail(error);

                            return;
                        }

                        switch sets {
                            case [ set ]:
                                for (line in set.lines) {
                                    lines.push(line);
                                }

                                resolveBuildSet(set, lines, cb);
                            case _:
                                cb.fail(new Exception("Inner hxml file contained multiple build sets"));
                        }
                    });
                case _:
                    cb.fail(new Exception("Unexpected hxml line"));

                    return;
            }
        }

        cb.success({ lines: lines, index: 0, source: '' });
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