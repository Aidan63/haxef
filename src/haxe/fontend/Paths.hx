package haxe.fontend;

import asys.native.filesystem.FileSystem;
import asys.native.filesystem.FilePath;

class Paths {
    public static function getHomeFolder() {
        return switch Sys.systemName() {
            case 'Windows':
                FilePath.ofString(Sys.getEnv('APPDATA'));
            case _:
                FilePath.ofString(Sys.getEnv('HOME'));
        }
    }
    
    public static function getHaxelibLocation(cb:Callback<FilePath>) {
        switch Sys.getEnv('HAXELIB_LIBRARY_PATH') {
            case null:
                FileSystem.readString(getHomeFolder().add('.haxelib'), (data, error) -> {
                    switch error {
                        case null:
                            cb.success(data);
                        case exn:
                            cb.fail(exn);
                    }
                });
            case path:
                cb.success(path);
        }
    }
}