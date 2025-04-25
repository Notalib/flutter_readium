import UIKit

extension UIDevice {
  var totalDiskSpaceInMB: Double {
    return Double(totalDiskSpaceInBytes / (1024 * 1024))
  }

  var freeDiskSpaceInMB: Double {
    return Double(freeDiskSpaceInBytes / (1024 * 1024))
  }

  var usedDiskSpaceInMB: Double {
    return Double(usedDiskSpaceInBytes / (1024 * 1024))
  }

  //MARK: Get raw value
  var totalDiskSpaceInBytes: Int64 {
    guard
      let systemAttributes = try? FileManager.default.attributesOfFileSystem(
        forPath: NSHomeDirectory() as String),
      let space = (systemAttributes[FileAttributeKey.systemSize] as? NSNumber)?.int64Value
    else { return 0 }
    return space
  }

  var usedDiskSpaceInBytes: Int64 {
    return totalDiskSpaceInBytes - freeDiskSpaceInBytes
  }

  /*
     Total available capacity in bytes for "Important" resources, including space expected to be cleared by purging non-essential and cached resources. "Important" means something that the user or application clearly expects to be present on the local system, but is ultimately replaceable. This would include items that the user has explicitly requested via the UI, and resources that an application requires in order to provide functionality.
     Examples: A video that the user has explicitly requested to watch but has not yet finished watching or an audio file that the user has requested to download.
     This value should not be used in determining if there is room for an irreplaceable resource. In the case of irreplaceable resources, always attempt to save the resource regardless of available capacity and handle failure as gracefully as possible.
     */
  var freeDiskSpaceInBytes: Int64 {
    if #available(iOS 11.0, *) {
      if let space = try? URL(fileURLWithPath: NSHomeDirectory() as String).resourceValues(
        forKeys: [URLResourceKey.volumeAvailableCapacityForImportantUsageKey])
        .volumeAvailableCapacityForImportantUsage
      {
        return space
      } else {
        return 0
      }
    } else {
      if let systemAttributes = try? FileManager.default.attributesOfFileSystem(
        forPath: NSHomeDirectory() as String),
        let freeSpace = (systemAttributes[FileAttributeKey.systemFreeSize] as? NSNumber)?.int64Value
      {
        return freeSpace
      } else {
        return 0
      }
    }
  }
}
