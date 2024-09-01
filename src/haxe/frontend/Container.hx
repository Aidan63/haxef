package haxe.frontend;

import json2object.JsonParser;
import asys.native.filesystem.FileSystem;
import asys.native.filesystem.FilePath;
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
}