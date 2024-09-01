package haxe.frontend;

import json2object.JsonParser;
import asys.native.IoException;
import asys.native.filesystem.FileSystem;
import asys.native.filesystem.FilePath;

using StringTools;

class LibraryResolution {
    static function replaceVariable(name:String, cb:Callback<FilePath>) {
        if (name == null || name.length < 4) {
            cb.success(name);

            return;
        }

        var i = 0;
        while (i < name.length) {
            if (name.fastCodeAt(i) != '$'.code || i + 1 >= name.length || name.fastCodeAt(i + 1) != '{'.code) {
                i++;

                continue;
            }

            var j = i + 2;
            while (j < name.length){
                if (name.fastCodeAt(j) == '}'.code) {
                    final prefix = name.substring(0, i - 1);
                    final suffix = name.substring(j + 1);

                    switch name.substring(i + 2, j).trim() {
                        case 'haxelib':
                            Paths.getHaxelibLocation((path, error) -> {
                                switch error {
                                    case null:
                                        cb.success(prefix + path + suffix);
                                    case exn:
                                        cb.fail(exn);
                                }
                            });
                        case envvar:
                            switch Sys.getEnv(envvar) {
                                case null:
                                    cb.fail(new Exception('No environment variable with name "$envvar" found'));
                                case value:
                                    cb.success(prefix + value + suffix);
                            }
                    }

                    return;
                }

                j++;
            }
        }

        cb.success(name);
    }

    static function resolvePath(path:FilePath, cb:Callback<FilePath>) {
        var accumulated:FilePath = null;
        var toSearch = path;

        function replaceResult(path:FilePath, error:Exception) {
            switch error {
                case null:
                    accumulated = path.add(accumulated);

                    if ('' != (toSearch = toSearch.parent())) {
                        replaceVariable(toSearch.name(), replaceResult);
                    } else {
                        cb.success(accumulated);
                    }
                case exn:
                    cb.fail(exn);
            }
        }
        
        replaceVariable(toSearch.name(), replaceResult);
    }

    static function haxelibToDependency(folder:FilePath, cb:Callback<Dependency>) {
        FileSystem.readString(folder.add('haxelib.json'), (data, error) -> {
            switch error {
                case null:
                    final parser       = new JsonParser<Haxelib>();
                    final json         = parser.fromJson(data);
                    final dependencies = [];

                    cb.success(new Dependency(folder.add(json.classPath), json.version, dependencies, ''));
                case exn:
                    cb.fail(exn);
            }
        });
    }

    static function resolveHaxelib(haxelib:FilePath, name:String, cb:Callback<Dependency>) {
        // haxelib fallback resolution
        // - use the path in ${haxelib}/name/.dev if it exists
        // - else use the path in ${haxelib}/name/.current
        // - read the haxelib.json for dependencies

        FileSystem.readString(haxelib.add(name).add('.dev'), (devPath, error) -> {
            switch error {
                case null:
                    haxelibToDependency(devPath, cb);
                case exn:
                    if (Std.isOfType(exn, IoException) && (cast exn:IoException).type.match(FileNotFound)) {
                        FileSystem.readString(haxelib.add(name).add('.current'), (currentVersion, error) -> {
                            switch error {
                                case null:
                                    haxelibToDependency(haxelib.add(name).add(currentVersion), cb);
                                case exn:
                                    if (Std.isOfType(exn, IoException) && (cast exn:IoException).type.match(FileNotFound)) {
                                        cb.fail(new Exception('Failed to find .dev or .current file for "$name" haxelib', exn));
                                    } else {
                                        cb.fail(exn);
                                    }
                            }
                        });
                    } else {
                        cb.fail(exn);
                    }
            }
        });
    }

    public static function resolve(lockfile:LockFile, name:String, cb:Callback<Dependency>) {
        switch lockfile[name] {
            case null:
                Paths.getHaxelibLocation((path, error) -> {
                    switch error {
                        case null:
                            resolveHaxelib(path, name, cb);
                        case exn:
                            cb.fail(exn);
                    }
                });
            case found:
                resolvePath(found.path, (path, error) -> {
                    switch error {
                        case null:
                            final dependencies = [];
                            final toResolve    = found.dependencies.copy();

                            function resolveNext() {
                                switch toResolve.shift() {
                                    case null:
                                        cb.success(new Dependency(path, found.version, dependencies, ''));
                                    case next:
                                        resolve(lockfile, next, (dependency, error) -> {
                                            switch error {
                                                case null:
                                                    dependencies.push(dependency);

                                                    resolveNext();
                                                case exn:
                                                    cb.fail(exn);
                                            }
                                        });
                                }
                            }

                            resolveNext();
                        case exn:
                            cb.fail(exn);
                    }
                });
        }
    }
}