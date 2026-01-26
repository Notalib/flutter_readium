// Copyright (c) 2021 Mantano. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE.Iridium file.

import '../link.dart';
import '../publication.dart';

extension PublicationLists on Publication {
  /// Provides navigation to positions in the Publication content that correspond to the locations of
  /// page boundaries present in a print source being represented by this EPUB Publication.
  List<Link> get pageList => collectionLinks('pageList');

  /// Identifies fundamental structural components of the publication in order to enable Reading
  /// Systems to provide the User efficient access to them.
  List<Link> get landmarks => collectionLinks('landmarks');

  List<Link> get listOfAudioClips => collectionLinks('loa');
  List<Link> get listOfIllustrations => collectionLinks('loi');
  List<Link> get listOfTables => collectionLinks('lot');
  List<Link> get listOfVideoClips => collectionLinks('lov');
}
