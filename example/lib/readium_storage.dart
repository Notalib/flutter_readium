import 'dart:io';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';

abstract class ReadiumStorage {
  const ReadiumStorage._();

  // Do not change these after app is released.
  static const _rootDirName = 'r2_dl';
  static const _pubsDirName = 'r2_dl_publications';
  static const _pubCachedDirName = 'r2_cached_publication';

  static final Future<Directory> rootDir = () async {
    final appDir = await getApplicationSupportDirectory();
    return Directory(join(appDir.path, _rootDirName)).create();
  }();

  static final Future<String> publicationsRelativeDirPath = () async {
    final path = join(_rootDirName, _pubsDirName);
    return path;
  }();

  static final Future<Directory> publicationsDir = () async {
    final dir = await rootDir;
    return Directory(join(dir.path, _pubsDirName)).create();
  }();

  static final Future<String> publicationsDirPath = () async {
    final dir = await publicationsDir;
    return dir.path;
  }();

  static final Future<Directory> publicationCacheDir = () async {
    final dir = await rootDir;

    return Directory(join(dir.path, _pubCachedDirName));
  }();

  static final Future<String> publicationCacheDirPath = () async {
    final dir = await publicationCacheDir;
    return dir.path;
  }();
}
