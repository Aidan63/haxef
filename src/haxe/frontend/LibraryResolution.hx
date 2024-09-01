package haxe.frontend;

import asys.native.IoException;
import asys.native.filesystem.FileSystem;
import haxe.exceptions.NotImplementedException;
import asys.native.filesystem.FilePath;
import haxe.frontend.LockFile.Library;

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

    public static function resolve(lockfile:LockFile, name:String, cb:Callback<Dependency>) {
        switch lockfile[name] {
            case null:
                Paths.getHaxelibLocation((path, error) -> {
                    switch error {
                        case null:
                            FileSystem.readString(path.add(name).add('.dev'), (devPath, error) -> {
                                switch error {
                                    case null:
                                        trace(devPath);

                                        cb.fail(new NotImplementedException());
                                    case exn:
                                        if (Std.isOfType(exn, IoException) && (cast exn:IoException).type.match(FileNotFound)) {
                                            //
                                        } else {
                                            cb.fail(exn);
                                        }
                                }
                            });
                        case exn:
                            cb.fail(exn);
                    }
                });
            case found:
                resolvePath(found.path, (path, error) -> {
                    switch error {
                        case null:
                            trace(path);
        
                            cb.fail(new NotImplementedException());
                        case exn:
                            cb.fail(exn);
                    }
                });
        }
    }
}