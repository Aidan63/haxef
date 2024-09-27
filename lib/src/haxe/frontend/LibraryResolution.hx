package haxe.frontend;

import cpp.asys.FilePathExtras;
import hxml.Hxml;
import json2object.JsonParser;
import asys.native.IoException;
import asys.native.filesystem.FileSystem;
import asys.native.filesystem.FilePath;

using StringTools;
using Lambda;

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

    public static function resolvePath(src:FilePath, cb:Callback<FilePath>) {
        var accumulated:FilePath = null;
        var toSearch = src;

        function replaceResult(path:FilePath, error:Exception) {
            switch error {
                case null:
                    accumulated = path.add(accumulated);

                    if ('' != path && '' != (toSearch = toSearch.parent())) {
                        replaceVariable(toSearch.name(), replaceResult);
                    } else {
                        if (src.isAbsolute()) {
                            cb.success(FilePath.ofString(FilePathExtras.getRootName(src) + FilePathExtras.getRootDirectory(src)).add(accumulated));
                        } else {
                            cb.success(accumulated);
                        }
                    }
                case exn:
                    cb.fail(exn);
            }
        }
        
        replaceVariable(toSearch.name(), replaceResult);
    }

    static function haxelibToDependency(lockfile:LockFile, name:String, folder:FilePath, cb:Callback<Dependency>) {
        FileSystem.readString(folder.add('haxelib.json'), (data, error) -> {
            switch error {
                case null:
                    final parser       = new JsonParser<Haxelib>();
                    final json         = parser.fromJson(data);
                    final dependencies = [];
                    final toResolve    = [ for (name in json.dependencies.keys()) name ];

                    function resolveNext() {
                        switch toResolve.shift() {
                            case null:
                                FileSystem.readString(folder.add('extraParams.hxml'), (data, error) -> {
                                    switch error {
                                        case null:
                                            switch Hxml.parse(data).sets {
                                                case [ set ]:
                                                    cb.success(new Dependency(name, json.version, folder, folder.add(json.classPath), dependencies, set.lines));
                                                case _:
                                                    cb.fail(new Exception('Failed to parse extra params'));
                                            }
                                        case exn:
                                            cb.success(new Dependency(name, json.version, folder, folder.add(json.classPath), dependencies, []));
                                    }
                                });
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

    static function resolveHaxelib(lockfile:LockFile, haxelib:FilePath, name:String, cb:Callback<Dependency>) {
        // haxelib fallback resolution
        // - use the path in ${haxelib}/name/.dev if it exists
        // - else use the path in ${haxelib}/name/.current
        // - read the haxelib.json for dependencies

        FileSystem.readString(haxelib.add(name).add('.dev'), (devPath, error) -> {
            switch error {
                case null:
                    haxelibToDependency(lockfile, name, devPath, cb);
                case exn:
                    if (Std.isOfType(exn, IoException) && (cast exn:IoException).type.match(FileNotFound)) {
                        FileSystem.readString(haxelib.add(name).add('.current'), (currentVersion, error) -> {
                            switch error {
                                case null:
                                    haxelibToDependency(lockfile, name, haxelib.add(name).add(currentVersion), cb);
                                case exn:
                                    if (Std.isOfType(exn, IoException) && (cast exn:IoException).type.match(FileNotFound)) {
                                        cb.fail(new Exception('Failed to find .dev or .current file for "$name" haxelib', exn));
                                    } else {
                                        cb.fail(exn);
                                    }
                            }
                        });
                    } else {
                        trace('failed...');
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
                            resolveHaxelib(lockfile, path, name, cb);
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
                                        cb.success(new Dependency(name, found.version, path, path, dependencies, []));
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